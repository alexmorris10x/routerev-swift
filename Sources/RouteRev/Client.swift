import Foundation

/// Owns identity, sessions, and the queue. All mutation happens on this actor.
actor Client {
    struct Config: Sendable {
        let key: String
        let endpoint: URL
        let bundleId: String
        let appVersion: String?
        let flushInterval: TimeInterval
        let batchSize: Int
        let maxQueued: Int
    }

    static let sessionTimeout: TimeInterval = 30 * 60

    private let config: Config
    private let store: RouteRevStore
    private let transport: RouteRevTransport
    private let now: @Sendable () -> Date

    nonisolated let installId: String
    private var userId: String?
    private var sessionId: String
    private var lastActivity: Date
    private var queue: [Event]
    private var isFlushing = false
    private var failures = 0
    private var retryAfter: Date?
    private var screenWidth: Int?
    private var flushTask: Task<Void, Never>?

    init(config: Config, store: RouteRevStore, transport: RouteRevTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.store = store
        self.transport = transport
        self.now = now

        if let existing = store.loadInstallId() {
            installId = existing
        } else {
            installId = UUID().uuidString.lowercased()
            store.saveInstallId(installId)
        }
        userId = store.loadValue("userId")
        sessionId = store.loadValue("sessionId") ?? UUID().uuidString.lowercased()
        let last = store.loadValue("lastActivity").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        lastActivity = last ?? .distantPast
        queue = store.loadQueue()
    }

    func setScreenWidth(_ width: Int?) {
        screenWidth = width
    }

    // MARK: Events

    func record(_ kind: Event.Kind, name: String?, props: [String: RouteRevValue], at date: Date, id: String? = nil) {
        let event = Event(
            id: id ?? UUID().uuidString.lowercased(),
            type: kind.rawValue,
            name: name.map { String($0.prefix(120)) },
            ts: Event.timestamp(date),
            platform: "ios",
            visitorId: installId,
            sessionId: session(at: date),
            userId: userId,
            url: kind == .screen ? screenURL(name) : nil,
            screenWidth: screenWidth,
            language: Locale.preferredLanguages.first.map { String($0.prefix(35)) },
            timezone: TimeZone.current.identifier,
            appVersion: config.appVersion.map { String($0.prefix(32)) },
            props: Event.sanitize(props)
        )
        queue.append(event)
        if queue.count > config.maxQueued {
            queue.removeFirst(queue.count - config.maxQueued)
        }
        store.saveQueue(queue)
        if queue.count >= config.batchSize {
            Task { await self.flush() }
        }
    }

    /// Records `first_open` once per install, carrying the Apple Search Ads token when there is one.
    /// Returns false when this install already sent it.
    @discardableResult
    func recordFirstOpen(attributionToken: String?, at date: Date) -> Bool {
        guard store.loadValue("firstOpenSent") == nil else { return false }
        store.saveValue("firstOpenSent", "1")
        // A fixed ID per install: if the app is killed before the flag above is saved and this runs
        // again, the collector drops the repeat as a duplicate
        record(.goal, name: "first_open", props: [:], at: date, id: "fo_\(installId)")
        if let token = attributionToken, !token.isEmpty, token.count <= 4096, let last = queue.indices.last {
            queue[last].attributionToken = token
            store.saveQueue(queue)
        }
        return true
    }

    func identify(_ id: String, at date: Date) {
        let trimmed = String(id.prefix(128))
        // Apps often identify on every launch or view update; later events already carry the user ID
        guard trimmed != userId else { return }
        userId = trimmed
        store.saveValue("userId", trimmed)
        record(.identify, name: nil, props: [:], at: date)
    }

    /// Forgets the signed-in user and starts a new session; the install ID stays.
    func reset() {
        userId = nil
        store.saveValue("userId", nil)
        sessionId = UUID().uuidString.lowercased()
        lastActivity = .distantPast
        store.saveValue("sessionId", sessionId)
    }

    var pendingCount: Int { queue.count }
    var currentUserId: String? { userId }

    // MARK: Sessions

    private func session(at date: Date) -> String {
        if date.timeIntervalSince(lastActivity) > Self.sessionTimeout {
            sessionId = UUID().uuidString.lowercased()
            store.saveValue("sessionId", sessionId)
        }
        lastActivity = max(lastActivity, date)
        store.saveValue("lastActivity", String(lastActivity.timeIntervalSince1970))
        return sessionId
    }

    private func screenURL(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let path = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "app://\(config.bundleId)/\(path)"
    }

    // MARK: Delivery

    func startFlushing() {
        guard flushTask == nil else { return }
        let interval = config.flushInterval
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.flush()
            }
        }
    }

    func stopFlushing() {
        flushTask?.cancel()
        flushTask = nil
    }

    /// Sends queued events in batches. Keeps them on network or server errors;
    /// drops a batch the collector rejects as invalid so one bad event can't block the queue.
    func flush() async {
        guard !isFlushing, !queue.isEmpty else { return }
        if let retryAfter, now() < retryAfter { return }
        isFlushing = true
        defer { isFlushing = false }

        while !queue.isEmpty {
            let batch = Array(queue.prefix(min(config.batchSize, 100)))
            let status: Int
            do {
                let body = try JSONEncoder().encode(Batch(key: config.key, events: batch))
                status = try await transport.send(body, to: config.endpoint)
            } catch {
                backOff()
                return
            }

            switch status {
            case 200..<300, 400, 404, 413, 422:
                // Delivered, or permanently unacceptable: either way it must leave the queue
                let sent = Set(batch.map(\.id))
                queue.removeAll { sent.contains($0.id) }
                store.saveQueue(queue)
                failures = 0
                retryAfter = nil
            default:
                backOff()
                return
            }
        }
    }

    private func backOff() {
        failures += 1
        let delay = min(pow(2, Double(failures)) * 5, 300)
        retryAfter = now().addingTimeInterval(delay)
    }
}

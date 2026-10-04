import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AdServices)
import AdServices
#endif

/// First-party, revenue-attributed analytics for iOS apps.
///
/// ```swift
/// RouteRev.configure(key: "YOUR_PRODUCT_KEY", endpoint: URL(string: "https://e.example.com/e")!)
/// RouteRev.screen("Paywall")
/// RouteRev.goal("sign_up", ["method": "apple"])
/// RouteRev.identify(user.id)
/// // Link RevenueCat purchases to this install:
/// Purchases.shared.attribution.setAttributes(RouteRev.revenueCatAttributes)
/// ```
///
/// Every call is fire-and-forget and safe from any thread. Nothing is sent until `configure`,
/// and nothing is sent while collection is disabled.
public enum RouteRev {
    public struct Options: Sendable {
        /// Seconds between background flushes.
        public var flushInterval: TimeInterval = 15
        /// Events per request; the collector accepts at most 100.
        public var batchSize: Int = 20
        /// Oldest events are dropped beyond this many unsent events.
        public var maxQueuedEvents: Int = 1000
        /// Set false to send nothing (for example, until the user consents): no events, no
        /// `first_open`, no Search Ads token and no queued delivery. Set `RouteRev.isEnabled = true`
        /// later to start; `first_open` is then sent once for the install.
        public var enabled: Bool = true
        /// Sends Apple's Search Ads attribution token with the install's first event, so installs
        /// from Search Ads are credited to their campaign and keyword. No IDFA or ATT prompt involved.
        public var searchAdsAttribution: Bool = true

        public init() {}
    }

    /// Call once at launch with the product's public key and its collector URL: the product's own
    /// subdomain, CNAME'd to RouteRev, such as `https://e.example.com/e`. RouteRev has no built-in
    /// server address, so a shipped app never depends on a RouteRev domain.
    public static func configure(key: String, endpoint: URL, options: Options = Options()) {
        configure(
            key: key, endpoint: endpoint, options: options,
            store: DeviceStore(), transport: URLSessionTransport(), searchAdsToken: { searchAdsToken() }
        )
    }

    /// The public configure with its storage, transport and Search Ads token injectable for tests.
    static func configure(
        key: String, endpoint: URL, options: Options,
        store: RouteRevStore, transport: RouteRevTransport,
        searchAdsToken: @escaping @Sendable () -> String?,
        bundle: Bundle = .main
    ) {
        let config = configuration(key: key, endpoint: endpoint, options: options, bundle: bundle)
        let state = self.state
        let client = Client(config: config, store: store, transport: transport, isEnabled: { state.enabled })
        let searchAds = options.searchAdsAttribution
        let token: @Sendable () -> String? = { searchAds ? searchAdsToken() : nil }
        let firstOpen = FirstOpen(client: client, launch: Date(), attributionToken: token)
        install(client, enabled: options.enabled, firstOpen: firstOpen)
    }

    // Builds the client configuration, without storage or transport side effects.
    static func configuration(key: String, endpoint: URL, options: Options = Options(), bundle: Bundle = .main) -> Client.Config {
        Client.Config(
            key: key,
            endpoint: endpoint,
            bundleId: bundle.bundleIdentifier ?? "app",
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            flushInterval: options.flushInterval,
            batchSize: max(1, min(options.batchSize, 100)),
            maxQueued: max(100, options.maxQueuedEvents)
        )
    }

    /// Records the answer to "How did you hear about us?" as the install's source.
    /// Use the answers in `AcquisitionSource` so they match the campaign naming convention.
    public static func acquisitionSurvey(_ answer: AcquisitionSource) {
        goal("acquisition_survey", ["answer": .string(answer.rawValue)])
    }

    /// Records a screen view. Screens appear under "Top pages" as `/ScreenName`.
    public static func screen(_ name: String, _ props: [String: RouteRevValue] = [:]) {
        send(.screen, name: name, props: props)
    }

    /// Records a goal, such as `sign_up` or `paywall_viewed`.
    public static func goal(_ name: String, _ props: [String: RouteRevValue] = [:]) {
        send(.goal, name: name, props: props)
    }

    /// Links this install to your own user ID, so web visits and iOS usage join up.
    public static func identify(_ userId: String) {
        guard !userId.isEmpty, let client = state.client else { return }
        let date = Date()
        Task { await client.identify(userId, at: date) }
    }

    /// Call on sign-out. Keeps the install ID; clears the user and starts a new session.
    /// Works while collection is disabled, since it sends nothing.
    public static func reset() {
        guard let client = state.configuredClient else { return }
        Task { await client.reset() }
    }

    /// Sends queued events now. Useful before the app is suspended.
    public static func flush() async {
        await state.client?.flush()
    }

    /// Stable per install (stored in the Keychain). Set it as the RevenueCat
    /// subscriber attribute `rr_install_id` so purchases attribute to this install.
    public static var installId: String? { state.installId }

    /// RevenueCat subscriber attributes for this install, or empty before configure.
    /// Set with `Purchases.shared.attribution.setAttributes(RouteRev.revenueCatAttributes)`.
    public static var revenueCatAttributes: [String: String] { state.revenueCatAttributes }

    /// Turns collection off or on at runtime. While false, nothing is sent: calls are dropped,
    /// queued events wait on the device, and `first_open` waits. Setting it true sends `first_open`
    /// once for the install if it hasn't been sent. Either this or `Options.enabled` set to false
    /// disables collection, including when set before `configure`. Not persisted: set it at each launch.
    public static var isEnabled: Bool {
        get { state.enabled }
        set { state.setEnabled(newValue) }
    }

    // MARK: - Internals

    static let state = State()

    /// The install's `first_open`, waiting until collection is enabled. Sent at most once per install.
    struct FirstOpen: Sendable {
        let client: Client
        let launch: Date
        let attributionToken: @Sendable () -> String?

        func start() -> Task<Void, Never> {
            Task.detached(priority: .utility) {
                await client.recordFirstOpen(attributionToken: attributionToken(), at: launch)
            }
        }
    }

    // Every mutable field is accessed under lock; Client is an actor.
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _client: Client?
        private var _installId: String?
        private var _enabled = true
        private var observers: [NSObjectProtocol] = []
        private var pendingFirstOpen: FirstOpen?
        private var _firstOpenTask: Task<Void, Never>?

        var client: Client? { locked { _enabled ? _client : nil } }
        /// The configured client even while disabled, for calls that send nothing.
        var configuredClient: Client? { locked { _client } }
        var installId: String? { locked { _installId } }
        var revenueCatAttributes: [String: String] {
            locked { _installId.map { ["rr_install_id": $0] } ?? [:] }
        }
        var enabled: Bool { locked { _enabled } }
        /// The most recent `first_open` delivery started, for tests.
        var firstOpenTask: Task<Void, Never>? { locked { _firstOpenTask } }

        func setEnabled(_ enabled: Bool) {
            locked {
                _enabled = enabled
                startFirstOpenIfEnabled()
            }
        }

        /// Installs a configured client. Collection stays off if either the app already set
        /// `isEnabled = false` or `enabled` (from `Options`) is false.
        func set(_ client: Client, installId: String, enabled: Bool, observers: [NSObjectProtocol], firstOpen: FirstOpen? = nil) {
            locked {
                self.observers.forEach(NotificationCenter.default.removeObserver)
                _client = client
                _installId = installId
                _enabled = _enabled && enabled
                self.observers = observers
                pendingFirstOpen = firstOpen
                startFirstOpenIfEnabled()
            }
        }

        /// Forgets the configured client and settings, for tests.
        func clear() {
            locked {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                _client = nil
                _installId = nil
                _enabled = true
                pendingFirstOpen = nil
                _firstOpenTask = nil
            }
        }

        // Call under lock. Starting the task only schedules it, so holding the lock is safe.
        private func startFirstOpenIfEnabled() {
            guard _enabled, let firstOpen = pendingFirstOpen else { return }
            pendingFirstOpen = nil
            _firstOpenTask = firstOpen.start()
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }
    }

    static func install(_ client: Client, enabled: Bool, firstOpen: FirstOpen? = nil) {
        var observers: [NSObjectProtocol] = []
        #if canImport(UIKit) && !os(watchOS)
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            // NotificationCenter's .main queue guarantees this synchronous callback is
            // on the main thread. Make that existing guarantee explicit to Swift 6.
            MainActor.assumeIsolated {
                let application = UIApplication.shared
                let background = BackgroundTask()
                background.id = application.beginBackgroundTask(withName: "RouteRev flush") {
                    background.end(application)
                }
                Task {
                    // Sends nothing while collection is disabled
                    await client.flush()
                    background.end(application)
                }
            }
        })
        Task { @MainActor in
            await client.setScreenWidth(Int(UIScreen.main.bounds.width))
        }
        #endif
        state.set(client, installId: client.installId, enabled: enabled, observers: observers, firstOpen: firstOpen)
        Task { await client.startFlushing() }
    }

    #if canImport(UIKit) && !os(watchOS)
    /// Holds a background task ID so both the expiration handler and the flush can end it once.
    @MainActor final class BackgroundTask {
        var id = UIBackgroundTaskIdentifier.invalid

        func end(_ application: UIApplication) {
            guard id != .invalid else { return }
            application.endBackgroundTask(id)
            id = .invalid
        }
    }
    #endif

    /// Apple's attribution token (iOS 14.3+); nil on the simulator, macOS, or when AdServices fails.
    static func searchAdsToken() -> String? {
        #if canImport(AdServices) && os(iOS) && !targetEnvironment(simulator)
        if #available(iOS 14.3, *) {
            return try? AAAttribution.attributionToken()
        }
        #endif
        return nil
    }

    private static func send(_ kind: Event.Kind, name: String, props: [String: RouteRevValue]) {
        guard !name.isEmpty, let client = state.client else { return }
        let date = Date()
        Task { await client.record(kind, name: name, props: props, at: date) }
    }
}

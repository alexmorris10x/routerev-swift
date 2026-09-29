import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// First-party, revenue-attributed analytics for iOS apps.
///
/// ```swift
/// RouteRev.configure(key: "pk_memex_…", endpoint: URL(string: "https://e.trymemex.com/e")!)
/// RouteRev.screen("Paywall")
/// RouteRev.goal("sign_up", ["method": "apple"])
/// RouteRev.identify(user.id)
/// // Link RevenueCat purchases to this install:
/// Purchases.shared.attribution.setAttributes(["rr_install_id": RouteRev.installId ?? ""])
/// ```
///
/// Every call is fire-and-forget and safe from any thread. Nothing is sent until `configure`.
public enum RouteRev {
    public struct Options: Sendable {
        /// Seconds between background flushes.
        public var flushInterval: TimeInterval = 15
        /// Events per request; the collector accepts at most 100.
        public var batchSize: Int = 20
        /// Oldest events are dropped beyond this many unsent events.
        public var maxQueuedEvents: Int = 1000
        /// Set false to keep events on the device (for example, until the user consents).
        public var enabled: Bool = true

        public init() {}
    }

    /// Call once at launch, as early as possible.
    public static func configure(key: String, endpoint: URL, options: Options = Options()) {
        let bundle = Bundle.main
        let config = Client.Config(
            key: key,
            endpoint: endpoint,
            bundleId: bundle.bundleIdentifier ?? "app",
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            flushInterval: options.flushInterval,
            batchSize: max(1, min(options.batchSize, 100)),
            maxQueued: max(100, options.maxQueuedEvents)
        )
        let client = Client(config: config, store: DeviceStore(), transport: URLSessionTransport())
        install(client, enabled: options.enabled)
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
    public static func reset() {
        guard let client = state.client else { return }
        Task { await client.reset() }
    }

    /// Sends queued events now. Useful before the app is suspended.
    public static func flush() async {
        await state.client?.flush()
    }

    /// Stable per install (stored in the Keychain). Set it as the RevenueCat
    /// subscriber attribute `rr_install_id` so purchases attribute to this install.
    public static var installId: String? { state.installId }

    /// Pauses or resumes collection at runtime.
    public static var isEnabled: Bool {
        get { state.enabled }
        set { state.enabled = newValue }
    }

    // MARK: - Internals

    static let state = State()

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _client: Client?
        private var _installId: String?
        private var _enabled = true
        private var observers: [NSObjectProtocol] = []

        var client: Client? { locked { _enabled ? _client : nil } }
        var installId: String? { locked { _installId } }
        var enabled: Bool {
            get { locked { _enabled } }
            set { locked { _enabled = newValue } }
        }

        func set(_ client: Client, installId: String, enabled: Bool, observers: [NSObjectProtocol]) {
            locked {
                self.observers.forEach(NotificationCenter.default.removeObserver)
                _client = client
                _installId = installId
                _enabled = enabled
                self.observers = observers
            }
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }
    }

    static func install(_ client: Client, enabled: Bool) {
        var observers: [NSObjectProtocol] = []
        #if canImport(UIKit) && !os(watchOS)
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            // Ask for a little background time so the last screen and goals reach the collector
            let application = UIApplication.shared
            let background = BackgroundTask()
            background.id = application.beginBackgroundTask(withName: "RouteRev flush") {
                background.end(application)
            }
            Task {
                await client.flush()
                await MainActor.run { background.end(application) }
            }
        })
        Task { @MainActor in
            await client.setScreenWidth(Int(UIScreen.main.bounds.width))
        }
        #endif
        state.set(client, installId: client.installId, enabled: enabled, observers: observers)
        Task { await client.startFlushing() }
    }

    #if canImport(UIKit) && !os(watchOS)
    /// Holds a background task ID so both the expiration handler and the flush can end it once.
    final class BackgroundTask: @unchecked Sendable {
        var id = UIBackgroundTaskIdentifier.invalid

        func end(_ application: UIApplication) {
            guard id != .invalid else { return }
            application.endBackgroundTask(id)
            id = .invalid
        }
    }
    #endif

    private static func send(_ kind: Event.Kind, name: String, props: [String: RouteRevValue]) {
        guard !name.isEmpty, let client = state.client else { return }
        let date = Date()
        Task { await client.record(kind, name: name, props: props, at: date) }
    }
}

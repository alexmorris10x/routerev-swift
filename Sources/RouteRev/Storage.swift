import Foundation
#if canImport(Security)
import Security
#endif

/// Where RouteRev keeps identity and the unsent queue. Injectable for tests.
protocol RouteRevStore: Sendable {
    func loadInstallId() -> String?
    func saveInstallId(_ id: String)
    func loadValue(_ key: String) -> String?
    func saveValue(_ key: String, _ value: String?)
    func loadQueue() -> [Event]
    func saveQueue(_ events: [Event])
}

/// Install ID in the Keychain (survives reinstall on the same device), small values in
/// UserDefaults, and the queue as a JSON file in Application Support.
final class DeviceStore: RouteRevStore, @unchecked Sendable {
    private let service = "routerev"
    private let account = "install-id"
    private let defaults: UserDefaults
    private let queueURL: URL?
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let dir = base?.appendingPathComponent("RouteRev", isDirectory: true) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            queueURL = dir.appendingPathComponent("queue.json")
        } else {
            queueURL = nil
        }
    }

    func loadInstallId() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let id = String(data: data, encoding: .utf8) {
            return id
        }
        #endif
        return defaults.string(forKey: "routerev.installId")
    }

    func saveInstallId(_ id: String) {
        defaults.set(id, forKey: "routerev.installId")
        #if canImport(Security)
        let data = Data(id.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
        #endif
    }

    func loadValue(_ key: String) -> String? {
        defaults.string(forKey: "routerev.\(key)")
    }

    func saveValue(_ key: String, _ value: String?) {
        defaults.set(value, forKey: "routerev.\(key)")
    }

    func loadQueue() -> [Event] {
        lock.lock(); defer { lock.unlock() }
        guard let url = queueURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
    }

    func saveQueue(_ events: [Event]) {
        lock.lock(); defer { lock.unlock() }
        guard let url = queueURL else { return }
        if events.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// In-memory store for tests and previews.
final class MemoryStore: RouteRevStore, @unchecked Sendable {
    private let lock = NSLock()
    private var installId: String?
    private var values: [String: String] = [:]
    private var queue: [Event] = []

    // NSLock.withLock needs iOS 16; the package supports iOS 15
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    func loadInstallId() -> String? { locked { installId } }
    func saveInstallId(_ id: String) { locked { installId = id } }
    func loadValue(_ key: String) -> String? { locked { values[key] } }
    func saveValue(_ key: String, _ value: String?) { locked { values[key] = value } }
    func loadQueue() -> [Event] { locked { queue } }
    func saveQueue(_ events: [Event]) { locked { queue = events } }
}

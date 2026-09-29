import XCTest
@testable import RouteRev

/// Records requests and answers with scripted status codes (or a thrown network error).
final class MockTransport: RouteRevTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<Int, Error>]
    private(set) var bodies: [Data] = []

    init(_ responses: [Result<Int, Error>]) { self.responses = responses }

    func send(_ body: Data, to endpoint: URL) async throws -> Int {
        lock.lock(); defer { lock.unlock() }
        bodies.append(body)
        let next = responses.isEmpty ? .success(202) : responses.removeFirst()
        return try next.get()
    }

    var sentEvents: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return bodies.flatMap { body -> [[String: Any]] in
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            return json?["events"] as? [[String: Any]] ?? []
        }
    }
}

/// A clock tests can move forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

final class ClientTests: XCTestCase {
    private func makeClient(
        store: RouteRevStore = MemoryStore(),
        transport: MockTransport = MockTransport([]),
        clock: TestClock = TestClock(),
        batchSize: Int = 50
    ) -> Client {
        let config = Client.Config(
            key: "pk_test_123", endpoint: URL(string: "https://e.example.com/e")!, bundleId: "com.example.app",
            appVersion: "1.4.0", flushInterval: 3600, batchSize: batchSize, maxQueued: 1000
        )
        return Client(config: config, store: store, transport: transport, now: { clock.now })
    }

    func testEventsMatchTheCollectorSchema() async throws {
        let transport = MockTransport([])
        let client = makeClient(transport: transport)
        let clock = TestClock()
        await client.record(.screen, name: "Paywall View", props: ["plan": "pro", "step": 2, "trial": true], at: clock.now)
        await client.identify("user_42", at: clock.now)
        await client.flush()

        let body = try XCTUnwrap(transport.bodies.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["key"] as? String, "pk_test_123")
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)

        let screen = events[0]
        XCTAssertEqual(screen["type"] as? String, "screen")
        XCTAssertEqual(screen["name"] as? String, "Paywall View")
        XCTAssertEqual(screen["platform"] as? String, "ios")
        XCTAssertEqual(screen["url"] as? String, "app://com.example.app/Paywall%20View")
        XCTAssertEqual(screen["appVersion"] as? String, "1.4.0")
        XCTAssertEqual(screen["ts"] as? String, "2026-09-21T14:13:20.000Z")
        XCTAssertGreaterThanOrEqual((screen["id"] as? String)?.count ?? 0, 8)
        XCTAssertGreaterThanOrEqual((screen["visitorId"] as? String)?.count ?? 0, 8)
        let props = try XCTUnwrap(screen["props"] as? [String: Any])
        XCTAssertEqual(props["plan"] as? String, "pro")
        XCTAssertEqual(props["step"] as? Int, 2)
        XCTAssertEqual(props["trial"] as? Bool, true)
        XCTAssertNil(screen["userId"] as? String, "screen was recorded before identify")

        let identify = events[1]
        XCTAssertEqual(identify["type"] as? String, "identify")
        XCTAssertEqual(identify["userId"] as? String, "user_42")
        XCTAssertEqual(identify["visitorId"] as? String, screen["visitorId"] as? String)
    }

    func testInstallIdPersistsAcrossLaunches() async {
        let store = MemoryStore()
        let first = makeClient(store: store).installId
        let second = makeClient(store: store).installId
        XCTAssertEqual(first, second)
    }

    func testSessionRollsOverAfterThirtyMinutesIdle() async {
        let transport = MockTransport([])
        let clock = TestClock()
        let client = makeClient(transport: transport, clock: clock)
        await client.record(.screen, name: "Home", props: [:], at: clock.now)
        clock.advance(29 * 60)
        await client.record(.screen, name: "Settings", props: [:], at: clock.now)
        clock.advance(31 * 60)
        await client.record(.screen, name: "Home", props: [:], at: clock.now)
        await client.flush()

        let sessions = transport.sentEvents.compactMap { $0["sessionId"] as? String }
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions[0], sessions[1])
        XCTAssertNotEqual(sessions[1], sessions[2])
    }

    func testNetworkFailureKeepsEventsAndBacksOff() async {
        struct Offline: Error {}
        let transport = MockTransport([.failure(Offline()), .success(202)])
        let clock = TestClock()
        let client = makeClient(transport: transport, clock: clock)
        await client.record(.goal, name: "sign_up", props: [:], at: clock.now)

        await client.flush()
        var pending = await client.pendingCount
        XCTAssertEqual(pending, 1, "kept after a network error")

        await client.flush()
        XCTAssertEqual(transport.bodies.count, 1, "no retry during backoff")

        clock.advance(11)
        await client.flush()
        pending = await client.pendingCount
        XCTAssertEqual(pending, 0, "delivered after backoff")
    }

    func testServerErrorsKeepEventsButInvalidBatchesAreDropped() async {
        let transport = MockTransport([.success(503), .success(400)])
        let clock = TestClock()
        let client = makeClient(transport: transport, clock: clock)
        await client.record(.goal, name: "a", props: [:], at: clock.now)
        await client.flush()
        var pending = await client.pendingCount
        XCTAssertEqual(pending, 1)

        clock.advance(11)
        await client.flush()
        pending = await client.pendingCount
        XCTAssertEqual(pending, 0, "a 400 means the batch can never succeed")
    }

    func testQueueSurvivesRestartAndSendsInBatches() async {
        let store = MemoryStore()
        let clock = TestClock()
        let offline = makeClient(store: store, transport: MockTransport([.success(500)]), clock: clock, batchSize: 50)
        for i in 0..<120 {
            await offline.record(.goal, name: "g\(i)", props: [:], at: clock.now)
        }

        let transport = MockTransport([])
        let relaunched = makeClient(store: store, transport: transport, clock: clock, batchSize: 50)
        let queued = await relaunched.pendingCount
        XCTAssertEqual(queued, 120, "queue restored from the store")
        await relaunched.flush()
        let pending = await relaunched.pendingCount
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(transport.bodies.count, 3, "120 events in batches of 50")
    }

    func testLimitsAreTrimmedBeforeSending() {
        var props: [String: RouteRevValue] = [:]
        for i in 0..<30 { props["key\(i)"] = .string(String(repeating: "x", count: 600)) }
        let sanitized = Event.sanitize(props)
        XCTAssertEqual(sanitized?.count, 20)
        if case .string(let s)? = sanitized?.values.first { XCTAssertEqual(s.count, 500) } else { XCTFail() }
        XCTAssertNil(Event.sanitize([:]))
    }

    func testResetClearsUserButKeepsInstall() async {
        let client = makeClient()
        let install = client.installId
        await client.identify("user_1", at: Date())
        await client.reset()
        let user = await client.currentUserId
        XCTAssertNil(user)
        XCTAssertEqual(client.installId, install)
    }
}

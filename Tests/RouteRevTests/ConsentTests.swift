import Foundation
import XCTest
@testable import RouteRev

/// Drives the real configure path (global state included) with an in-memory store and a fake
/// transport, to check that disabled collection sends nothing at all.
final class ConsentTests: XCTestCase {
    private let endpoint = URL(string: "https://e.example.com/e")!

    override func setUp() {
        super.setUp()
        RouteRev.state.clear()
    }

    override func tearDown() {
        if let client = RouteRev.state.configuredClient {
            let stop = expectation(description: "stop flushing")
            Task { await client.stopFlushing(); stop.fulfill() }
            wait(for: [stop], timeout: 2)
        }
        RouteRev.state.clear()
        super.tearDown()
    }

    private func configure(enabled: Bool = true, store: RouteRevStore = MemoryStore(), transport: MockTransport) {
        var options = RouteRev.Options()
        options.enabled = enabled
        options.flushInterval = 3600
        RouteRev.configure(
            key: "pk_test_123", endpoint: endpoint, options: options,
            store: store, transport: transport, searchAdsToken: { "asa-token" }
        )
    }

    /// Flushes through the configured client directly, as the background timer and the
    /// backgrounding observer do (they don't go through the public enabled gate).
    private func flushLikeTheTimer() async throws {
        let client = try XCTUnwrap(RouteRev.state.configuredClient)
        await client.flush()
    }

    private func firstOpens(_ transport: MockTransport) -> [[String: Any]] {
        transport.sentEvents.filter { $0["name"] as? String == "first_open" }
    }

    func testDisabledBeforeConfigureSendsNothing() async throws {
        let transport = MockTransport([])
        RouteRev.isEnabled = false
        configure(transport: transport)

        XCTAssertFalse(RouteRev.isEnabled, "configure must not turn collection back on")
        XCTAssertNil(RouteRev.state.firstOpenTask, "first_open waits until enabled")
        RouteRev.screen("Paywall")
        RouteRev.goal("sign_up")
        RouteRev.identify("user_1")
        await RouteRev.flush()
        try await flushLikeTheTimer()

        let pending = await RouteRev.state.configuredClient?.pendingCount
        XCTAssertEqual(pending, 0, "nothing was queued")
        XCTAssertTrue(transport.bodies.isEmpty, "no request at all, so no Search Ads token either")
    }

    func testDisabledByOptionSendsNothingEvenWithQueuedEvents() async throws {
        let store = MemoryStore()
        // A previous launch left an unsent event on the device
        let earlier = Client(
            config: RouteRev.configuration(key: "pk_test_123", endpoint: endpoint),
            store: store, transport: MockTransport([.success(500)])
        )
        await earlier.record(.goal, name: "queued_earlier", props: [:], at: Date())

        let transport = MockTransport([])
        configure(enabled: false, store: store, transport: transport)
        await RouteRev.flush()
        try await flushLikeTheTimer()

        XCTAssertTrue(transport.bodies.isEmpty)
        let pending = await RouteRev.state.configuredClient?.pendingCount
        XCTAssertEqual(pending, 1, "queued events wait on the device")
    }

    func testDisabledThenEnabledSendsFirstOpenOnce() async throws {
        let store = MemoryStore()
        let transport = MockTransport([])
        configure(enabled: false, store: store, transport: transport)
        XCTAssertNil(RouteRev.state.firstOpenTask)

        RouteRev.isEnabled = true
        await RouteRev.state.firstOpenTask?.value
        RouteRev.isEnabled = false
        RouteRev.isEnabled = true
        await RouteRev.state.firstOpenTask?.value
        await RouteRev.flush()

        var sent = firstOpens(transport)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["attributionToken"] as? String, "asa-token")

        // The next launch doesn't send it again
        configure(store: store, transport: transport)
        await RouteRev.state.firstOpenTask?.value
        await RouteRev.flush()
        sent = firstOpens(transport)
        XCTAssertEqual(sent.count, 1, "first_open is once per install")
    }

    func testEnabledSendsFirstOpenAndEventsAsBefore() async throws {
        let transport = MockTransport([])
        configure(transport: transport)
        XCTAssertTrue(RouteRev.isEnabled)
        await RouteRev.state.firstOpenTask?.value
        RouteRev.goal("sign_up")
        try await waitForPending(2)
        await RouteRev.flush()

        let names = transport.sentEvents.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["first_open", "sign_up"])
        XCTAssertEqual(firstOpens(transport).first?["attributionToken"] as? String, "asa-token")
        XCTAssertEqual(transport.sentEvents.last?["attributionToken"] as? String, nil)
    }

    func testDisablingAfterConfigureStopsDelivery() async throws {
        let transport = MockTransport([])
        configure(transport: transport)
        await RouteRev.state.firstOpenTask?.value
        RouteRev.isEnabled = false
        RouteRev.goal("dropped_while_disabled")
        try await flushLikeTheTimer()
        XCTAssertTrue(transport.bodies.isEmpty, "the queued first_open waits while disabled")

        RouteRev.isEnabled = true
        await RouteRev.flush()
        XCTAssertEqual(transport.sentEvents.compactMap { $0["name"] as? String }, ["first_open"])
    }

    func testResetWorksWhileDisabled() async throws {
        configure(transport: MockTransport([]))
        RouteRev.identify("user_1")
        try await waitForUser("user_1")
        RouteRev.isEnabled = false
        RouteRev.reset()
        try await waitForUser(nil)
    }

    // Public calls hop onto the client actor in an unstructured Task; wait for them to land.
    private func waitForPending(_ count: Int) async throws {
        let client = try XCTUnwrap(RouteRev.state.configuredClient)
        for _ in 0..<200 {
            if await client.pendingCount >= count { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("expected \(count) queued events")
    }

    private func waitForUser(_ user: String?) async throws {
        let client = try XCTUnwrap(RouteRev.state.configuredClient)
        for _ in 0..<200 {
            if await client.currentUserId == user { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("expected user \(user ?? "nil")")
    }
}

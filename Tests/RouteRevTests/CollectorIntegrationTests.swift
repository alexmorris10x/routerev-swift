import XCTest
@testable import RouteRev

/// Sends real events to a running RouteRev collector. Skipped unless configured:
/// ROUTEREV_E2E_ENDPOINT=http://localhost:4600/e ROUTEREV_E2E_KEY=pk_dev_… swift test
final class CollectorIntegrationTests: XCTestCase {
    func testCollectorAcceptsWhatTheClientSends() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let endpoint = env["ROUTEREV_E2E_ENDPOINT"].flatMap(URL.init(string:)), let key = env["ROUTEREV_E2E_KEY"] else {
            throw XCTSkip("Set ROUTEREV_E2E_ENDPOINT and ROUTEREV_E2E_KEY to run against a collector")
        }
        let config = Client.Config(
            key: key, endpoint: endpoint, bundleId: "com.routerev.e2e", appVersion: "0.0.1",
            flushInterval: 3600, batchSize: 50, maxQueued: 1000
        )
        let client = Client(config: config, store: MemoryStore(), transport: URLSessionTransport())
        await client.setScreenWidth(393)
        await client.record(.screen, name: "Paywall View", props: ["placement": "onboarding"], at: Date())
        await client.record(.goal, name: "sign_up", props: ["method": "apple"], at: Date())
        await client.identify("e2e_user", at: Date())
        await client.flush()

        let pending = await client.pendingCount
        XCTAssertEqual(pending, 0, "collector accepted the batch")
        print("ROUTEREV_E2E_INSTALL_ID=\(client.installId)")
    }
}

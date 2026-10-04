import Foundation
import XCTest
@testable import RouteRev
#if canImport(SwiftUI)
import SwiftUI
#endif

final class PolishTests: XCTestCase {
    private let endpoint = URL(string: "https://collector.example.invalid/e")!

    func testConfigurationUsesTheAppsEndpointAndKeepsOptions() {
        var options = RouteRev.Options()
        options.flushInterval = 42
        options.batchSize = 33
        options.maxQueuedEvents = 456
        let config = RouteRev.configuration(key: "pk_fixture", endpoint: endpoint, options: options)
        XCTAssertEqual(config.endpoint, endpoint)
        XCTAssertEqual(config.key, "pk_fixture")
        XCTAssertEqual(config.flushInterval, 42)
        XCTAssertEqual(config.batchSize, 33)
        XCTAssertEqual(config.maxQueued, 456)
    }

    func testCustomConfigurationAndExistingLimitsArePreserved() {
        var options = RouteRev.Options()
        options.batchSize = 200
        options.maxQueuedEvents = 2
        let config = RouteRev.configuration(key: "pk_fixture", endpoint: endpoint, options: options)
        XCTAssertEqual(config.endpoint, endpoint)
        XCTAssertEqual(config.batchSize, 100)
        XCTAssertEqual(config.maxQueued, 100)
        options.batchSize = 0
        XCTAssertEqual(RouteRev.configuration(key: "pk_fixture", endpoint: endpoint, options: options).batchSize, 1)
    }

    func testThe021ConfigureCallsStillCompile() {
        // Compile-only: the public configure constructs persistent storage and a real transport.
        // Never invoke this closure in offline tests; ConsentTests drive the injectable configure.
        let call021: () -> Void = {
            RouteRev.configure(key: "pk_fixture", endpoint: URL(string: "https://collector.example.invalid/e")!)
            RouteRev.configure(key: "pk_fixture", endpoint: URL(string: "https://collector.example.invalid/e")!, options: .init())
            RouteRev.isEnabled = false
            _ = RouteRev.installId
        }
        _ = call021
    }

    func testRevenueCatAttributesBeforeAndAfterInstallingIdentity() {
        // Same state accessor as the public helper, isolated from global state/timers.
        let state = RouteRev.State()
        XCTAssertEqual(state.revenueCatAttributes, [:])
        XCTAssertEqual(RouteRev.revenueCatAttributes, [:])
        let client = Client(config: RouteRev.configuration(key: "pk_fixture", endpoint: endpoint), store: MemoryStore(), transport: MockTransport([]))
        state.set(client, installId: client.installId, enabled: false, observers: [])
        XCTAssertEqual(state.revenueCatAttributes, ["rr_install_id": client.installId])
        XCTAssertFalse(state.enabled)
        XCTAssertNil(state.client)
    }

    func testBundledPrivacyManifestDeclaresReasonsAndCollectedData() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let accessed = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(accessed.count, 1)
        XCTAssertEqual(accessed[0]["NSPrivacyAccessedAPIType"] as? String, "NSPrivacyAccessedAPICategoryUserDefaults")
        XCTAssertEqual(accessed[0]["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }), [
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypeAdvertisingData",
        ])
        XCTAssertEqual(collected.count, 5)
        for item in collected {
            XCTAssertEqual(item["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(item["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(item["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAnalytics"])
        }
    }

    #if canImport(SwiftUI)
    @MainActor func testSwiftUIHelperCompilesWithDefaultAndCustomProperties() {
        _ = Text("x").routeRevScreen("Paywall")
        _ = Text("x").routeRevScreen("Paywall", ["placement": "onboarding", "step": 2])
    }
    #endif
}

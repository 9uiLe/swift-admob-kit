@testable import AdsKit
import StoreKit
import XCTest

final class AppStoreAdServingPolicyTests: XCTestCase {
    func testProductionAndSandboxUseProductionAdUnits() {
        XCTAssertEqual(AppStoreAdServingPolicy.adsEnvironment(for: .production), .production)
        XCTAssertEqual(AppStoreAdServingPolicy.adsEnvironment(for: .sandbox), .production)
    }

    func testXcodeUsesTestAdUnits() {
        XCTAssertEqual(AppStoreAdServingPolicy.adsEnvironment(for: .xcode), .test)
    }

    func testReceiptURLMapsDistributedBuildsToProductionAdUnits() {
        XCTAssertEqual(AppStoreAdServingPolicy.adsEnvironment(receiptLastPathComponent: "receipt"), .production)
        XCTAssertEqual(
            AppStoreAdServingPolicy.adsEnvironment(receiptLastPathComponent: "sandboxReceipt"),
            .production,
        )
        XCTAssertNil(AppStoreAdServingPolicy.adsEnvironment(receiptLastPathComponent: nil))
        XCTAssertNil(AppStoreAdServingPolicy.adsEnvironment(receiptLastPathComponent: "missing"))
    }
}

import AdsKit
import XCTest

@MainActor
final class AdMobClientContractTests: XCTestCase {
    func testUnknownSlotIsRejectedWithoutTouchingTheSDK() async {
        let client = AdMobClient(
            configuration: AdMobConfiguration(
                adUnits: [:],
                environmentPolicy: .test,
            ),
        )

        let outcome = await client.load(AdSlot(rawValue: "missing"))

        XCTAssertEqual(outcome, .unavailable(.unknownSlot))
    }

    func testConfiguredSlotIsUnavailableBeforePreparation() async {
        let slot = AdSlot(rawValue: "gameplay-banner")
        let client = AdMobClient(
            configuration: AdMobConfiguration(
                adUnits: [
                    slot: AdUnitConfiguration(
                        format: .banner,
                        productionAdUnitID: "ca-app-pub-example/banner",
                    ),
                ],
                environmentPolicy: .test,
            ),
        )

        let loadOutcome = await client.load(slot)
        let presentationOutcome = await client.present(slot)

        XCTAssertEqual(loadOutcome, .unavailable(.notReady))
        XCTAssertEqual(presentationOutcome, .unavailable(.notReady))
    }
}

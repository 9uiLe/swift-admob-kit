import Domain
import StoreKit

enum AdsEnvironment: Sendable {
    case test
    case production
}

struct AdUnitIDResolver: Sendable {
    let environment: AdsEnvironment

    static func resolve() async -> AdUnitIDResolver {
        AdUnitIDResolver(environment: await resolveEnvironment())
    }

    private static func resolveEnvironment() async -> AdsEnvironment {
        #if DEBUG || targetEnvironment(simulator)
        return .test
        #else
        // TestFlight と App Store 提出は同一の Release アーカイブを共有するため、
        // ビルド設定ではなく実行時に判定する。判定不能時は test に倒す
        // (fail-safe: 収益を捨てても無効トラフィックを出さない)。
        guard case let .verified(transaction) = try? await AppTransaction.shared,
              transaction.environment == .production else {
            return .test
        }
        return .production
        #endif
    }

    func adUnitID(for placement: AdPlacementID) -> String {
        switch environment {
        case .test:
            testAdUnitID(for: placement)
        case .production:
            productionAdUnitID(for: placement)
        }
    }

    // Google 公式のデモ用 AdUnitID (https://developers.google.com/admob/ios/test-ads)
    private func testAdUnitID(for placement: AdPlacementID) -> String {
        switch placement {
        case .gameplayBanner:
            "ca-app-pub-3940256099942544/2435281174"
        case .postPuzzleInterstitial:
            "ca-app-pub-3940256099942544/4411468910"
        case .rewardedHint, .rewardedPractice:
            "ca-app-pub-3940256099942544/1712485313"
        }
    }

    // 本番 AdUnitID はこのメソッド以外に書かない (scripts/check-architecture.sh が検査)。
    private func productionAdUnitID(for placement: AdPlacementID) -> String {
        switch placement {
        case .gameplayBanner:
            "ca-app-pub-2739163670639776/5942529722"
        case .postPuzzleInterstitial:
            "ca-app-pub-2739163670639776/3316366380"
        case .rewardedHint:
            "ca-app-pub-2739163670639776/2003284711"
        case .rewardedPractice:
            "ca-app-pub-2739163670639776/9227168618"
        }
    }
}

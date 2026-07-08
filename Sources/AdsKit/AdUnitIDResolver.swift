import Domain
import StoreKit

enum AdsEnvironment {
    case test
    case production
}

struct AdUnitIDResolver {
    let environment: AdsEnvironment

    static func resolve() async -> AdUnitIDResolver {
        await AdUnitIDResolver(environment: resolveEnvironment())
    }

    private static func resolveEnvironment() async -> AdsEnvironment {
        #if DEBUG || targetEnvironment(simulator)
            // AdMob が自動でテストデバイス扱いにするのはシミュレータのみ。実機 Debug は
            // SDK からは本番と区別できないため、この分岐でテスト ID を強制する (削除禁止)。
            return .test
        #else
            // TestFlight と App Store 提出は同一の Release アーカイブを共有するため、
            // ビルド設定ではなく実行時に判定する。TestFlight (.sandbox) は実ユーザーに近い
            // 検証環境として本番 ID を使う (2026-07-09 変更)。Xcode 直接インストール
            // (.xcode)・判定不能時は test に倒す (fail-safe: 無効トラフィックを出さない)。
            // 注意: TestFlight では本物の広告が出るため、自分の広告をタップしない。
            // タップ検証が必要な端末は AdMob コンソールでテストデバイス登録する。
            do {
                guard case let .verified(transaction) = try await AppTransaction.shared,
                      transaction.environment == .production || transaction.environment == .sandbox
                else {
                    return .test
                }
            } catch {
                let message = "failed to resolve App Store transaction environment; using test ad units: \(error)"
                AdsKitLog.logger.error("\(message, privacy: .public)")
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

    /// Google 公式のデモ用 AdUnitID (https://developers.google.com/admob/ios/test-ads)
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

    /// 本番 AdUnitID はこのメソッド以外に書かない (scripts/check-architecture.sh が検査)。
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

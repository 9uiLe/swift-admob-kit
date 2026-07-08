import Domain
import StoreKit

enum AdsEnvironment {
    case test
    case production
}

struct AdUnitIDResolver {
    let environment: AdsEnvironment

    static func resolve() async -> AdUnitIDResolver {
        let environment = await resolveEnvironment()
        return AdUnitIDResolver(environment: environment)
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
            for attempt in 1 ... 3 {
                do {
                    let result = try await AppTransaction.shared
                    if let storeEnvironment = appStoreEnvironment(from: result) {
                        let environment = AppStoreAdServingPolicy.adsEnvironment(for: storeEnvironment)
                        logResolvedEnvironment(environment, signal: "appTransaction(\(storeEnvironment))")
                        return environment
                    }
                } catch {
                    AdsKitLog.logger.error(
                        "AppTransaction attempt \(attempt) failed; will retry or fall back: \(String(describing: error), privacy: .public)",
                    )
                    if attempt < 3 {
                        try? await Task.sleep(for: .milliseconds(300 * attempt))
                    }
                }
            }

            let receiptComponent = Bundle.main.appStoreReceiptURL?.lastPathComponent
            if let environment = AppStoreAdServingPolicy.adsEnvironment(receiptLastPathComponent: receiptComponent) {
                logResolvedEnvironment(environment, signal: "receiptURL(\(receiptComponent ?? "nil"))")
                return environment
            }

            AdsKitLog.logger.error("failed to resolve App Store distribution; using test ad units (fail-safe)")
            return .test
        #endif
    }

    private static func appStoreEnvironment(from result: VerificationResult<AppTransaction>) -> AppStore.Environment? {
        let transaction: AppTransaction
        switch result {
        case let .verified(value):
            transaction = value
        case let .unverified(value, error):
            // ユニット ID 選択は信頼境界ではない。検証失敗でも環境フィールドは利用する。
            AdsKitLog.logger.error(
                "unverified AppTransaction; using environment anyway: \(String(describing: error), privacy: .public)",
            )
            transaction = value
        }
        return transaction.environment
    }

    private static func logResolvedEnvironment(_ environment: AdsEnvironment, signal: String) {
        AdsKitLog.logger.info(
            "resolved ad environment=\(String(describing: environment), privacy: .public) via \(signal, privacy: .public)",
        )
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

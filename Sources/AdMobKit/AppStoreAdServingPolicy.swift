import StoreKit

/// App Store 配布形態と AdMob ユニット ID 選択の対応 (設計書 §3.5)。
enum AppStoreAdServingPolicy {
    static func adsEnvironment(for storeEnvironment: AppStore.Environment) -> AdsEnvironment {
        switch storeEnvironment {
        case .production, .sandbox:
            .production
        case .xcode:
            .test
        default:
            .test
        }
    }

    /// `Bundle.main.appStoreReceiptURL` の lastPathComponent から配布形態を推定する。
    /// AppTransaction が一時的に失敗したときのフォールバック。ファイル実体の有無は問わない。
    static func adsEnvironment(receiptLastPathComponent: String?) -> AdsEnvironment? {
        switch receiptLastPathComponent {
        case "receipt", "sandboxReceipt":
            .production
        default:
            nil
        }
    }
}

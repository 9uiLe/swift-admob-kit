import AppTrackingTransparency

// concurrency-exception: Google Mobile Ads SDK は Swift 6 strict concurrency に完全対応していないため、
// @preconcurrency import を AdsKit 内部に限定して使用する (設計書 §2 T2)。
@preconcurrency import GoogleMobileAds
import UIKit
@preconcurrency import UserMessagingPlatform

/// UMP 同意 → ATT → canRequestAds の状態機械 (設計書 §3.5)。
/// AdMob コンソールの「IDFA メッセージ」は使わず、ATT はコードから明示的に呼ぶ手動パターン。
@MainActor
final class ConsentCoordinator {
    private(set) var canRequestAds = false

    func prepareConsent() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            if let viewController = Self.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: viewController)
            }
        } catch {
            // 同意フローの失敗でゲームを止めない。canRequestAds に従って安全に劣化する。
        }
        _ = await ATTrackingManager.requestTrackingAuthorization()
        canRequestAds = ConsentInformation.shared.canRequestAds
    }

    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() async {
        guard let viewController = Self.topViewController() else {
            return
        }
        try? await ConsentForm.presentPrivacyOptionsForm(from: viewController)
    }

    static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

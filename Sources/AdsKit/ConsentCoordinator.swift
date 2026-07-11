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

    func prepareConsent(trackingAuthorizationPolicy: AdTrackingAuthorizationPolicy) async {
        #if DEBUG || targetEnvironment(simulator)
            // UMP/ATT のスキップは確実に開発環境と分かるビルドに限定する。
            // Release 実機では AdUnitIDResolver が fail-safe で .test に倒れても通常の同意フローを通す。
            canRequestAds = true
        #else
            do {
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
                if let viewController = Self.topViewController() {
                    try await ConsentForm.loadAndPresentIfRequired(from: viewController)
                }
            } catch {
                // 同意フローの失敗でゲームを止めない。canRequestAds に従って安全に劣化する。
                AdsKitLog.logger.error(
                    "failed to prepare consent flow: \(String(describing: error), privacy: .public)",
                )
            }
            if trackingAuthorizationPolicy == .requestAfterConsent {
                _ = await ATTrackingManager.requestTrackingAuthorization()
            }
            canRequestAds = ConsentInformation.shared.canRequestAds
        #endif
    }

    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() async {
        guard let viewController = Self.topViewController() else {
            return
        }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: viewController)
        } catch {
            // プライバシー設定フォームはユーザー起点の任意導線。失敗してもゲーム進行は止めない。
            AdsKitLog.logger.error(
                "failed to present privacy options form: \(String(describing: error), privacy: .public)",
            )
        }
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

// concurrency-exception: SDK の Sendable 未準拠に対する @preconcurrency import (AdsKit 内部限定)。
@preconcurrency import GoogleMobileAds
import Application
import Domain
import UIKit

// AdServingRepository ポートの Google Mobile Ads 実装。
// SDK の UI 要件 (present / UMP / ATT はメインスレッド必須) に合わせ @MainActor に分離する。
// nonisolated な async ポート要件は MainActor 分離メソッドで witness できる (await にホップが吸収される)。
@MainActor
public final class AdMobServingRepository: AdServingRepository {
    private let consent = ConsentCoordinator()
    private var resolver: AdUnitIDResolver?
    private var interstitial: InterstitialAd?
    private var rewardedAds: [AdPlacementID: RewardedAd] = [:]
    private var isStarted = false

    public init() {}

    public var privacyOptionsRequired: Bool {
        consent.privacyOptionsRequired
    }

    public func presentPrivacyOptions() async {
        await consent.presentPrivacyOptions()
    }

    public func prepareAds(configuration: AdMonetizationConfiguration) async throws {
        guard !isStarted else {
            return
        }
        resolver = await AdUnitIDResolver.resolve()
        await consent.prepareConsent()
        guard consent.canRequestAds else {
            return
        }
        _ = await MobileAds.shared.start()
        isStarted = true
    }

    // 同意未取得・未初期化の状態で呼ばれても安全に劣化する (ポート契約: 設計書 §3.5)。
    public func loadAd(placement: AdPlacementDefinition) async throws {
        guard isStarted, consent.canRequestAds, let resolver else {
            return
        }
        switch placement.format {
        case .interstitial:
            interstitial = try? await InterstitialAd.load(
                with: resolver.adUnitID(for: placement.id),
                request: Request()
            )
        case .rewarded, .rewardedInterstitial:
            rewardedAds[placement.id] = try? await RewardedAd.load(
                with: resolver.adUnitID(for: placement.id),
                request: Request()
            )
        case .banner:
            break
        }
    }

    public func showAd(placement: AdPlacementDefinition) async throws -> AdShowOutcome {
        guard isStarted, consent.canRequestAds,
              let viewController = ConsentCoordinator.topViewController() else {
            return .unavailable
        }
        switch placement.format {
        case .interstitial:
            return await showInterstitial(from: viewController, placement: placement)
        case .rewarded, .rewardedInterstitial:
            return await showRewarded(from: viewController, placement: placement)
        case .banner:
            return .unavailable
        }
    }

    private func showInterstitial(
        from viewController: UIViewController,
        placement: AdPlacementDefinition
    ) async -> AdShowOutcome {
        guard let ad = interstitial else {
            reload(placement)
            return .unavailable
        }
        interstitial = nil
        let events = FullScreenAdEvents()
        ad.fullScreenContentDelegate = events
        let outcome = await events.run {
            ad.present(from: viewController)
        }
        reload(placement)
        return outcome
    }

    private func showRewarded(
        from viewController: UIViewController,
        placement: AdPlacementDefinition
    ) async -> AdShowOutcome {
        guard let ad = rewardedAds[placement.id] else {
            reload(placement)
            return .unavailable
        }
        rewardedAds[placement.id] = nil
        let events = FullScreenAdEvents()
        ad.fullScreenContentDelegate = events
        let outcome = await events.run {
            ad.present(from: viewController) {
                events.recordReward(Application.AdReward(
                    placementID: placement.id,
                    amount: ad.adReward.amount.intValue
                ))
            }
        }
        reload(placement)
        // リワードは「報酬条件を満たしたか」だけで判定する。
        // 報酬前の離脱はインプレッションが記録されていても .dismissed (付与しない)。
        if let reward = events.earnedReward {
            return .rewarded(reward)
        }
        return outcome == .unavailable ? .unavailable : .dismissed
    }

    private func reload(_ placement: AdPlacementDefinition) {
        // 広告インスタンスは 1 回のみ表示可能・約 1 時間で失効するため、表示後に 1 枚だけ再ロードする。
        Task {
            try? await self.loadAd(placement: placement)
        }
    }
}

// フルスクリーン広告のデリゲートイベントを async/await に橋渡しする。
// 意味論 (設計書 §3.5): インプレッション記録後の dismiss = .completed / 表示前の失敗 = .unavailable。
@MainActor
private final class FullScreenAdEvents: NSObject, FullScreenContentDelegate {
    private(set) var earnedReward: Application.AdReward?
    private var impressionRecorded = false
    private var continuation: CheckedContinuation<AdShowOutcome, Never>?

    func run(present: () -> Void) async -> AdShowOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    func recordReward(_ reward: Application.AdReward) {
        earnedReward = reward
    }

    nonisolated func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            self.impressionRecorded = true
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            self.finish(with: self.impressionRecorded ? .completed : .dismissed)
        }
    }

    nonisolated func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        Task { @MainActor in
            self.finish(with: .unavailable)
        }
    }

    private func finish(with outcome: AdShowOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

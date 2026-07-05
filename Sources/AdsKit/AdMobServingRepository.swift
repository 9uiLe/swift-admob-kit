import Application
import Domain

// concurrency-exception: SDK の Sendable 未準拠に対する @preconcurrency import (AdsKit 内部限定)。
@preconcurrency import GoogleMobileAds
import Tasking
import UIKit

/// AdsKit 内部で起動する非同期 Action の ID (Presentation の PuzzleActions と同じ規約)。
private enum AdsKitActions {
    static func reloadAd(_ placement: AdPlacementID) -> ActionID {
        ActionID("adsKit.reloadAd.\(placement.rawValue)")
    }
}

/// AdServingRepository ポートの Google Mobile Ads 実装。
/// SDK の UI 要件 (present / UMP / ATT はメインスレッド必須) に合わせ @MainActor に分離する。
/// nonisolated な async ポート要件は MainActor 分離メソッドで witness できる (await にホップが吸収される)。
@MainActor
public final class AdMobServingRepository: AdServingRepository {
    private let consent = ConsentCoordinator()
    private var resolver: AdUnitIDResolver?
    private var interstitial: InterstitialAd?
    private var rewardedAds: [AdPlacementID: RewardedAd] = [:]
    private var isStarted = false
    private var prepareAttemptCompleted = false
    private var readinessWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private let taskStore = ViewTaskStore()

    public init() {}

    public var isReady: Bool {
        isStarted
    }

    public var privacyOptionsRequired: Bool {
        consent.privacyOptionsRequired
    }

    public func waitUntilReady() async {
        guard !isStarted, !prepareAttemptCompleted else {
            return
        }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isStarted || prepareAttemptCompleted {
                    continuation.resume()
                    return
                }
                if Task.isCancelled {
                    continuation.resume()
                    return
                }
                readinessWaiters[waiterID] = continuation
            }
        } onCancel: {
            // nonisolated 同期コールバックからの MainActor ホップは ViewTaskStore (@MainActor) に到達できないため生 Task を維持する。
            Task { @MainActor in
                self.resumeReadinessWaiter(id: waiterID)
            }
        }
    }

    public func bannerAdUnitID(for placement: AdPlacementID) -> String? {
        resolver?.adUnitID(for: placement)
    }

    public func presentPrivacyOptions() async {
        await consent.presentPrivacyOptions()
    }

    public func prepareAds(configuration _: AdMonetizationConfiguration) async throws {
        guard !isStarted else {
            return
        }
        resolver = await AdUnitIDResolver.resolve()
        await consent.prepareConsent()
        guard consent.canRequestAds else {
            prepareAttemptCompleted = true
            resumeReadinessWaiters()
            return
        }
        // メディエーションアダプタを使用していないため、start() 時のアダプタ初期化を無効化する。
        MobileAds.shared.disableMediationInitialization()
        _ = await MobileAds.shared.start()
        isStarted = true
        prepareAttemptCompleted = true
        resumeReadinessWaiters()
    }

    /// 同意未取得・未初期化の状態で呼ばれても安全に劣化する (ポート契約: 設計書 §3.5)。
    public func loadAd(placement: AdPlacementDefinition) async throws {
        guard isStarted, consent.canRequestAds, let resolver else {
            return
        }
        switch placement.format {
        case .interstitial:
            interstitial = try? await InterstitialAd.load(
                with: resolver.adUnitID(for: placement.id),
                request: Request(),
            )
        case .rewarded, .rewardedInterstitial:
            rewardedAds[placement.id] = try? await RewardedAd.load(
                with: resolver.adUnitID(for: placement.id),
                request: Request(),
            )
        case .banner:
            break
        }
    }

    public func showAd(placement: AdPlacementDefinition) async throws -> AdShowOutcome {
        guard isStarted, consent.canRequestAds,
              let viewController = ConsentCoordinator.topViewController()
        else {
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
        placement: AdPlacementDefinition,
    ) async -> AdShowOutcome {
        guard let loadedInterstitial = interstitial else {
            reload(placement)
            return .unavailable
        }
        interstitial = nil
        let events = FullScreenAdEvents()
        loadedInterstitial.fullScreenContentDelegate = events
        let outcome = await events.run {
            loadedInterstitial.present(from: viewController)
        }
        reload(placement)
        return outcome
    }

    private func showRewarded(
        from viewController: UIViewController,
        placement: AdPlacementDefinition,
    ) async -> AdShowOutcome {
        guard let loadedRewarded = rewardedAds[placement.id] else {
            reload(placement)
            return .unavailable
        }
        rewardedAds[placement.id] = nil
        let events = FullScreenAdEvents()
        loadedRewarded.fullScreenContentDelegate = events
        let outcome = await events.run {
            loadedRewarded.present(from: viewController) {
                events.recordReward(Application.AdReward(
                    placementID: placement.id,
                    amount: loadedRewarded.adReward.amount.intValue,
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
        // ViewTaskStore の ignoreNew で同一プレースメントの再ロード多重起動を構造的に防ぐ。
        taskStore.start(id: AdsKitActions.reloadAd(placement.id), lifetime: .appBound, policy: .ignoreNew) { _ in
            try? await self.loadAd(placement: placement)
        }
    }

    private func resumeReadinessWaiter(id: UUID) {
        readinessWaiters.removeValue(forKey: id)?.resume()
    }

    private func resumeReadinessWaiters() {
        let waiters = Array(readinessWaiters.values)
        readinessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

/// フルスクリーン広告のデリゲートイベントを async/await に橋渡しする。
/// 意味論 (設計書 §3.5): インプレッション記録後の dismiss = .completed / 表示前の失敗 = .unavailable。
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

    nonisolated func adDidRecordImpression(_: FullScreenPresentingAd) {
        // nonisolated 同期コールバックからの MainActor ホップは ViewTaskStore (@MainActor) に到達できないため生 Task を維持する。
        Task { @MainActor in
            self.impressionRecorded = true
        }
    }

    nonisolated func adDidDismissFullScreenContent(_: FullScreenPresentingAd) {
        Task { @MainActor in
            self.finish(with: self.impressionRecorded ? .completed : .dismissed)
        }
    }

    /// GADFullScreenContentDelegate のメソッド名 (SDK 契約)
    nonisolated func ad(
        _: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError _: Error,
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

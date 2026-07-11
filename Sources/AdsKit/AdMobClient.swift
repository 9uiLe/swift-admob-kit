import Foundation

// concurrency-exception: Google Mobile Ads delegate callbacks are nonisolated and must hop to MainActor.
@preconcurrency import GoogleMobileAds
import UIKit

/// A MainActor-isolated facade over Google Mobile Ads and UMP.
///
/// The host supplies slot names and production unit IDs. AdsKit owns consent, environment resolution,
/// Google demo ID selection, ad caching, presentation, and post-presentation reloads.
@MainActor
public final class AdMobClient {
    private let configuration: AdMobConfiguration
    private let consent = ConsentCoordinator()
    private var resolver: AdUnitIDResolver?
    private var interstitialAds: [AdSlot: InterstitialAd] = [:]
    private var rewardedAds: [AdSlot: RewardedAd] = [:]
    private var rewardedInterstitialAds: [AdSlot: RewardedInterstitialAd] = [:]
    private var loadingSlots: Set<AdSlot> = []
    private var isStarted = false
    private var isPreparing = false
    private var prepareAttemptCompleted = false
    private var readinessWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    public init(configuration: AdMobConfiguration) {
        self.configuration = configuration
    }

    public var isReady: Bool {
        isStarted
    }

    public var privacyOptionsRequired: Bool {
        consent.privacyOptionsRequired
    }

    /// Resolves the serving environment, completes consent/ATT, and starts Google Mobile Ads.
    /// Repeated calls are idempotent. Failures leave the client unavailable instead of blocking the host app.
    public func prepare() async {
        guard !isStarted, !prepareAttemptCompleted else {
            return
        }
        guard !isPreparing else {
            await waitUntilReady()
            return
        }
        isPreparing = true
        resolver = await AdUnitIDResolver.resolve(policy: configuration.environmentPolicy)
        await consent.prepareConsent(trackingAuthorizationPolicy: configuration.trackingAuthorizationPolicy)
        guard consent.canRequestAds else {
            finishPreparation(started: false)
            return
        }
        MobileAds.shared.disableMediationInitialization()
        _ = await MobileAds.shared.start()
        finishPreparation(started: true)
    }

    public func waitUntilReady() async {
        guard !isStarted, !prepareAttemptCompleted else {
            return
        }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isStarted || prepareAttemptCompleted || Task.isCancelled {
                    continuation.resume()
                } else {
                    readinessWaiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.resumeReadinessWaiter(id: waiterID)
            }
        }
    }

    @discardableResult
    public func load(_ slot: AdSlot) async -> AdLoadOutcome {
        let request: AdLoadRequest
        do {
            request = try makeLoadRequest(for: slot)
        } catch let error as AdClientError {
            return .unavailable(error.reason)
        } catch {
            return .unavailable(.invalidConfiguration)
        }
        defer { loadingSlots.remove(slot) }

        switch request.configuration.format {
        case .banner:
            return .unavailable(.invalidConfiguration)
        case .interstitial:
            do {
                interstitialAds[slot] = try await InterstitialAd.load(with: request.adUnitID, request: Request())
                return .loaded
            } catch {
                interstitialAds[slot] = nil
                logLoadFailure(error, slot: slot)
                return .unavailable(.loadFailed)
            }
        case .rewarded:
            do {
                rewardedAds[slot] = try await RewardedAd.load(with: request.adUnitID, request: Request())
                return .loaded
            } catch {
                rewardedAds[slot] = nil
                logLoadFailure(error, slot: slot)
                return .unavailable(.loadFailed)
            }
        case .rewardedInterstitial:
            do {
                rewardedInterstitialAds[slot] = try await RewardedInterstitialAd.load(
                    with: request.adUnitID,
                    request: Request(),
                )
                return .loaded
            } catch {
                rewardedInterstitialAds[slot] = nil
                logLoadFailure(error, slot: slot)
                return .unavailable(.loadFailed)
            }
        }
    }

    public func present(_ slot: AdSlot) async -> AdPresentationOutcome {
        guard let adUnit = configuration.adUnits[slot] else {
            return .unavailable(.unknownSlot)
        }
        guard isStarted else {
            return .unavailable(.notReady)
        }
        guard consent.canRequestAds else {
            return .unavailable(.consentRequired)
        }
        guard let viewController = ConsentCoordinator.topViewController() else {
            return .unavailable(.presentationFailed)
        }

        let outcome: AdPresentationOutcome
        switch adUnit.format {
        case .interstitial:
            outcome = await presentInterstitial(slot, from: viewController)
        case .rewarded:
            outcome = await presentRewarded(slot, from: viewController)
        case .rewardedInterstitial:
            outcome = await presentRewardedInterstitial(slot, from: viewController)
        case .banner:
            return .unavailable(.invalidConfiguration)
        }
        scheduleReload(slot)
        return outcome
    }

    public func presentPrivacyOptions() async {
        await consent.presentPrivacyOptions()
    }

    func bannerAdUnitID(for slot: AdSlot) -> String? {
        guard isStarted,
              consent.canRequestAds,
              let resolver,
              let adUnit = configuration.adUnits[slot],
              adUnit.format == .banner
        else {
            return nil
        }
        return resolver.adUnitID(for: adUnit)
    }

    private func presentInterstitial(
        _ slot: AdSlot,
        from viewController: UIViewController,
    ) async -> AdPresentationOutcome {
        guard let loadedAd = interstitialAds.removeValue(forKey: slot) else {
            return .unavailable(.notReady)
        }
        let events = FullScreenAdEvents()
        loadedAd.fullScreenContentDelegate = events
        let outcome = await events.run {
            loadedAd.present(from: viewController)
        }
        loadedAd.fullScreenContentDelegate = nil
        return outcome
    }

    private func presentRewarded(
        _ slot: AdSlot,
        from viewController: UIViewController,
    ) async -> AdPresentationOutcome {
        guard let loadedAd = rewardedAds.removeValue(forKey: slot) else {
            return .unavailable(.notReady)
        }
        let events = FullScreenAdEvents()
        loadedAd.fullScreenContentDelegate = events
        let rewardAmount = loadedAd.adReward.amount.intValue
        let outcome = await events.run {
            loadedAd.present(from: viewController) {
                events.recordReward(amount: rewardAmount)
            }
        }
        loadedAd.fullScreenContentDelegate = nil
        if let amount = events.rewardAmount {
            return .rewarded(amount: amount)
        }
        return outcome == .unavailable(.presentationFailed) ? outcome : .dismissed
    }

    private func presentRewardedInterstitial(
        _ slot: AdSlot,
        from viewController: UIViewController,
    ) async -> AdPresentationOutcome {
        guard let loadedAd = rewardedInterstitialAds.removeValue(forKey: slot) else {
            return .unavailable(.notReady)
        }
        let events = FullScreenAdEvents()
        loadedAd.fullScreenContentDelegate = events
        let rewardAmount = loadedAd.adReward.amount.intValue
        let outcome = await events.run {
            loadedAd.present(from: viewController) {
                events.recordReward(amount: rewardAmount)
            }
        }
        loadedAd.fullScreenContentDelegate = nil
        if let amount = events.rewardAmount {
            return .rewarded(amount: amount)
        }
        return outcome == .unavailable(.presentationFailed) ? outcome : .dismissed
    }

    private func scheduleReload(_ slot: AdSlot) {
        Task { @MainActor [weak self] in
            await self?.load(slot)
        }
    }

    private func makeLoadRequest(for slot: AdSlot) throws -> AdLoadRequest {
        guard let configuration = configuration.adUnits[slot] else {
            throw AdClientError(reason: .unknownSlot)
        }
        guard isStarted, let resolver else {
            throw AdClientError(reason: .notReady)
        }
        guard consent.canRequestAds else {
            throw AdClientError(reason: .consentRequired)
        }
        guard let adUnitID = resolver.adUnitID(for: configuration) else {
            throw AdClientError(reason: .invalidConfiguration)
        }
        guard loadingSlots.insert(slot).inserted else {
            throw AdClientError(reason: .loadInProgress)
        }
        return AdLoadRequest(configuration: configuration, adUnitID: adUnitID)
    }

    private func finishPreparation(started: Bool) {
        isStarted = started
        isPreparing = false
        prepareAttemptCompleted = true
        let waiters = Array(readinessWaiters.values)
        readinessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resumeReadinessWaiter(id: UUID) {
        readinessWaiters.removeValue(forKey: id)?.resume()
    }

    private func logLoadFailure(_ error: Error, slot: AdSlot) {
        AdsKitLog.logger.error(
            "failed to load ad for slot=\(slot.rawValue, privacy: .public): \(String(describing: error), privacy: .public)",
        )
    }
}

private struct AdLoadRequest {
    let configuration: AdUnitConfiguration
    let adUnitID: String
}

private struct AdClientError: Error {
    let reason: AdUnavailableReason
}

@MainActor
private final class FullScreenAdEvents: NSObject, FullScreenContentDelegate {
    private(set) var rewardAmount: Int?
    private var impressionRecorded = false
    private var continuation: CheckedContinuation<AdPresentationOutcome, Never>?

    func run(present: () -> Void) async -> AdPresentationOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    func recordReward(amount: Int) {
        rewardAmount = amount
    }

    nonisolated func adDidRecordImpression(_: FullScreenPresentingAd) {
        Task { @MainActor in
            self.impressionRecorded = true
        }
    }

    nonisolated func adDidDismissFullScreenContent(_: FullScreenPresentingAd) {
        Task { @MainActor in
            self.finish(with: self.impressionRecorded ? .completed : .dismissed)
        }
    }

    nonisolated func ad(
        _: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error,
    ) {
        Task { @MainActor in
            AdsKitLog.logger.error(
                "failed to present full-screen ad: \(String(describing: error), privacy: .public)",
            )
            self.finish(with: .unavailable(.presentationFailed))
        }
    }

    private func finish(with outcome: AdPresentationOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

import Foundation

/// A host-defined key for one ad location. AdsKit does not attach domain meaning to it.
public struct AdSlot: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum AdMobFormat: String, Codable, Equatable, Sendable {
    case banner
    case interstitial
    case rewarded
    case rewardedInterstitial
}

/// The production unit ID and format for a host-defined slot.
/// Google demo IDs are selected internally whenever AdsKit resolves the test environment.
public struct AdUnitConfiguration: Codable, Equatable, Sendable {
    public let format: AdMobFormat
    public let productionAdUnitID: String

    public init(format: AdMobFormat, productionAdUnitID: String) {
        self.format = format
        self.productionAdUnitID = productionAdUnitID
    }
}

public enum AdEnvironmentPolicy: Codable, Equatable, Sendable {
    /// DEBUG, Simulator, and direct Xcode installs use test ads. Distributed builds use production ads.
    /// If distribution cannot be established, AdsKit fails safe to test ads.
    case automatic
    /// Always use Google's demo ad unit IDs. Useful for previews, QA, and automated tests.
    case test
}

public enum AdTrackingAuthorizationPolicy: Codable, Equatable, Sendable {
    /// Request App Tracking Transparency authorization after UMP has updated consent information.
    case requestAfterConsent
    /// Do not request ATT. The host remains responsible for any tracking authorization flow it needs.
    case disabled
}

public struct AdMobConfiguration: Codable, Equatable, Sendable {
    public let adUnits: [AdSlot: AdUnitConfiguration]
    public let environmentPolicy: AdEnvironmentPolicy
    public let trackingAuthorizationPolicy: AdTrackingAuthorizationPolicy

    public init(
        adUnits: [AdSlot: AdUnitConfiguration],
        environmentPolicy: AdEnvironmentPolicy = .automatic,
        trackingAuthorizationPolicy: AdTrackingAuthorizationPolicy = .requestAfterConsent,
    ) {
        self.adUnits = adUnits
        self.environmentPolicy = environmentPolicy
        self.trackingAuthorizationPolicy = trackingAuthorizationPolicy
    }
}

public enum AdUnavailableReason: String, Codable, Equatable, Sendable {
    case unknownSlot
    case notReady
    case consentRequired
    case invalidConfiguration
    case loadInProgress
    case loadFailed
    case presentationFailed
}

public enum AdLoadOutcome: Equatable, Sendable {
    case loaded
    case unavailable(AdUnavailableReason)
}

public enum AdPresentationOutcome: Equatable, Sendable {
    case completed
    case rewarded(amount: Int)
    case dismissed
    case unavailable(AdUnavailableReason)
}

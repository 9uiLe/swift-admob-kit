# Swift AdMob Kit

[![CI](https://github.com/9uiLe/swift-admob-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/9uiLe/swift-admob-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`AdMobKit` is a small Swift package that isolates Google Mobile Ads and User Messaging Platform behind a Swift 6, MainActor-safe interface.

The package owns SDK startup, UMP consent, optional ATT authorization, test-versus-production unit selection, banner rendering, full-screen ad caching, presentation outcomes, and reloads. Your app owns placement names, production ad unit IDs, monetization policy, and UI styling.

## Requirements

- iOS 26 or later
- Swift 6.3 or later
- Xcode 26 or later

## Installation

Add the package dependency in Xcode or in `Package.swift`:

```swift
.package(
    url: "https://github.com/9uiLe/swift-admob-kit.git",
    from: "0.1.0",
)
```

Then add the `AdMobKit` product to your iOS target.

## Host app setup

The host application, not this package, must configure its AdMob application ID and privacy metadata in `Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>$(ADMOB_APP_ID)</string>
<key>NSUserTrackingUsageDescription</key>
<string>Explain why your app requests tracking authorization.</string>
```

Also add the current `SKAdNetworkItems` entries required by Google and any mediation partners. Keep this list current using Google's [iOS quick start](https://developers.google.com/admob/ios/quick-start) and [privacy strategies](https://developers.google.com/admob/ios/privacy/strategies) documentation.

Create required privacy messages in the AdMob console before shipping. See Google's [UMP setup guide](https://developers.google.com/admob/ios/privacy).

## Configure the client

Slots are host-defined string keys. Production unit IDs are injected by the host; Google demo IDs remain internal to AdMobKit.

```swift
import AdMobKit

let banner = AdSlot(rawValue: "home-banner")
let interstitial = AdSlot(rawValue: "level-complete")
let rewarded = AdSlot(rawValue: "rewarded-hint")

@MainActor
let ads = AdMobClient(
    configuration: AdMobConfiguration(
        adUnits: [
            banner: AdUnitConfiguration(
                format: .banner,
                productionAdUnitID: "ca-app-pub-…/…",
            ),
            interstitial: AdUnitConfiguration(
                format: .interstitial,
                productionAdUnitID: "ca-app-pub-…/…",
            ),
            rewarded: AdUnitConfiguration(
                format: .rewarded,
                productionAdUnitID: "ca-app-pub-…/…",
            ),
        ],
        environmentPolicy: .automatic,
        trackingAuthorizationPolicy: .requestAfterConsent,
    ),
)
```

Call `prepare()` after the app becomes active so ATT can present if enabled:

```swift
await ads.prepare()
```

Load and present full-screen ads:

```swift
if await ads.load(interstitial) == .loaded {
    let outcome = await ads.present(interstitial)
    // completed, dismissed, or unavailable(reason)
}

if await ads.load(rewarded) == .loaded {
    let outcome = await ads.present(rewarded)
    // rewarded(amount), dismissed, or unavailable(reason)
}
```

Reserve banner height in the host layout to prevent layout shifts:

```swift
AdMobBanner(slot: banner, client: ads, maximumHeight: 60)
    .frame(height: 60)
```

If `privacyOptionsRequired` becomes true after preparation, expose a visible control that calls:

```swift
await ads.presentPrivacyOptions()
```

## Environment safety

With `.automatic`:

- DEBUG builds and iOS Simulator use Google's demo ad unit IDs.
- direct Xcode installs use demo IDs.
- App Store and TestFlight distributions use the host's production IDs.
- unresolved distribution state fails safe to demo IDs.

Use `.test` to force demo IDs. AdMobKit intentionally has no “force production” policy. Always follow Google's [test ads guidance](https://developers.google.com/admob/ios/test-ads); do not click live ads while testing.

## Architecture

`AdMobClient` is the public module interface. It is isolated to `MainActor`, keeping non-Sendable Google SDK objects inside the implementation. Apps adapt their own domain placement types and advertising policy to `AdSlot`; AdMobKit does not define frequency caps, rewards policy, or app-specific presentation contracts.

## License

Swift AdMob Kit is available under the MIT License. See [LICENSE](LICENSE).

This is an independent, unofficial project. AdMob and Google Mobile Ads are trademarks of Google LLC.

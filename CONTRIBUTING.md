# Contributing

Issues and focused pull requests are welcome.

## Development

Requirements: Xcode 26+, Swift 6.3+, and an iOS 26 Simulator.

```bash
xcodebuild test \
  -scheme SwiftAdsKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

Keep these invariants intact:

- Production ad unit IDs belong to host apps and must not be committed to AdsKit.
- Google SDK objects remain MainActor-isolated inside the package implementation.
- Unknown distribution environments resolve to Google demo IDs.
- Public types must not depend on an app's domain or presentation modules.

Do not use live ads for automated or manual interaction testing.

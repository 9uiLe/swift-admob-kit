// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SwiftAdsKit",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "AdsKit",
            targets: ["AdsKit"],
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "13.6.0",
        ),
    ],
    targets: [
        .target(
            name: "AdsKit",
            dependencies: [
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
        ),
        .testTarget(
            name: "AdsKitTests",
            dependencies: ["AdsKit"],
        ),
    ],
    swiftLanguageModes: [.v6],
)

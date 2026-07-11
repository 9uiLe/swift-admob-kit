// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SwiftAdMobKit",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "AdMobKit",
            targets: ["AdMobKit"],
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
            name: "AdMobKit",
            dependencies: [
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
        ),
        .testTarget(
            name: "AdMobKitTests",
            dependencies: ["AdMobKit"],
        ),
    ],
    swiftLanguageModes: [.v6],
)

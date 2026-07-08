// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AdsKit",
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
        // name: はローカル依存の識別子がディレクトリ名 (num-path) から導出され
        // Package.swift の宣言名 AdPuzzleApp と一致しないため必須 (deprecated だが意図的)。
        .package(name: "AdPuzzleApp", path: "../AdPuzzleApp"),
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "13.6.0",
        ),
        .package(url: "https://github.com/9uiLe/swift-tasking.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "AdsKit",
            dependencies: [
                .product(name: "Domain", package: "AdPuzzleApp"),
                .product(name: "Application", package: "AdPuzzleApp"),
                .product(name: "Presentation", package: "AdPuzzleApp"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "Tasking", package: "swift-tasking"),
            ],
        ),
        .testTarget(
            name: "AdsKitTests",
            dependencies: ["AdsKit"],
        ),
    ],
    swiftLanguageModes: [.v6],
)

import Foundation
import os

enum AdsKitLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.9uiLe.swift-ads-kit",
        category: "ads",
    )
}

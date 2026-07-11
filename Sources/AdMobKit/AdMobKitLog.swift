import Foundation
import os

enum AdMobKitLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.9uiLe.swift-admob-kit",
        category: "ads",
    )
}

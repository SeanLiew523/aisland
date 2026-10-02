import Foundation

/// Local bundle identity; the underlying executable and hook protocol stay OpenIsland.
enum AppBrand {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "AIsland"
    }

    static var settingsWindowTitle: String { "\(displayName) Settings" }

    static var usesLiveBloubStyle: Bool {
        Bundle.main.object(forInfoDictionaryKey: "OpenIslandLiveBloubStyle") as? Bool ?? true
    }
}

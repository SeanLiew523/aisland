import Foundation

/// The reviewed introduction has English and Simplified Chinese media. This
/// resolver never writes the app's language preference, including zh-Hant.
public enum OnboardingLanguage: String, Sendable, CaseIterable {
    case english = "en"
    case chinese = "zh"

    public static func resolve(manualLanguage: String?, preferredLanguages: [String]) -> Self {
        let manual = manualLanguage?.lowercased()
        if manual == "en" { return .english }
        if manual == "zh-hans" || manual == "zh-hant" { return .chinese }
        let system = preferredLanguages.first?.lowercased() ?? "en"
        return system.hasPrefix("zh") ? .chinese : .english
    }
}

public enum OnboardingPresentationPolicy {
    /// Migration readiness prevents a legacy upgrade racing the first-run gate.
    public static func shouldAutomaticallyPresent(
        migrationReady: Bool, firstLaunchCompleted: Bool, alreadyPresented: Bool
    ) -> Bool {
        migrationReady && !firstLaunchCompleted && !alreadyPresented
    }
}

/// Presentation and completion are distinct: even quitting halfway through
/// consumes the automatic welcome. Replay is an explicit settings action.
public final class OnboardingPresentationStore: @unchecked Sendable {
    public static let presentedKey = "onboardingPresentedV1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var alreadyPresented: Bool { defaults.bool(forKey: Self.presentedKey) }

    /// Call after migration and immediately before displaying the native window.
    /// Synchronize this low-frequency claim so an early process exit is durable.
    @discardableResult
    public func claimAutomaticPresentation(migrationReady: Bool, firstLaunchCompleted: Bool) -> Bool {
        guard OnboardingPresentationPolicy.shouldAutomaticallyPresent(
            migrationReady: migrationReady, firstLaunchCompleted: firstLaunchCompleted,
            alreadyPresented: alreadyPresented
        ) else { return false }
        defaults.set(true, forKey: Self.presentedKey)
        defaults.synchronize()
        return true
    }
}

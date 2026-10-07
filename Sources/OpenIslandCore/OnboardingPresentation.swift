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
    private static let installationKey = "onboardingInstallationV1"
    private let defaults: UserDefaults

    /// Directory identity survives launches/moves but changes on a fresh copy.
    /// A different build is an upgrade; the same build at a new identity is a reinstall.
    public struct Installation: Codable, Equatable, Sendable {
        public let identity: String
        public let build: String
        public init(identity: String, build: String) { self.identity = identity; self.build = build }
        public static func current(bundle: Bundle = .main) -> Installation? {
            guard bundle.bundleURL.pathExtension == "app",
                  let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: bundle.bundleURL.path),
                  let device = attributes[.systemNumber] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            return Installation(identity: "\(device):\(inode)", build: build)
        }
    }

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var alreadyPresented: Bool { defaults.bool(forKey: Self.presentedKey) }

    /// Call after migration and immediately before displaying the native window.
    /// Synchronize this low-frequency claim so an early process exit is durable.
    @discardableResult
    public func claimAutomaticPresentation(migrationReady: Bool, firstLaunchCompleted: Bool,
                                           installation: Installation? = nil) -> Bool {
        if let installation {
            guard migrationReady else { return false }
            let previous = defaults.data(forKey: Self.installationKey).flatMap { try? JSONDecoder().decode(Installation.self, from: $0) }
            let reinstalled = previous.map { $0.build == installation.build && $0.identity != installation.identity } ?? false
            if let data = try? JSONEncoder().encode(installation) { defaults.set(data, forKey: Self.installationKey) }
            // Legacy hook setup is not evidence that this introduction was played.
            guard !alreadyPresented || reinstalled else { defaults.synchronize(); return false }
            defaults.set(true, forKey: Self.presentedKey)
            defaults.synchronize()
            return true
        }
        guard OnboardingPresentationPolicy.shouldAutomaticallyPresent(
            migrationReady: migrationReady, firstLaunchCompleted: firstLaunchCompleted,
            alreadyPresented: alreadyPresented
        ) else { return false }
        defaults.set(true, forKey: Self.presentedKey)
        defaults.synchronize()
        return true
    }
}

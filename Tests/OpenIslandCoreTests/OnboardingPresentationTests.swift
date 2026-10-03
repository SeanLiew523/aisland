import Foundation
import Testing
@testable import OpenIslandCore

struct OnboardingPresentationTests {
    @Test func freshLaunchClaimsOnceEvenWithoutCompletion() throws {
        try withDefaults { defaults in
            let first = OnboardingPresentationStore(defaults: defaults)
            #expect(first.claimAutomaticPresentation(migrationReady: true, firstLaunchCompleted: false))
            // Reopening after a partial presentation, close or application exit
            // does not require firstLaunchCompleted to have been written.
            let second = OnboardingPresentationStore(defaults: defaults)
            #expect(!second.claimAutomaticPresentation(migrationReady: true, firstLaunchCompleted: false))
            #expect(!AgentIntentStore(defaults: defaults).firstLaunchCompleted)
        }
    }

    @Test func migrationMustFinishBeforeClaim() throws {
        try withDefaults { defaults in
            let store = OnboardingPresentationStore(defaults: defaults)
            #expect(!store.claimAutomaticPresentation(migrationReady: false, firstLaunchCompleted: false))
            #expect(!store.alreadyPresented)
            #expect(store.claimAutomaticPresentation(migrationReady: true, firstLaunchCompleted: false))
        }
    }

    @Test func legacyAndCompletedUsersDoNotAutomaticallyReplay() throws {
        try withDefaults { defaults in
            let legacy = AgentIntentStore(defaults: defaults)
            legacy.migrateFromLegacyStateIfNeeded { $0 == .claudeCode }
            let presentation = OnboardingPresentationStore(defaults: defaults)
            #expect(!presentation.claimAutomaticPresentation(migrationReady: true, firstLaunchCompleted: legacy.firstLaunchCompleted))
            #expect(legacy.intent(for: .claudeCode) == .installed)
            #expect(!presentation.alreadyPresented)
            // Settings replay has no presentation-store mutation and preserves
            // both completion and the manual language from a previous version.
            defaults.set("zh-Hant", forKey: "appLanguage")
            #expect(OnboardingLanguage.resolve(manualLanguage: defaults.string(forKey: "appLanguage"), preferredLanguages: ["en-US"]) == .chinese)
            #expect(defaults.string(forKey: "appLanguage") == "zh-Hant")
            #expect(legacy.firstLaunchCompleted)
        }
    }

    @Test func completeAndSkipPersistExistingCompletion() throws {
        try withDefaults { defaults in
            let presentation = OnboardingPresentationStore(defaults: defaults)
            #expect(presentation.claimAutomaticPresentation(migrationReady: true, firstLaunchCompleted: false))
            let intent = AgentIntentStore(defaults: defaults)
            intent.firstLaunchCompleted = true
            #expect(!OnboardingPresentationStore(defaults: defaults).claimAutomaticPresentation(migrationReady: true, firstLaunchCompleted: intent.firstLaunchCompleted))
        }
    }

    @Test(arguments: [
        ("system", "zh-Hans-CN", OnboardingLanguage.chinese),
        ("system", "en-GB", .english), ("system", "fr-FR", .english),
        ("en", "zh-CN", .english), ("zh-Hans", "en-US", .chinese),
        ("zh-Hant", "en-US", .chinese), ("system", "zh-TW", .chinese)
    ]) func languagePreservesManualChoice(manual: String, system: String, expected: OnboardingLanguage) {
        #expect(OnboardingLanguage.resolve(manualLanguage: manual, preferredLanguages: [system]) == expected)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "onboarding-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

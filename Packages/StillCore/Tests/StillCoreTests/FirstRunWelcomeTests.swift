import Foundation
import Testing
@testable import StillCore

/// Preferences held in memory, so tests never write to the user's defaults.
private final class Preferences: MigrationPreferences, @unchecked Sendable {
    var values: [String: Any]
    init(_ values: [String: Any] = [:]) { self.values = values }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// #158: the welcome shows once on a first launch, and never to someone who already used Still or CacheDrop.
@Suite struct FirstRunWelcomeTests {
    @Test func aFreshInstallShowsTheWelcomeUntilItIsFinishedOrSkipped() {
        let preferences = Preferences()
        let welcome = FirstRunWelcome(preferences: preferences)
        #expect(welcome.shouldShow(migration: .nothingToCopy, stateExisted: false))
        #expect(welcome.shouldShow(migration: .alreadyDone, stateExisted: false))
        welcome.markSeen()
        #expect(!welcome.shouldShow(migration: .alreadyDone, stateExisted: false))
        #expect(!FirstRunWelcome(preferences: preferences).shouldShow(migration: .alreadyDone, stateExisted: false), "Kept across launches")
    }

    @Test func quittingWithTheWelcomeOpenShowsItAgainEvenOnceStateExists() {
        let preferences = Preferences()
        #expect(FirstRunWelcome(preferences: preferences).shouldShow(migration: .nothingToCopy, stateExisted: false))
        #expect(preferences.values[FirstRunWelcome.stateKey] as? String == "pending", "Recorded the first time")
        // Quit without Skip or Start scan; by the next launch the launch scan has written CacheDrop's state.
        #expect(FirstRunWelcome(preferences: preferences).shouldShow(migration: .alreadyDone, stateExisted: true))
        FirstRunWelcome(preferences: preferences).markSeen()
        #expect(!FirstRunWelcome(preferences: preferences).shouldShow(migration: .alreadyDone, stateExisted: true))
    }

    @Test(arguments: [LegacyStillMigration.Outcome.copied, .cacheDropHasState])
    func aMigratedOrExistingUserNeverSeesIt(_ migration: LegacyStillMigration.Outcome) {
        let preferences = Preferences()
        #expect(!FirstRunWelcome(preferences: preferences).shouldShow(migration: migration, stateExisted: false))
        #expect(preferences.values[FirstRunWelcome.stateKey] as? String == "seen", "Recorded, so a later launch doesn't show it either")
    }

    @Test func cacheDropStateFromAnEarlierVersionCountsAsSeen() {
        let preferences = Preferences()
        #expect(!FirstRunWelcome(preferences: preferences).shouldShow(migration: .alreadyDone, stateExisted: true))
        #expect(!FirstRunWelcome(preferences: preferences).shouldShow(migration: .alreadyDone, stateExisted: false))
    }

    @Test func aMigrationToTryAgainLaterStillShowsItToANewUser() {
        #expect(FirstRunWelcome(preferences: Preferences()).shouldShow(migration: .stillRunning, stateExisted: false))
        #expect(FirstRunWelcome(preferences: Preferences()).shouldShow(migration: nil, stateExisted: false))
    }
}

import Foundation
import Testing
@testable import CacheDropCore

@Suite struct AutomaticUpdateChecksTests {
    @Test func onByDefaultAndOffWhenTurnedOff() {
        #expect(AutomaticUpdateChecks.isOn(saved: nil, disposableTest: false))
        #expect(AutomaticUpdateChecks.isOn(saved: true, disposableTest: false))
        #expect(!AutomaticUpdateChecks.isOn(saved: false, disposableTest: false))
        #expect(!AutomaticUpdateChecks.isOn(saved: nil, disposableTest: true), "Test runs never check on their own")
    }
    @Test func onceAWeek() { #expect(AutomaticUpdateChecks.interval == 604_800) }
    @Test func scheduledChecksOnlyWhileOnAndNeverDuringAPendingInstallation() {
        #expect(AutomaticUpdateChecks.allows(.scheduled, automaticChecksOn: true, installationPending: false))
        #expect(!AutomaticUpdateChecks.allows(.scheduled, automaticChecksOn: false, installationPending: false))
        #expect(AutomaticUpdateChecks.allows(.requested, automaticChecksOn: false, installationPending: false))
        #expect(!AutomaticUpdateChecks.allows(.requested, automaticChecksOn: true, installationPending: true))
        #expect(!AutomaticUpdateChecks.allows(.scheduled, automaticChecksOn: true, installationPending: true))
    }
    @Test func theKeyIsPinned() { #expect(PreferenceKeys.checksForUpdatesAutomatically == "CacheDrop.checksForUpdatesAutomatically") }
}

import Foundation
import Testing
import CacheDropCore

@MainActor private final class DisposableAppearanceStore: AppearancePreferenceStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillAppearance-" + UUID().uuidString)
    var file: URL { root.appendingPathComponent("appearance") }
    var failReads = false, failWrites = false, failRemoves = false
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false) }
    func read() throws -> String? {
        if failReads { throw CocoaError(.fileReadNoPermission) }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8)
    }
    func write(_ value: String) throws {
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        try Data(value.utf8).write(to: file, options: .atomic)
    }
    func remove() throws {
        if failRemoves { throw CocoaError(.fileWriteNoPermission) }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test @MainActor func appearanceMissingIsAutomaticAndChosenOverrideSurvivesRecreation() throws {
    let store = try DisposableAppearanceStore(); defer { store.clean() }
    let appearance = AppearancePreferenceController(store: store)
    #expect(appearance.choice == .automatic)
    #expect(appearance.notice == nil)
    appearance.choose(.dark)
    #expect(appearance.choice == .dark)
    #expect(try store.read() == "Dark")
    let reopened = AppearancePreferenceController(store: store)
    #expect(reopened.choice == .dark)
    reopened.choose(.light)
    #expect(AppearancePreferenceController(store: store).choice == .light)
}

@Test @MainActor func appearanceInvalidAndUnreadableFallbackNeverRepairSavedData() throws {
    let store = try DisposableAppearanceStore(); defer { store.clean() }
    try store.write("Unexpected")
    let invalid = AppearancePreferenceController(store: store)
    #expect(invalid.choice == .automatic)
    #expect(invalid.notice == .invalidSavedValue)
    #expect(try store.read() == "Unexpected")
    store.failReads = true
    let unavailable = AppearancePreferenceController(store: store)
    #expect(unavailable.choice == .automatic)
    #expect(unavailable.notice == .unreadable)
    store.failReads = false
    #expect(try store.read() == "Unexpected")
    unavailable.choose(.light)
    #expect(unavailable.notice == nil)
    #expect(try store.read() == "Light")
}

@Test @MainActor func appearanceFailedSaveRetainsSessionChoiceAndRetryOnlySavesThatChoice() throws {
    let store = try DisposableAppearanceStore(); defer { store.clean() }
    try store.write("Dark")
    let unrelated = store.root.appendingPathComponent("unrelated-record")
    try Data([3, 1, 4]).write(to: unrelated)
    let appearance = AppearancePreferenceController(store: store)
    store.failWrites = true
    appearance.choose(.light)
    #expect(appearance.choice == .light)
    #expect(appearance.notice == .saveFailed)
    #expect(AppearancePreferenceController(store: store).choice == .dark)
    appearance.retrySaving()
    #expect(appearance.notice == .saveFailed)
    store.failWrites = false
    appearance.retrySaving()
    #expect(appearance.choice == .light)
    #expect(appearance.notice == nil)
    #expect(AppearancePreferenceController(store: store).choice == .light)
    #expect(try Data(contentsOf: unrelated) == Data([3, 1, 4]))
}

@Test @MainActor func appearanceResetChangesOnlyAfterItsOwnPreferenceClearSucceeds() throws {
    let store = try DisposableAppearanceStore(); defer { store.clean() }
    let appearance = AppearancePreferenceController(store: store)
    appearance.choose(.dark)
    store.failRemoves = true
    do { try appearance.reset(); Issue.record("Failed appearance removal must be reported") }
    catch { }
    #expect(appearance.choice == .dark)
    #expect(try store.read() == "Dark")
    store.failRemoves = false
    try appearance.reset()
    #expect(appearance.choice == .automatic)
    #expect(appearance.notice == nil)
    #expect(try store.read() == nil)
    #expect(AppearancePreferenceController(store: store).choice == .automatic)
}

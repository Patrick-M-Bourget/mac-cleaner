import Foundation
import Testing
@testable import StillCore

/// A temp home folder with its own `.Trash`; tests never read or open the real Trash.
private func trashHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillTrash-\(UUID())")
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    return URL(fileURLWithPath: try #require(realPath(home.path)))
}
private func write(_ url: URL, bytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 3, count: bytes).write(to: url)
}

@Test func anEmptyOrMissingTrashIsEmpty() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(TrashSpace.measure(home: home) == .empty)
    try write(home.appendingPathComponent(".Trash/.DS_Store"), bytes: 6_148)
    #expect(TrashSpace.measure(home: home) == .empty)
    try FileManager.default.removeItem(at: home.appendingPathComponent(".Trash"))
    #expect(TrashSpace.measure(home: home) == .empty)
}

@Test func theTrashIsSizedByTheSpaceItsItemsUse() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home.appendingPathComponent(".Trash/Setup.dmg"), bytes: 200_000)
    try write(home.appendingPathComponent(".Trash/Old project/notes.txt"), bytes: 50_000)
    guard case .holds(let bytes) = TrashSpace.measure(home: home) else { Issue.record("expected a size"); return }
    #expect(bytes >= 250_000)
    #expect(bytes < 400_000)
}

@Test func anUnreadableTrashIsUnknownNeverZero() throws {
    let home = try trashHome()
    defer { chmod(home.appendingPathComponent(".Trash").path, 0o755); try? FileManager.default.removeItem(at: home) }
    try write(home.appendingPathComponent(".Trash/Setup.dmg"), bytes: 10_000)
    #expect(chmod(home.appendingPathComponent(".Trash").path, 0) == 0)
    #expect(TrashSpace.measure(home: home) == .unknown)
}

@Test func aPartlyUnreadableTrashIsUnknown() throws {
    let home = try trashHome()
    let locked = home.appendingPathComponent(".Trash/Locked")
    defer { chmod(locked.path, 0o755); try? FileManager.default.removeItem(at: home) }
    try write(locked.appendingPathComponent("secret.bin"), bytes: 10_000)
    #expect(chmod(locked.path, 0) == 0)
    #expect(TrashSpace.measure(home: home) == .unknown)
}

@Test func aTrashThatIsASymlinkIsUnknown() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let elsewhere = home.appendingPathComponent("elsewhere")
    try write(elsewhere.appendingPathComponent("big.bin"), bytes: 10_000)
    try FileManager.default.removeItem(at: home.appendingPathComponent(".Trash"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".Trash"), withDestinationURL: elsewhere)
    #expect(TrashSpace.measure(home: home) == .unknown)
}

@Test func measuringTheTrashChangesNothingInIt() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent(".Trash/Setup.dmg")
    try write(file, bytes: 10_000)
    let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    _ = TrashSpace.measure(home: home)
    #expect(try Data(contentsOf: file) == Data(repeating: 3, count: 10_000))
    #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == before)
}

@Test func overviewSaysWhatTheTrashHoldsOnlyWhenItIsNotEmpty() {
    #expect(TrashContents.empty.overviewText == nil)
    #expect(TrashContents.holds(2_400_000_000).overviewText == "Trash holds 2.4 GB")
    #expect(TrashContents.unknown.overviewText == "Trash size unknown")
}

@Test func resultsSayHowMuchEmptyingTheTrashWouldFree() {
    #expect(TrashContents.holds(3_000_000_000).emptyHint(movedBytes: 0) == nil)
    #expect(TrashContents.holds(3_000_000_000).emptyHint(movedBytes: 1_000_000_000) == "Empty the Trash in Finder to free 3 GB")
    // Unreadable: what this run moved is a lower bound, never 0.
    #expect(TrashContents.unknown.emptyHint(movedBytes: 1_000_000_000) == "Empty the Trash in Finder to free at least 1 GB")
    #expect(TrashContents.empty.emptyHint(movedBytes: 1_000_000_000) == "Empty the Trash in Finder to free at least 1 GB")
}

private final class RecordingOpener: TrashOpening, @unchecked Sendable {
    var opened: [URL] = []
    func open(_ folder: URL) -> Bool { opened.append(folder); return true }
}

@Test func openTrashOpensTheTrashFolderInFinder() throws {
    let home = try trashHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let opener = RecordingOpener()
    #expect(TrashSpace.open(home: home, with: opener))
    #expect(opener.opened == [home.appendingPathComponent(".Trash", isDirectory: true)])
}

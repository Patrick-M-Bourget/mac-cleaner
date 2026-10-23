import Foundation
import Testing
import CloudProbe

@Test func uncertainPinningBlocksOtherwiseSyncedDownload() {
    let report = CloudProbe.assess(.init(isCloud: true, status: "current", uploaded: true, uploading: false, downloading: false, conflicts: false, syncError: false))
    #expect(report.eviction == "unsupported")
    #expect(report.reasons.contains("pinning-not-validated"))
}

@Test(arguments: [
    ("notDownloaded", true, false, false, false, false, "already-placeholder"),
    ("downloaded", true, false, false, false, false, "local-copy-stale"),
    ("current", false, true, false, false, false, "upload-incomplete-or-unknown"),
    ("current", true, false, false, true, false, "conflicts-or-unknown"),
    ("current", true, false, false, false, true, "sync-error-or-unknown"),
    ("current", true, false, true, false, false, "transfer-active-or-unknown")
]) func unsafeStatesGiveSpecificGuidance(_ row: (String, Bool, Bool, Bool, Bool, Bool, String)) {
    let report = CloudProbe.assess(.init(isCloud: true, status: row.0, uploaded: row.1, uploading: row.2, downloading: row.3, conflicts: row.4, syncError: row.5))
    #expect(report.eviction == "unsupported")
    #expect(report.reasons.contains(row.6))
}

@Test func missingMetadataNeverAuthorizesEviction() {
    let report = CloudProbe.assess(.init(isCloud: nil, status: nil, uploaded: nil, uploading: nil, downloading: nil, conflicts: nil, syncError: nil))
    #expect(report.reasons.contains("cloud-membership-unconfirmed"))
    #expect(report.reasons.contains("upload-incomplete-or-unknown"))
}

@Test func disposableLocalFileIsObservedWithoutModification() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillCloudProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let item = root.appendingPathComponent("disposable.txt")
    let contents = Data("Disposable probe content".utf8)
    try contents.write(to: item)
    let before = try item.resourceValues(forKeys: [.contentModificationDateKey, .fileAllocatedSizeKey])
    let report = try CloudProbe.inspectDisposable(item)
    #expect(report.eviction == "unsupported")
    #expect(report.reasons.contains("cloud-membership-unconfirmed"))
    let after = try item.resourceValues(forKeys: [.contentModificationDateKey, .fileAllocatedSizeKey])
    #expect(before.contentModificationDate == after.contentModificationDate)
    #expect(before.fileAllocatedSize == after.fileAllocatedSize)
    #expect(try Data(contentsOf: item) == contents)
}

@Test func pathsOutsideDisposableScopeAreRejected() {
    #expect(throws: (any Error).self) {
        try CloudProbe.inspectDisposable(URL(fileURLWithPath: "/Users/example/important.txt"))
    }
}

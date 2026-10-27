import Testing
@testable import CacheDropCore

/// #223, #232: Overview's Scanned locations line says what was observed in plain words, with one middle dot at most.
/// The caller formats the size, with the same formatter as the rest of Overview.
@Test func summaryNamesTheObservedFolderAndKnownCacheFolders() {
    #expect(ScannedLocationsSummary.text(folders: 1, observedSize: "12 MB", complete: true, knownCacheFolders: 12, checking: false)
        == "12 MB observed in 1 folder · 12 known cache folders")
    #expect(ScannedLocationsSummary.text(folders: 2, observedSize: "3 GB", complete: false, knownCacheFolders: 1, checking: false)
        == "at least 3 GB observed in 2 folders · 1 known cache folder")
}

@Test func summaryWithoutAnObservedFolderLeavesUnknownCoverageToTheRowBelow() {
    #expect(ScannedLocationsSummary.text(folders: nil, observedSize: nil, complete: false, knownCacheFolders: 12, checking: false)
        == "12 known cache folders")
    #expect(ScannedLocationsSummary.text(folders: 1, observedSize: nil, complete: true, knownCacheFolders: nil, checking: false) == "1 folder")
}

@Test func summaryWhileCheckingAndWhenNothingIsChosen() {
    #expect(ScannedLocationsSummary.text(folders: nil, observedSize: nil, complete: false, knownCacheFolders: nil, checking: true)
        == "Checking known cache folders…")
    #expect(ScannedLocationsSummary.text(folders: nil, observedSize: nil, complete: false, knownCacheFolders: nil, checking: false)
        == "No folders chosen yet")
}

import Testing
@testable import CacheDropCore

/// #223: Overview's Scanned locations line says what was scanned in plain words, with one middle dot at most.
@Test func summaryNamesTheObservedFolderAndKnownCacheFolders() {
    #expect(ScannedLocationsSummary.text(folders: 1, observedBytes: 12_000_000, complete: true, knownCacheFolders: 12, checking: false)
        == "12 MB in 1 folder · 12 known cache folders")
    #expect(ScannedLocationsSummary.text(folders: 2, observedBytes: 3_000_000_000, complete: false, knownCacheFolders: 1, checking: false)
        == "at least 3 GB in 2 folders · 1 known cache folder")
}

@Test func summaryWithoutAnObservedFolderLeavesUnknownCoverageToTheRowBelow() {
    #expect(ScannedLocationsSummary.text(folders: nil, observedBytes: nil, complete: false, knownCacheFolders: 12, checking: false)
        == "12 known cache folders")
    #expect(ScannedLocationsSummary.text(folders: 1, observedBytes: nil, complete: true, knownCacheFolders: nil, checking: false) == "1 folder")
}

@Test func summaryWhileCheckingAndWhenNothingIsChosen() {
    #expect(ScannedLocationsSummary.text(folders: nil, observedBytes: nil, complete: false, knownCacheFolders: nil, checking: true)
        == "Checking known cache folders…")
    #expect(ScannedLocationsSummary.text(folders: nil, observedBytes: nil, complete: false, knownCacheFolders: nil, checking: false)
        == "No folders chosen yet")
}

import Testing
import CacheDropCore

// Decision 46: the bottom bar shows background work as one line, the work that started first plus "+1 more".
// #230: each kind of work is labelled by what it is.

private let catalog = "Checking npm cache… 4 of 31"

@Test func nothingRunningShowsNoLine() {
    var work = BackgroundWork()
    work.update(running: [])
    #expect(work.line(catalogProgress: catalog) == nil)
}

@Test func eachTaskIsLabelledByWhatItIs() {
    #expect(BackgroundJob.catalogScan.text(catalogProgress: catalog) == "Checking npm cache… 4 of 31")
    #expect(BackgroundJob.folderRecheck.text(catalogProgress: catalog) == "Rechecking selected locations…")
    #expect(BackgroundJob.folderScan(folder: "Projects").text(catalogProgress: catalog) == "Scanning Projects…")
}

@Test func eachTaskHasItsOwnIdentifier() {
    #expect(BackgroundJob.catalogScan.identifier == "catalogScanProgress")
    #expect(BackgroundJob.folderRecheck.identifier == "folderRecheckProgress")
    #expect(BackgroundJob.folderScan(folder: "Projects").identifier == "folderScanProgress")
}

@Test func oneJobShowsItsOwnText() {
    var work = BackgroundWork()
    work.update(running: [.catalogScan])
    let line = work.line(catalogProgress: catalog)
    #expect(line?.id == "catalogScanProgress")
    #expect(line?.text == "Checking npm cache… 4 of 31")
}

@Test func aNewFolderScanIsNotARecheck() {
    var work = BackgroundWork()
    work.update(running: [.folderScan(folder: "Projects")])
    #expect(work.line(catalogProgress: catalog)?.id == "folderScanProgress")
    #expect(work.line(catalogProgress: catalog)?.text == "Scanning Projects…")
}

@Test func twoJobsShowTheEarliestPlusOneMore() {
    var work = BackgroundWork()
    work.update(running: [.folderRecheck])
    work.update(running: [.catalogScan, .folderRecheck])
    #expect(work.line(catalogProgress: catalog)?.id == "folderRecheckProgress")
    #expect(work.line(catalogProgress: catalog)?.text == "Rechecking selected locations… · +1 more")
}

@Test func whenTheEarliestFinishesTheNextTakesItsPlace() {
    var work = BackgroundWork()
    work.update(running: [.catalogScan])
    work.update(running: [.catalogScan, .folderRecheck])
    work.update(running: [.folderRecheck])
    #expect(work.line(catalogProgress: catalog)?.text == "Rechecking selected locations…")
    // Work that starts again later goes to the back.
    work.update(running: [.folderRecheck, .catalogScan])
    #expect(work.line(catalogProgress: catalog)?.text == "Rechecking selected locations… · +1 more")
}

@Test func workStartedTogetherShowsTheFolderScanFirst() {
    // Scan again starts both at once; the folder scan leads, so its own progress shows.
    var work = BackgroundWork()
    work.update(running: [.catalogScan, .folderRecheck])
    #expect(work.running == [.folderRecheck, .catalogScan])
}

@Test func threeJobsCountEveryOtherOne() {
    var work = BackgroundWork()
    work.update(running: [.catalogScan])
    work.update(running: [.catalogScan, .folderRecheck, .folderScan(folder: "Projects")])
    #expect(work.line(catalogProgress: catalog)?.text == "Checking npm cache… 4 of 31 · +2 more")
}

// #235: a folder scan's line carries its phase and count, each with its own identifier, on one line.

@Test func aFolderScanShowsItsPhaseAndCount() {
    var work = BackgroundWork()
    work.update(running: [.folderScan(folder: "Projects")])
    let line = work.line(catalogProgress: catalog, folderPhase: .enumerating, inspectedEntries: 1240)
    #expect(line?.text == "Scanning Projects · Reading file metadata… · 1240 entries inspected")
    #expect(line?.parts.map(\.id) == ["folderScanProgress", "scanPhase", "scanProgressSummary"])
}

@Test func aRecheckNamesEachPhase() {
    var work = BackgroundWork()
    work.update(running: [.folderRecheck, .catalogScan])
    #expect(work.line(catalogProgress: catalog, folderPhase: .checkingDirectories, inspectedEntries: 3)?.text
        == "Rechecking selected locations · Checking directory stability… · 3 entries inspected · +1 more")
    #expect(work.line(catalogProgress: catalog, folderPhase: .rechecking, inspectedEntries: 1)?.text
        == "Rechecking selected locations · Rechecking changed coverage… · 1 entry inspected · +1 more")
}

@Test func theCatalogScanLeadingIgnoresFolderProgress() {
    var work = BackgroundWork()
    work.update(running: [.catalogScan])
    work.update(running: [.catalogScan, .folderRecheck])
    let line = work.line(catalogProgress: catalog, folderPhase: .enumerating, inspectedEntries: 9)
    #expect(line?.text == "Checking npm cache… 4 of 31 · +1 more")
    #expect(line?.runsFolderScan == true)
}

@Test func onlyFolderScansCanBeStopped() {
    var work = BackgroundWork()
    work.update(running: [.catalogScan])
    #expect(work.line(catalogProgress: catalog)?.runsFolderScan == false)
}

// #308: after discovery the catalog scan goes on reading apps, plug-ins and app-managed storage; the line names each phase.

@Test func theCatalogLineCountsLocationsDuringDiscovery() {
    #expect(CatalogScanPhase.starting.progressText == "Checking known locations…")
    #expect(CatalogScanPhase.location(title: "npm cache", number: 4, total: 31).progressText == "Checking npm cache… 4 of 31")
}

@Test func theCatalogLineNamesEachPhaseAfterDiscovery() {
    #expect(CatalogScanPhase.removedAppLeftovers.progressText == "Checking leftovers of removed apps…")
    #expect(CatalogScanPhase.appsAndPlugIns.progressText == "Checking apps and plug-ins…")
    #expect(CatalogScanPhase.openApps.progressText == "Checking which apps are open…")
    #expect(CatalogScanPhase.storageTrends.progressText == "Recording storage trends…")
    #expect(CatalogScanPhase.appManagedStorage.progressText == "Checking app-managed storage…")
}


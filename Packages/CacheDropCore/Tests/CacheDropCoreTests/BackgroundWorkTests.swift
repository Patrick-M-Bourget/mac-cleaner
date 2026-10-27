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
    #expect(work.line(catalogProgress: catalog) == BackgroundWork.Line(id: "catalogScanProgress", text: "Checking npm cache… 4 of 31"))
}

@Test func aNewFolderScanIsNotARecheck() {
    var work = BackgroundWork()
    work.update(running: [.folderScan(folder: "Projects")])
    #expect(work.line(catalogProgress: catalog) == BackgroundWork.Line(id: "folderScanProgress", text: "Scanning Projects…"))
}

@Test func twoJobsShowTheEarliestPlusOneMore() {
    var work = BackgroundWork()
    work.update(running: [.folderRecheck])
    work.update(running: [.catalogScan, .folderRecheck])
    #expect(work.line(catalogProgress: catalog) == BackgroundWork.Line(id: "folderRecheckProgress", text: "Rechecking selected locations… · +1 more"))
}

@Test func whenTheEarliestFinishesTheNextTakesItsPlace() {
    var work = BackgroundWork()
    work.update(running: [.catalogScan])
    work.update(running: [.catalogScan, .folderRecheck])
    work.update(running: [.folderRecheck])
    #expect(work.line(catalogProgress: catalog) == BackgroundWork.Line(id: "folderRecheckProgress", text: "Rechecking selected locations…"))
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

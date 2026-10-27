import Testing
import CacheDropCore

// Decision 46: the bottom bar shows background work as one line, the work that started first plus "+1 more".

@Test func nothingRunningShowsNoLine() {
    var work = BackgroundWork()
    work.update(running: [])
    #expect(work.line { _ in "unused" } == nil)
}

@Test func oneJobShowsItsOwnText() {
    var work = BackgroundWork()
    work.update(running: ["catalog"])
    #expect(work.line { _ in "Checking npm cache… 4 of 31" } == BackgroundWork.Line(id: "catalog", text: "Checking npm cache… 4 of 31"))
}

@Test func twoJobsShowTheEarliestPlusOneMore() {
    var work = BackgroundWork()
    work.update(running: ["recheck"])
    work.update(running: ["catalog", "recheck"])
    let texts = ["catalog": "Checking npm cache… 4 of 31", "recheck": "Rechecking selected locations…"]
    #expect(work.line { texts[$0]! } == BackgroundWork.Line(id: "recheck", text: "Rechecking selected locations… · +1 more"))
}

@Test func whenTheEarliestFinishesTheNextTakesItsPlace() {
    var work = BackgroundWork()
    work.update(running: ["catalog"])
    work.update(running: ["catalog", "recheck"])
    work.update(running: ["recheck"])
    #expect(work.line { _ in "Rechecking selected locations…" } == BackgroundWork.Line(id: "recheck", text: "Rechecking selected locations…"))
    // Work that starts again later goes to the back.
    work.update(running: ["recheck", "catalog"])
    #expect(work.line { $0 } == BackgroundWork.Line(id: "recheck", text: "recheck · +1 more"))
}

@Test func threeJobsCountEveryOtherOne() {
    var work = BackgroundWork()
    work.update(running: ["a"])
    work.update(running: ["a", "b", "c"])
    #expect(work.line { $0 }?.text == "a · +2 more")
}

import Foundation
import Testing
@testable import CacheDropCore

// #781, Decision 188: Worth a look's Apps you haven't opened in 6 months. Every app is a fake bundle in a temp home's
// Applications folder, and every last-opened date is a fixture date; nothing on this Mac is read.

private struct Apps: AppPresence {
    var installed: [InstalledApp]
    func installedApps() -> [InstalledApp]? { installed }
    func isRegistered(bundleID: String) -> Bool { installed.contains { $0.bundleID.lowercased() == bundleID.lowercased() } }
}
private struct NoReceipts: InstallerReceiptReading { func receipts() -> [InstallerReceipt] { [] } }

/// A fixed "now": 2026-11-05 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_793_880_000)
private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * .secondsPerDay) }

/// A temp home with each app's bundle in its Applications folder and a preferences file tied to it by bundle ID.
private func home(_ apps: [(name: String, id: String, opened: Date?)]) throws -> (home: URL, installed: [InstalledApp]) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropWorthALookApps-\(UUID())").resolvingSymlinksInPath()
    var installed: [InstalledApp] = []
    for app in apps {
        for relative in ["Applications/\(app.name).app/Contents/MacOS/main", "Library/Preferences/\(app.id).plist"] {
            let file = home.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 2_000).write(to: file)
        }
        installed.append(InstalledApp(name: app.name, bundleID: app.id, path: home.appendingPathComponent("Applications/\(app.name).app").path, lastOpened: app.opened))
    }
    return (home, installed)
}
private func uninstallable(_ home: URL, _ installed: [InstalledApp]) -> [Candidate] {
    let apps = Apps(installed: installed)
    return installed.flatMap { AppUninstall.scan($0, excluding: nil, home: home, apps: apps, receipts: NoReceipts(), leftovers: []) }
}
private func names(_ items: [Candidate]) -> [String] { items.map { $0.url.deletingPathExtension().lastPathComponent } }

@Test func anAppCarriesTheLastOpenedDateSpotlightGaveItAndUnknownStaysUnknown() throws {
    let (home, installed) = try home([("Synth", "com.maker.synth", daysAgo(200)), ("Pad", "com.maker.pad", nil)])
    defer { try? FileManager.default.removeItem(at: home) }

    let found = uninstallable(home, installed)

    #expect(found.first { $0.url.lastPathComponent == "Synth.app" }?.uninstall?.lastOpened == daysAgo(200))
    #expect(found.first { $0.url.lastPathComponent == "Pad.app" }?.uninstall != nil)
    #expect(found.first { $0.url.lastPathComponent == "Pad.app" }?.uninstall?.lastOpened == nil, "Unknown, never \"never opened\"")
}

@Test func onlyAppsNotOpenedFor180DaysAreSuggestedNeverAppleOrUnknownOrHeld() throws {
    let (home, installed) = try home([("Old", "com.maker.old", daysAgo(400)), ("Edge", "com.maker.edge", daysAgo(180)), ("Recent", "com.maker.recent", daysAgo(179)),
                                      ("Unknown", "com.maker.unknown", nil), ("Busy", "com.maker.busy", daysAgo(300)), ("Held", "com.maker.held", daysAgo(300))])
    defer { try? FileManager.default.removeItem(at: home) }
    var found = uninstallable(home, installed)
    // The scan found Held in use (#374).
    if let index = found.firstIndex(where: { $0.url.lastPathComponent == "Held.app" }) { found[index].hold = CandidateHold(.ownerRunning("Held")) }
    // An Apple app that somehow reached the list, with an old date: still never suggested.
    let apple = InstalledApp(name: "Old", bundleID: "com.apple.old", path: installed[0].path, lastOpened: daysAgo(400))
    var appleItem = try #require(found.first { $0.url.lastPathComponent == "Old.app" })
    appleItem.uninstall = AppUninstall.Target(name: apple.name, bundleID: apple.bundleID, path: apple.path)
    appleItem.uninstall?.lastOpened = apple.lastOpened

    // Busy's owner runs now: held, so left out.
    let suggested = WorthALook.unopenedApps(in: found, now: now) { $0.uninstall?.name == "Busy" ? .ownerRunning("Busy") : nil }

    #expect(Set(names(suggested)) == ["Old", "Edge"], "Not opened for 180 days or more; unknown, recent, running and held left out")
    #expect(suggested.allSatisfy { $0.ruleID == AppUninstall.appRuleID }, "One row per app: the app itself, never its files")
    #expect(WorthALook.unopenedApps(in: [appleItem], now: now) { _ in nil }.isEmpty, "Apple's own apps are never suggested")
    #expect(WorthALook.unopenedDays == 180)
}

@Test func tickingASuggestedAppTicksItAsApplicationsDoesAndOnlyThenCountsInSmartClean() throws {
    let (home, installed) = try home([("Old", "com.maker.old", daysAgo(400)), ("Recent", "com.maker.recent", daysAgo(10))])
    defer { try? FileManager.default.removeItem(at: home) }
    let found = uninstallable(home, installed)
    let suggested = WorthALook.unopenedApps(in: found, now: now) { _ in nil }
    let items = WorthALook.items(of: suggested, in: found)
    #expect(Set(items.map(\.url.lastPathComponent)) == ["Old.app", "com.maker.old.plist"], "The app with its allow-listed files (Decision 57)")
    let catalog = Catalog(rules: AppUninstall.rules)

    var selections = CleanupSelections()
    selections.noteChoices(among: found, recommended: [])
    #expect(selections.smartClean(catalog: catalog, found: [], apps: items) { _ in nil }.isEmpty, "Never ticked for you")
    let revision = selections.revision(of: .smartClean)

    // The app's checkbox, as on Applications.
    let row = CategorySelection(rules: AppUninstall.rules, candidates: items, selected: selections.ticked)
    guard case .choose(let ids) = row.toggle else { Issue.record("Its checkbox ticks the app and its files"); return }
    selections.set(ids, ticked: true)
    selections.noteChoices(among: found, recommended: [], suggested: items)

    #expect(Set(selections.smartClean(catalog: catalog, found: [], apps: items) { _ in nil }.map(\.id)) == Set(items.map(\.id)))
    #expect(Set(selections.chosen(on: .applications, from: found).map(\.id)) == Set(items.map(\.id)), "One selection with Applications")
    #expect(selections.revision(of: .smartClean) != revision, "An open review sheet knows")
}

@Test func theGroupsCheckboxNeverTicksEveryAppAtOnce() throws {
    let (home, installed) = try home([("Old", "com.maker.old", daysAgo(400)), ("Older", "com.maker.older", daysAgo(800))])
    defer { try? FileManager.default.removeItem(at: home) }
    let items = WorthALook.items(of: WorthALook.unopenedApps(in: uninstallable(home, installed), now: now) { _ in nil }, in: uninstallable(home, installed))

    let none = CategorySelection(oneByOne: items, selected: [])
    #expect(none.state == .unchecked && none.toggle == .showItems, "Opens Choose apps, to tick one by one")
    let one = Set(items.filter { $0.url.path.contains("Old.app") || $0.url.lastPathComponent == "com.maker.old.plist" }.map(\.id))
    let some = CategorySelection(oneByOne: items, selected: one)
    #expect(some.state == .mixed && some.toggle == .clear(Set(items.map(\.id))))
}

@Test func eachRowSaysTheMonthAndYearItWasLastOpened() {
    let gmt = TimeZone(identifier: "UTC")!
    #expect(WorthALook.lastOpenedText(Date(timeIntervalSince1970: 1_773_000_000), timeZone: gmt) == "Last opened March 2026")
    #expect(WorthALook.lastOpenedText(Date(timeIntervalSince1970: 1_767_225_599), timeZone: gmt) == "Last opened December 2025")
    #expect(WorthALook.appsTitle == "Apps you haven’t opened in 6 months")
}

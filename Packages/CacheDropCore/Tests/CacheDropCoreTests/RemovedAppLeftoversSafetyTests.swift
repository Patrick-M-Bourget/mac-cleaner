import Foundation
import Testing
@testable import CacheDropCore

// #251: what the real-Mac check of leftovers (#173) offered by mistake. Each fixture is shaped like an item found on that Mac:
// preferences and folders of installed plug-ins, Apple's Shortcuts data and a command-line tool's files. Every test uses a temp
// home and system root; installed bundles are read from fixture folders, never this Mac's.

private func fixtureFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropLeftovers\(name)-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: 100).write(to: file)
}
/// A bundle with only an Info.plist: a plug-in, preference pane, service or helper app. Its code is never loaded.
private func bundle(_ relative: String, in root: URL, id: String, component: String? = nil, copyright: String? = nil) throws {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": id]
    if let component { info["AudioComponents"] = [["name": component, "manufacturer": "Fxtr", "type": "aufx", "subtype": "fxtr"]] }
    if let copyright { info["NSHumanReadableCopyright"] = copyright }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
}

private struct Apps: AppPresence {
    var installed: [InstalledApp]? = []
    func installedApps() -> [InstalledApp]? { installed }
    func isRegistered(bundleID: String) -> Bool { false }
}
private struct NoReceipts: InstallerReceiptReading { func receipts() -> [InstallerReceipt] { [] } }

/// The plug-ins on the user's Mac that the bad listing ignored, in the shapes `plugins-199-after` lists.
private func installPlugIns(in root: URL) throws {
    let components = "Library/Audio/Plug-Ins/Components/", aax = "Library/Application Support/Avid/Audio/Plug-Ins/"
    try bundle(components + "RePitch.component", in: root, id: "com.synchroarts.RePitch", component: "Synchro Arts: RePitch")
    try bundle(components + "VocAlign.component", in: root, id: "com.synchroarts.VocAlign", component: "Synchro Arts: VocAlign")
    try bundle(aax + "THE_STRIP 2.aaxplugin", in: root, id: "com.myPhilspeiser.product", copyright: "© 2024 PHIL SPEISER")
    try bundle(components + "Reason Rack Plugin.component", in: root, id: "se.propellerheads.reasonrackplugin.au", component: "Reason Studios: Reason Rack Plugin Effect")
    try bundle("Library/Audio/Plug-Ins/VST3/iZotope/Ozone 12 Equalizer.vst3", in: root, id: "com.izotope.Ozone12Equalizer")
    try bundle(components + "FabFilter Pro-Q 4.component", in: root, id: "com.fabfilter.Pro-Q.AU.4", component: "FabFilter: Pro-Q 4")
    try bundle(aax + "Splice.aaxplugin", in: root, id: "com.splice.pro-tools-integration")
    try bundle(components + "Trigger_2.component", in: root, id: "com.stevenslate.Trigger_2", component: "Steven Slate: Trigger 2")
}
private func installed(_ home: URL, _ root: URL) -> Apps { Apps(installed: InstalledBundles.scan(home: home, systemRoot: root)) }
private func scan(_ home: URL, _ apps: Apps) -> [Candidate] { RemovedAppLeftovers.scan(home: home, apps: apps, receipts: NoReceipts()) }
private func names(_ found: [Candidate]) -> Set<String> { Set(found.map(\.url.lastPathComponent)) }
private func confirmed(_ found: [Candidate]) -> Set<String> { names(found.filter { $0.ruleID == RemovedAppLeftovers.ruleID }) }

@Test func installedBundlesIncludePlugInsWithTheirMakerAndOtherBundlesInStandardPlaces() throws {
    let home = try fixtureFolder("Home"), root = try fixtureFolder("Root")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: root) }
    try installPlugIns(in: root)
    try bundle("Library/PreferencePanes/Gizmo.prefPane", in: root, id: "com.gizmo.prefpane")
    try bundle("Library/Services/Clipper.service", in: home, id: "com.clipper.service")
    try bundle("Library/Application Support/Toolmaker/Helpers/Toolmaker Agent.app", in: home, id: "com.toolmaker.agent")

    let found = InstalledBundles.scan(home: home, systemRoot: root)
    let ids = Set(found.map(\.bundleID))

    #expect(ids.isSuperset(of: ["com.synchroarts.RePitch", "com.myPhilspeiser.product", "se.propellerheads.reasonrackplugin.au", "com.izotope.Ozone12Equalizer",
                                "com.gizmo.prefpane", "com.clipper.service", "com.toolmaker.agent"]))
    #expect(found.first { $0.bundleID == "se.propellerheads.reasonrackplugin.au" }?.maker == "Reason Studios")
    #expect(found.first { $0.bundleID == "com.myPhilspeiser.product" }?.maker == "PHIL SPEISER")
}

@Test func preferencesOfInstalledPlugInsAreNeverOffered() throws {
    let home = try fixtureFolder("Home"), root = try fixtureFolder("Root")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: root) }
    try installPlugIns(in: root)
    // As found on the user's Mac. Nautilus's maker is installed only under its other ID (`se.propellerheads`), as "Reason Studios".
    for name in ["com.synchroarts.RePitch", "com.synchroarts.RePitchAAX", "com.synchroarts.VocAlign6Pro", "com.synchroarts.VocAlignVST3",
                 "com.myPhilspeiser.product", "se.propellerheads.reason", "se.propellerheads.reason-recon", "com.reasonstudios.nautilus",
                 "com.izotope.ozone12", "com.izotope.plist"] {
        try write(home, "Library/Preferences/\(name).plist")
    }
    try write(home, "Library/Saved Application State/se.propellerheads.reason.savedState/data.data")

    #expect(scan(home, installed(home, root)).isEmpty)
}

@Test func foldersOfAnInstalledPlugInsMakerAreNeverOffered() throws {
    let home = try fixtureFolder("Home"), root = try fixtureFolder("Root")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: root) }
    try installPlugIns(in: root)
    for folder in ["FabFilter/Pro-Q 4/Presets/x", "Reason Companion/x", "SynchroArts/RePitch/x", "com.splice.INSTRUMENT/x", "iZotope/OZONE12MS/x"] {
        try write(home, "Library/Application Support/" + folder)
    }
    // A removed app of each maker, confirmed by its container, would otherwise tie the folders to it by name.
    for id in ["com.fabfilter.oldsuite", "se.propellerheads.reason", "com.synchroarts.revoice", "com.splice.splice", "com.izotope.rx"] {
        try write(home, "Library/Containers/\(id)/Data/x")
    }

    #expect(scan(home, installed(home, root)).isEmpty)
}

@Test func shortcutsDataIsNeverOfferedThoughItsIDIsNotApples() throws {
    let home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Group Containers/group.is.workflow.shortcuts/Shortcuts.sqlite")
    try write(home, "Library/Group Containers/group.is.workflow.my.app/x")
    try write(home, "Library/Containers/is.workflow.my.app/Data/x")
    try write(home, "Library/Preferences/is.workflow.my.app.plist")

    #expect(scan(home, Apps()).isEmpty)
}

@Test func aGroupContainerIsOfferedOnlyOnAnExactMatchToARemovedAppsID() throws {
    let home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: home) }
    try write(home, "Library/Containers/com.gone.synth/Data/x")
    try write(home, "Library/Group Containers/group.com.gone.synth/x")
    try write(home, "Library/Group Containers/ABCDE12345.com.gone.synth/x")
    // Shared with other apps of the maker, or named for no removed app: never matched by prefix.
    try write(home, "Library/Group Containers/group.com.gone.synth.shared/x")
    try write(home, "Library/Group Containers/ABCDE12345.com.gone.suite/x")
    try write(home, "Library/Group Containers/ABCDE12345.com.gone/x")

    let found = scan(home, Apps())

    #expect(names(found) == ["com.gone.synth", "group.com.gone.synth", "ABCDE12345.com.gone.synth"])
    #expect(confirmed(found) == names(found))
}

@Test func aCommandLineToolsFilesAreOnlyPossiblyRelated() throws {
    let home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: home) }
    // No app, plug-in or receipt has these IDs: a command-line tool, or an installer that is gone, wrote them.
    try write(home, "Library/Preferences/org.swift.swiftpm.plist")
    try write(home, "Library/Caches/org.swift.swiftpm/x")
    try write(home, "Library/Preferences/com.yme.slateaudio-center.plist")

    let found = scan(home, Apps())

    #expect(names(found) == ["org.swift.swiftpm.plist", "org.swift.swiftpm", "com.yme.slateaudio-center.plist"])
    #expect(confirmed(found).isEmpty)
    #expect(found.allSatisfy { $0.leftover?.reason?.contains("no app") == true })
}

/// Running nothing; the check reads presence from `apps`.
private struct NothingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }

@Test func theCheckBeforeActingAppliesTheSameRules() throws {
    let home = try fixtureFolder("Home"), root = try fixtureFolder("Root")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: root) }
    try installPlugIns(in: root)
    let relatives = ["Library/Preferences/com.synchroarts.RePitch.plist", "Library/Preferences/com.reasonstudios.nautilus.plist",
                     "Library/Application Support/FabFilter", "Library/Group Containers/group.is.workflow.shortcuts",
                     "Library/Group Containers/group.com.gone.synth.shared"]
    for relative in relatives { try write(home, relative + (relative.hasSuffix(".plist") ? "" : "/x")) }
    // Ties a scan before #251 made; each reaches the check as a confirmed leftover.
    let catalog = Catalog(rules: fixtureRules), rule = try #require(catalog.rule(RemovedAppLeftovers.ruleID))
    let forged = try zip(relatives, ["com.synchroarts.RePitch", "com.reasonstudios.nautilus", "com.fabfilter.oldsuite", "is.workflow.shortcuts", "com.gone.synth"])
        .map { relative, id -> Candidate in
            let url = home.appendingPathComponent(relative)
            var info = stat()
            #expect(lstat(url.path, &info) == 0)
            var item = catalog.candidate(rule, url, info, logical: 100, allocated: nil, complete: true, lastUsed: nil)
            item.leftover = LeftoverTie(app: "Gone", bundleID: id, vendor: RemovedAppLeftovers.vendor(of: id), evidence: .bundleID)
            return try #require(item.found(under: home) as Candidate?)
        }
    let check = CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: FixtureNothingInUse(), home: home, apps: installed(home, root))

    #expect(forged.map(check.check).allSatisfy { $0 != nil }, "\(forged.map(check.check))")
}

@Test func filesOfFrameworksSharedByManyAppsAreNeverOffered() throws {
    let home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: home) }
    // Named by a framework or SDK that installed apps embed, not by any app: found on the user's Mac.
    for relative in ["Preferences/org.sparkle-project.Sparkle.Autoupdate.plist", "Caches/com.juce.locks/x", "Preferences/com.segment.storage.oai.plist",
                     "Preferences/com.telemetrydeck.7fb09d7d2046.plist", "Caches/io.branch.network.cache/x", "Preferences/com.github.Electron.plist"] {
        try write(home, "Library/" + relative)
    }

    #expect(scan(home, Apps()).isEmpty)
}

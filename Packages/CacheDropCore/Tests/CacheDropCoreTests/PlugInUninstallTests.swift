import Foundation
import Testing
@testable import CacheDropCore

// #176: uninstalling a plug-in product. Every test builds a disposable fixture system root with fake plug-in bundles and
// real installer receipts (`mkbom`), never the real Plug-Ins folders or `/var/db/receipts`; running apps and the Trash are fixtures.

private struct Running: RunningAppChecking {
    var names: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? { names.contains(owner.name) }
}
private struct NoApps: AppPresence {
    func installedApps() -> [InstalledApp]? { [] }
    func isRegistered(bundleID: String) -> Bool { false }
}
private struct RootTrash: TrashMoving {
    let root: URL
    func moveToTrash(_ url: URL) throws -> URL? {
        let destination = root.appendingPathComponent(".Trash/" + UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

private let plugIns = "Library/Audio/Plug-Ins/", support = "Library/Application Support/Maker/"

private func write(_ relative: String, in root: URL, bytes: Int = 300) throws {
    let file = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
private func plugIn(_ relative: String, id: String, in root: URL) throws {
    let bundle = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
}
/// A real installer receipt for what is at `paths` under `root` now, as an installer records it.
private func receipt(_ id: String, listing paths: [String], in root: URL) throws {
    let receipts = root.appendingPathComponent("var/db/receipts")
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropReceipt-\(UUID())")
    defer { try? FileManager.default.removeItem(at: staging) }
    try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
    for path in paths {
        try FileManager.default.createDirectory(at: staging.appendingPathComponent(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent(path), to: staging.appendingPathComponent(path))
    }
    let info: [String: Any] = ["PackageIdentifier": id, "PackageVersion": "1.0", "InstallPrefixPath": "/"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: receipts.appendingPathComponent(id + ".plist"))
    let mkbom = Process()
    mkbom.executableURL = URL(fileURLWithPath: "/usr/bin/mkbom")
    mkbom.arguments = [staging.path, receipts.appendingPathComponent(id + ".bom").path]
    try mkbom.run(); mkbom.waitUntilExit()
    #expect(mkbom.terminationStatus == 0)
}

/// Pro Synth (AU, VST3, its own presets and a license file its receipt lists), Pro Delay of the same maker, and a suite
/// receipt both install a shared folder from.
private func fixture() throws -> (root: URL, home: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropPlugInUninstall-\(UUID())").resolvingSymlinksInPath()
    let home = root.appendingPathComponent("Users/me")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try plugIn(plugIns + "Components/Pro Synth.component", id: "com.maker.prosynth.au", in: root)
    try plugIn(plugIns + "VST3/Pro Synth.vst3", id: "com.maker.prosynth.vst3", in: root)
    try plugIn(plugIns + "VST3/Pro Delay.vst3", id: "com.maker.prodelay.vst3", in: root)
    try write(support + "Pro Synth/Presets/Init.preset", in: root)
    try write(support + "Pro Synth/License.dat", in: root)
    try write(support + "Pro Delay/Presets/Echo.preset", in: root)
    try write(support + "Shared/Engine.dat", in: root, bytes: 5000)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth"], in: root)
    try receipt("com.maker.prodelay.pkg", listing: [plugIns + "VST3/Pro Delay.vst3", support + "Pro Delay"], in: root)
    // A suite receipt lists both products and their shared folder.
    try receipt("com.maker.suite.pkg", listing: [plugIns + "VST3/Pro Synth.vst3", plugIns + "VST3/Pro Delay.vst3", support + "Shared"], in: root)
    try FileManager.default.createDirectory(at: root.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    return (root, home)
}
private func scan(_ root: URL, _ home: URL, apps: [InstalledApp] = []) -> (inventory: PlugInInventory, items: [Candidate]) {
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5))
    let listings = PlugInUninstall.listings(of: Set(inventory.products.flatMap(\.receipts)), under: root)
    return (inventory, PlugInUninstall.scan(inventory, apps: apps, listings: listings, systemRoot: root))
}
private func product(_ name: String, _ inventory: PlugInInventory) throws -> String { try #require(inventory.products.first { $0.name == name }).id }
private func check(_ home: URL, running: Running = Running()) -> CandidateCheck {
    CandidateCheck(catalog: Catalog(rules: PlugInUninstall.rules), running: running, inUse: FixtureNothingInUse(), home: home, apps: NoApps())
}
private func names(_ items: [Candidate]) -> Set<String> { Set(items.map(\.url.lastPathComponent)) }

@Test func aProductIsOfferedWithEveryFormatAndItsOwnSupportFilesNothingOfAnotherProduct() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let (inventory, items) = scan(root, home)
    let synth = try product("Pro Synth", inventory)
    let own = items.filter { $0.uninstall?.path == synth && $0.sharedBy.isEmpty }

    #expect(names(own.filter { $0.ruleID == PlugInUninstall.formatsRuleID }) == ["Pro Synth.component", "Pro Synth.vst3"])
    // Its own folder in the maker's folder, never the maker's folder, which holds the other product's files too.
    #expect(names(own.filter { $0.ruleID == PlugInUninstall.filesRuleID }) == ["Pro Synth"])
    #expect(!items.contains { $0.isUninstalled(with: synth) && $0.url.path.contains("Pro Delay") }, "Nothing of another product, even from the same maker")
}

@Test func aLicenseFileIsNeverOffered() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.removeItem(at: root.appendingPathComponent(support + "Pro Synth/License.dat"))
    try write(support + "Pro Synth License", in: root)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth",
                                                    support + "Pro Synth License"], in: root)
    let (_, items) = scan(root, home)
    #expect(!items.contains { $0.url.lastPathComponent == "Pro Synth License" })
}

@Test func sharedItemsAreListedUnderEveryProductCountedOnceAndNeverTickedWithIt() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let (inventory, items) = scan(root, home)
    let synth = try product("Pro Synth", inventory), delay = try product("Pro Delay", inventory)
    let shared = items.filter { $0.ruleID == PlugInUninstall.sharedRuleID }

    #expect(names(shared) == ["Shared"] && shared.count == 1, "Counted once")
    #expect(shared[0].isUninstalled(with: synth) && shared[0].isUninstalled(with: delay))
    #expect(shared[0].sharedBy.count == 2, "The row says how many products share it")
    let selection = CategorySelection(rules: PlugInUninstall.rules, candidates: items.filter { $0.isUninstalled(with: synth) }, selected: [])
    guard case .choose(let ids) = selection.toggle else { Issue.record("The product ticks its own items"); return }
    #expect(!ids.contains(shared[0].id), "A shared item is ticked one by one only")
}

@Test func formatsThatNeedAPasswordAreNeverOfferedAndTheReviewSaysTheyStay() throws {
    let (root, home) = try fixture()
    let components = root.appendingPathComponent(plugIns + "Components")
    defer { chmod(components.path, 0o755); try? FileManager.default.removeItem(at: root) }
    // As on a real Mac, the AU folder is not the user's to change (#268).
    chmod(components.path, 0o555)
    let nativeAccess = InstalledApp(name: "Native Access", bundleID: "com.native-instruments.nativeaccess2", path: "/Applications/Native Access.app")
    let (inventory, items) = scan(root, home, apps: [nativeAccess])
    let synth = try product("Pro Synth", inventory)
    let own = items.filter { $0.uninstall?.path == synth && $0.sharedBy.isEmpty }

    #expect(!own.contains { $0.url.pathExtension == "component" })
    #expect(AppUninstall.staying(chosen: own, offered: items).map(\.text).contains("Pro Synth: 1 part stays · Needs your password"))
}

@Test func uninstallingMovesTheProductToTrashAndPutBackRestoresEveryItem() async throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let (inventory, items) = scan(root, home)
    let synth = try product("Pro Synth", inventory)
    let chosen = items.filter { $0.uninstall?.path == synth && $0.sharedBy.isEmpty }
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("journal.sqlite"))

    let result = await CleanupExecutor(journal: journal, check: check(home), measure: { _ in nil }, trash: RootTrash(root: root))
        .execute(CatalogApproval(candidates: chosen, previewOnly: false))

    #expect(result.records.count == 3 && result.records.allSatisfy { $0.state == .succeeded }, "\(result.records.map(\.message))")
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(plugIns + "VST3/Pro Delay.vst3").path), "Another product stays")
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(support + "Shared").path), "A shared item stays unless ticked")
    let run = try #require(try journal.completedHistory().completedRuns.first)
    #expect(run.title == "Uninstalled Pro Synth · 3 items")
    for record in result.records { #expect(TrashPutBack(journal: journal).putBack(record) == .restored(record.originalURL)) }
    #expect(chosen.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
}

@Test func aRunningHostOrTheProductsOwnAppBlocksIt() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = InstalledApp(name: "Pro Synth", bundleID: "com.maker.prosynth.app", path: "/Applications/Pro Synth.app")
    let (inventory, items) = scan(root, home, apps: [app])
    let own = try items.filter { try $0.uninstall?.path == product("Pro Synth", inventory) }
    #expect(!own.isEmpty && own.allSatisfy { check(home).check($0) == nil })

    #expect(own.allSatisfy { check(home, running: Running(names: ["Ableton Live"])).check($0) == .ownerRunning("Ableton Live") })
    #expect(own.allSatisfy { check(home, running: Running(names: ["Pro Synth"])).check($0) == .ownerRunning("Pro Synth") })
    #expect(Catalog(rules: PlugInUninstall.rules).owner(for: own[0])?.bundleIDs.contains("com.maker.prosynth.app") == true, "Its standalone app")
    #expect(Set(PlugInUninstall.hosts.map(\.name)).isSuperset(of: ["Logic Pro", "GarageBand", "MainStage", "Ableton Live", "Reason", "Pro Tools", "Cubase",
                                                                   "Studio One", "Bitwig Studio", "FL Studio", "REAPER"]))
}

@Test func aFormatThatChangedOrNeedsAPasswordSinceTheScanIsRefusedNotMoved() throws {
    let (root, home) = try fixture()
    let bundle = root.appendingPathComponent(plugIns + "VST3/Pro Synth.vst3")
    defer { chmod(bundle.path, 0o755); try? FileManager.default.removeItem(at: root) }
    let (_, items) = scan(root, home)
    let format = try #require(items.first { $0.url.lastPathComponent == "Pro Synth.vst3" })
    #expect(check(home).check(format) == nil)

    // Another product's bundle now sits at the path the scan tied to Pro Synth.
    let info = format.url.appendingPathComponent("Contents/Info.plist")
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.other.thing"], format: .xml, options: 0).write(to: info)
    #expect(check(home).check(format) == .changed)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.maker.prosynth.vst3"], format: .xml, options: 0).write(to: info)
    // The bundle is no longer the user's to change: macOS would ask for a password (Decision 50).
    chmod(bundle.path, 0o555)
    #expect(check(home).check(format) == .notPermitted)
}

@Test func anAUv3GoesWithItsAppAndApplesFoldersAreNeverOffered() throws {
    #expect(PlugInUninstall.isNeverTouched(URL(fileURLWithPath: "/Library/Application Support/Logic/Plug-In Settings/x"), below: URL(fileURLWithPath: "/")))
    #expect(PlugInUninstall.isNeverTouched(URL(fileURLWithPath: "/Library/Audio/Apple Loops/Maker"), below: URL(fileURLWithPath: "/")))
    #expect(!PlugInUninstall.isNeverTouched(URL(fileURLWithPath: "/Library/Application Support/Maker/Pro Synth"), below: URL(fileURLWithPath: "/")))
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let appex = root.appendingPathComponent("Applications/Pad.app/Contents/PlugIns/Pad.appex")
    try FileManager.default.createDirectory(at: appex.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.maker.pad.auv3", "NSExtension": ["NSExtensionPointIdentifier": "com.apple.AudioUnit"]],
                                       format: .xml, options: 0).write(to: appex.appendingPathComponent("Contents/Info.plist"))
    try plugIn(plugIns + "VST3/Pad.vst3", id: "com.maker.pad.vst3", in: root)
    let pad = InstalledApp(name: "Pad", bundleID: "com.maker.pad", path: root.appendingPathComponent("Applications/Pad.app").path)
    let (inventory, items) = scan(root, home, apps: [pad])
    let own = try items.filter { try $0.uninstall?.path == product("Pad", inventory) }

    #expect(names(own) == ["Pad.vst3"], "The AUv3 is never moved out of its app")
    #expect(AppUninstall.staying(chosen: own, offered: own).map(\.text) == ["Pad: 1 part stays · Goes with the app it is in"])
    #expect(own[0].uninstall?.owner.paths.contains(pad.path) == true, "The app it is in counts as the product running")
}

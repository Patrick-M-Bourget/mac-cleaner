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
private func fixture(in folder: String? = nil) throws -> (root: URL, home: URL) {
    let base = folder.map { FileManager.default.temporaryDirectory.appendingPathComponent($0 + "-\(UUID())") } ?? FileManager.default.temporaryDirectory
    let root = base.appendingPathComponent("CacheDropPlugInUninstall-\(UUID())").resolvingSymlinksInPath()
    let home = root.appendingPathComponent("Users/me")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try plugIn(plugIns + "Components/Pro Synth.component", id: "com.maker.prosynth.au", in: root)
    try plugIn(plugIns + "VST3/Pro Synth.vst3", id: "com.maker.prosynth.vst3", in: root)
    try plugIn(plugIns + "VST3/Pro Delay.vst3", id: "com.maker.prodelay.vst3", in: root)
    try write(support + "Pro Synth/Presets/Init.fxp", in: root)
    try write(support + "Pro Synth/License.dat", in: root)
    try write(support + "Pro Delay/Presets/Echo.fxp", in: root)
    try write(support + "Shared/Engine.wav", in: root, bytes: 5000)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth"], in: root)
    try receipt("com.maker.prodelay.pkg", listing: [plugIns + "VST3/Pro Delay.vst3", support + "Pro Delay"], in: root)
    // A suite receipt lists both products and their shared folder.
    try receipt("com.maker.suite.pkg", listing: [plugIns + "VST3/Pro Synth.vst3", plugIns + "VST3/Pro Delay.vst3", support + "Shared"], in: root)
    try FileManager.default.createDirectory(at: root.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    return (root, home)
}
private func scan(_ root: URL, _ home: URL, apps: [InstalledApp] = []) -> (inventory: PlugInInventory, items: [Candidate]) {
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5), receipts: ReceiptListings.read(under: root))
    return (inventory, PlugInUninstall.scan(inventory, apps: apps, receipts: ReceiptListings.read(under: root), systemRoot: root))
}
private func product(_ name: String, _ inventory: PlugInInventory) throws -> String { try #require(inventory.products.first { $0.name == name }).id }
/// The check reads the fixture root's receipts, the home's grandparent.
private func check(_ home: URL, running: Running = Running()) -> CandidateCheck {
    CandidateCheck(catalog: Catalog(rules: PlugInUninstall.rules), running: running, inUse: FixtureNothingInUse(), home: home, apps: NoApps(),
                   systemRoot: home.deletingLastPathComponent().deletingLastPathComponent())
}
private func names(_ items: [Candidate]) -> Set<String> { Set(items.map(\.url.lastPathComponent)) }

@Test func aProductIsOfferedWithEveryFormatAndItsOwnSupportFilesNothingOfAnotherProduct() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let (inventory, items) = scan(root, home)
    let synth = try product("Pro Synth", inventory)
    let own = items.filter { $0.uninstall?.path == synth && $0.sharedBy.isEmpty }

    #expect(names(own.filter { $0.ruleID == PlugInUninstall.formatsRuleID }) == ["Pro Synth.component", "Pro Synth.vst3"])
    // Its own presets in the maker's folder, never the maker's folder, which holds the other product's files too, nor its
    // own folder, which holds its license file (#288).
    #expect(names(own.filter { $0.ruleID == PlugInUninstall.filesRuleID }) == ["Presets"])
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

@Test func anAAXIsOfferedOnceAsAFormatNeverAsASupportFileNorItsFolders() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let aax = "Library/Application Support/Avid/Audio/Plug-Ins/Pro Synth.aaxplugin"
    try plugIn(aax, id: "com.maker.prosynth.aax", in: root)
    // The AAX lives in Application Support, and the receipt lists it (and so, wholly, the Avid folder holding only it).
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth", aax], in: root)
    try receipt("com.maker.suite.pkg", listing: [plugIns + "VST3/Pro Synth.vst3", plugIns + "VST3/Pro Delay.vst3", support + "Shared", aax], in: root)
    let (_, items) = scan(root, home)

    #expect(items.filter { $0.url.lastPathComponent == "Pro Synth.aaxplugin" }.map(\.ruleID) == [PlugInUninstall.formatsRuleID], "Once, as a format")
    #expect(!items.contains { $0.ruleID != PlugInUninstall.formatsRuleID && $0.url.path.contains("/Avid") }, "Never Avid's plug-in folders")
}

@Test func aFolderAnotherProductsOwnReceiptAlsoListsIsSharedNotEitherProductsOwn() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(support + "Common/Impulses.wav", in: root)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth",
                                                    support + "Common"], in: root)
    try receipt("com.maker.prodelay.pkg", listing: [plugIns + "VST3/Pro Delay.vst3", support + "Pro Delay", support + "Common"], in: root)
    let (_, items) = scan(root, home)
    let common = items.filter { $0.url.lastPathComponent == "Common" }

    #expect(common.count == 1 && common[0].ruleID == PlugInUninstall.sharedRuleID && common[0].sharedBy.count == 2)
}

@Test func aSupportFolderThatGainedALicenseOrAnyUnlistedFileSinceTheScanIsRefusedNotMoved() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, items) = scan(root, home)
    let presets = try #require(items.first { $0.url.lastPathComponent == "Presets" })
    #expect(check(home).check(presets) == nil)

    try write(support + "Pro Synth/Presets/My Sound.fxp", in: root)
    #expect(check(home).check(presets) == .changed, "A file the receipt doesn't list may be the user's")
    try FileManager.default.removeItem(at: root.appendingPathComponent(support + "Pro Synth/Presets/My Sound.fxp"))
    try write(support + "Pro Synth/Presets/iLok Activation.dat", in: root)
    #expect(check(home).check(presets) == .protected("iLok Activation.dat"), "License data is never moved")
}

@Test func aSharedItemWaitsForEverySharersOwnAppAndTheReviewNamesTheProductBeingUninstalled() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let apps = ["Pro Synth", "Pro Delay"].map { InstalledApp(name: $0, bundleID: "com.maker." + $0.lowercased().replacingOccurrences(of: " ", with: "") + ".app",
                                                            path: "/Applications/\($0).app") }
    let (inventory, items) = scan(root, home, apps: apps)
    let shared = try #require(items.first { $0.ruleID == PlugInUninstall.sharedRuleID })

    for app in ["Pro Synth", "Pro Delay"] { #expect(check(home, running: Running(names: [app])).check(shared) == .ownerRunning(app), "\(app) is running") }
    #expect(check(home, running: Running(names: ["REAPER"])).check(shared) == .ownerRunning("REAPER"))
    let delay = try product("Pro Delay", inventory)
    // Pro Delay's formats and the shared folder, its presets left unticked.
    let chosen = items.filter { $0.uninstall?.path == delay && $0.ruleID == PlugInUninstall.formatsRuleID } + [shared]
    let lines = AppUninstall.staying(chosen: chosen, offered: items).map(\.text)
    #expect(!lines.isEmpty && lines.allSatisfy { $0.hasPrefix("Pro Delay: ") }, "\(lines)")
}

@Test func sharedContentCountsProductsOnlyIsNamedForItsVendorAndIsKeptWhenItsFirstOwnerOffersNothingElse() throws {
    let (root, home) = try fixture()
    let delayVST3 = root.appendingPathComponent(plugIns + "VST3/Pro Delay.vst3")
    defer { chmod(delayVST3.path, 0o755); try? FileManager.default.removeItem(at: root) }
    // Pro Delay offers nothing of its own: its VST3 needs a password and its presets are gone.
    chmod(delayVST3.path, 0o555)
    try FileManager.default.removeItem(at: root.appendingPathComponent(support + "Pro Delay"))
    try write("Library/Application Support/Maker Content/Sounds.wav", in: root)
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5), receipts: ReceiptListings.read(under: root))
    let synth = try product("Pro Synth", inventory), delay = try product("Pro Delay", inventory)
    let library = MusicContentItem(name: "Sounds", vendors: ["Maker"], url: root.appendingPathComponent("Library/Application Support/Maker Content"), kind: .installed,
                                   state: .present(.unknown), owners: [delay, "/Applications/Maker Hub.app", synth], tie: .vendor)
    let items = PlugInUninstall.scan(inventory, apps: [], receipts: ReceiptListings([:]), content: [library], systemRoot: root)
    let content = try #require(items.first { $0.url == library.url })

    #expect(content.sharedBy == [delay, synth], "Products only, never an app")
    #expect(content.sharedLabel == "Shared by Maker products")
    #expect(content.uninstall != nil)
}

@Test func whatNeedsAPasswordIsListedWithTheVendorsToolFromTheApplicationsPagesLookup() throws {
    let (root, home) = try fixture()
    let presets = root.appendingPathComponent(support + "Pro Synth/Presets")
    defer { chmod(presets.path, 0o755); try? FileManager.default.removeItem(at: root) }
    chmod(presets.path, 0o555)
    try plugIn(plugIns + "VST3/Kontakt.vst3", id: "com.native-instruments.kontakt.vst3", in: root)
    let nativeAccess = InstalledApp(name: "Native Access", bundleID: "com.native-instruments.NativeAccess2", path: "/Applications/Native Access.app")
    let (inventory, items) = scan(root, home, apps: [nativeAccess])

    #expect(items.first { try! $0.uninstall?.path == product("Kontakt", inventory) }?.uninstall?.tool == "Native Access")
    let synth = try #require(items.first { try! $0.uninstall?.path == product("Pro Synth", inventory) }?.uninstall)
    #expect(synth.passwordPaths == [presets.path] && synth.tool == nil)
}

@Test func aPathAnyOtherReceiptListsEvenOneWithNoPlugInIsShared() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    // A vendor's content pkg, with no plug-in, also lists one file inside Pro Synth's presets.
    try receipt("com.maker.common.pkg", listing: [support + "Pro Synth/Presets/Init.fxp"], in: root)
    let (inventory, items) = scan(root, home)
    let presets = try #require(items.first { $0.url.lastPathComponent == "Presets" })

    #expect(presets.ruleID == PlugInUninstall.sharedRuleID, "Never Pro Synth's own")
    #expect(presets.isUninstalled(with: try product("Pro Synth", inventory)))
    #expect(presets.sharedLabel == "Shared with another installer")
}

@Test func aProductInstalledSinceTheScanThatListsASupportItemMakesItRefused() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, items) = scan(root, home)
    let presets = try #require(items.first { $0.url.lastPathComponent == "Presets" })
    #expect(presets.ruleID == PlugInUninstall.filesRuleID && check(home).check(presets) == nil)

    // Pro Verb's installer, run after the scan, rewrote a preset Pro Synth's receipt also lists: nothing new on disk.
    try plugIn(plugIns + "VST3/Pro Verb.vst3", id: "com.maker.proverb.vst3", in: root)
    try receipt("com.maker.proverb.pkg", listing: [plugIns + "VST3/Pro Verb.vst3", support + "Pro Synth/Presets/Init.fxp"], in: root)
    #expect(check(home).check(presets) == .changed, "Read again before acting: it is shared now")
}

@Test func aSuiteFolderHoldingEachProductsFolderIsNeverOfferedWholeOnlyTheNarrowestFolders() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let maker = "Library/Application Support/Maker"
    try FileManager.default.removeItem(at: root.appendingPathComponent(support + "Pro Synth/License.dat"))
    // Only the suite receipt lists the maker's folder, with each product's folder and the shared one in it.
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3"], in: root)
    try receipt("com.maker.prodelay.pkg", listing: [plugIns + "VST3/Pro Delay.vst3"], in: root)
    try receipt("com.maker.suite.pkg", listing: [plugIns + "VST3/Pro Synth.vst3", plugIns + "VST3/Pro Delay.vst3", maker], in: root)
    let (_, items) = scan(root, home)

    #expect(!items.contains { $0.url.path == root.appendingPathComponent(maker).path }, "Never the folder above both products' files")
    #expect(names(items.filter { $0.ruleID == PlugInUninstall.sharedRuleID }).isSuperset(of: ["Shared", "Pro Synth", "Pro Delay"]))
}

private func plist(_ relative: String, _ value: [String: Any], in root: URL) throws {
    let file = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: file)
}

@Test func licenceDataIsNeverOfferedByNameKindOrPreferenceKeysAtTheScanOrTheRun() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let prefs = "Library/Preferences/com.maker.prosynth.plist"
    try plist(prefs, ["SerialNumber": "ABCD-1234", "Theme": "Dark"], in: root)
    try write(support + "Pro Synth/Skins/Dark.png", in: root)
    try write(support + "Pro Synth/Skins/state.dat", in: root)
    try write(support + "Pro Synth/Docs/Registration Info.txt", in: root)
    try write(support + "Pro Synth/Docs/Manual.pdf", in: root)
    try plist(support + "Pro Synth/Presets/Settings.plist", ["Volume": 1], in: root)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth", prefs], in: root)
    let (_, items) = scan(root, home)

    #expect(!items.contains { $0.url.lastPathComponent == "com.maker.prosynth.plist" }, "A preference with a serial number")
    #expect(!items.contains { $0.url.lastPathComponent == "Skins" }, "A folder with opaque data in it")
    #expect(!items.contains { $0.url.lastPathComponent == "Docs" }, "A folder with registration data in it")
    // A listed placeholder later filled with activation data is refused before acting.
    let presets = try #require(items.first { $0.url.lastPathComponent == "Presets" })
    #expect(check(home).check(presets) == nil)
    try plist(support + "Pro Synth/Presets/Settings.plist", ["Volume": 1, "ActivationCode": "XYZ"], in: root)
    #expect(check(home).check(presets) == .protected("Settings.plist"))
}

/// An installer record lsbom can't read: its plist, and a BOM that isn't one.
private func unreadableReceipt(_ id: String, in root: URL) throws {
    let receipts = root.appendingPathComponent("var/db/receipts")
    let info: [String: Any] = ["PackageIdentifier": id, "PackageVersion": "1.0", "InstallPrefixPath": "/"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: receipts.appendingPathComponent(id + ".plist"))
    try Data("not a bill of materials".utf8).write(to: receipts.appendingPathComponent(id + ".bom"))
}

@Test func aReceiptThatCantBeReadNeverCountsAsListingNothing() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, items) = scan(root, home)
    let presets = try #require(items.first { $0.url.lastPathComponent == "Presets" })
    #expect(check(home).check(presets) == nil)

    try unreadableReceipt("com.other.big.pkg", in: root)
    #expect(check(home).check(presets) == .receiptsUnread, "Before acting")
    let (_, again) = scan(root, home)
    #expect(!again.contains { $0.ruleID != PlugInUninstall.formatsRuleID }, "At the scan: no support item, only formats")
    #expect(again.contains { $0.ruleID == PlugInUninstall.formatsRuleID })
}

@Test func licenceDataInSmallTextFilesDatabasesLargeFilesAndAnyFolderNamedForItIsNeverMoved() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("Serial: 1234-5678-ABCD".utf8).write(to: { try! write(support + "Pro Synth/Notes/notes.txt", in: root); return root.appendingPathComponent(support + "Pro Synth/Notes/notes.txt") }())
    try write(support + "Pro Synth/Skins/Dark.png", in: root)
    try write(support + "Pro Synth/Skins/cache.db", in: root)
    try write(support + "Pro Synth/Docs/manual.json", in: root, bytes: 2_000_000)
    try plist(support + "Pro Synth/Presets/Info.plist", ["Volume": 1], in: root)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth"], in: root)
    let (_, items) = scan(root, home)

    #expect(!items.contains { ["Notes", "Skins", "Docs"].contains($0.url.lastPathComponent) }, "\(items.map(\.url.lastPathComponent))")
    let presets = try #require(items.first { $0.url.lastPathComponent == "Presets" })
    #expect(check(home).check(presets) == nil)
    try plist(support + "Pro Synth/Presets/Info.plist", ["Volume": 1, "Activation": "XYZ"], in: root)
    // The listed placeholder is filled with activation data after the scan.
    #expect(check(home).check(presets) == .protected("Info.plist"), "Before acting too")
}

@Test func aSupportItemWithRegistrationOrSerialAnywhereInItsPathIsNeverMoved() throws {
    let (root, home) = try fixture(in: "Registration Data")
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let (_, items) = scan(root, home)
    #expect(!items.contains { $0.ruleID != PlugInUninstall.formatsRuleID }, "Not at the scan")
}

@Test func vendorContentHoldingLicenceDataOrAnotherProductsFilesIsNeverOfferedOrMoved() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = "Library/Application Support/Maker Content"
    try write(folder + "/Sounds/Pad.wav", in: root)
    try write("Library/Application Support/Locked Content/Sounds/Pad.wav", in: root)
    try write("Library/Application Support/Locked Content/auth.lic", in: root)
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5), receipts: ReceiptListings.read(under: root))
    let synth = try product("Pro Synth", inventory)
    func content(_ name: String) -> MusicContentItem {
        MusicContentItem(name: name, vendors: ["Maker"], url: root.appendingPathComponent("Library/Application Support/" + name), kind: .installed,
                         state: .present(.unknown), owners: [synth], tie: .vendor)
    }
    func scanned() -> [Candidate] {
        PlugInUninstall.scan(inventory, apps: [], receipts: ReceiptListings.read(under: root), content: [content("Maker Content"), content("Locked Content")], systemRoot: root)
    }
    #expect(!scanned().contains { $0.url.lastPathComponent == "Locked Content" }, "Licence data in it, at the scan")
    let library = try #require(scanned().first { $0.url.lastPathComponent == "Maker Content" })
    #expect(check(home).check(library) == nil)

    // Before acting: opaque data appeared in it, or another product's receipt now lists a file in it.
    try write(folder + "/Sounds/state.db", in: root)
    #expect(check(home).check(library) == .unrecognised("state.db"))
    try FileManager.default.removeItem(at: root.appendingPathComponent(folder + "/Sounds/state.db"))
    try receipt("com.maker.prodelay.pkg", listing: [plugIns + "VST3/Pro Delay.vst3", support + "Pro Delay", folder + "/Sounds/Pad.wav"], in: root)
    #expect(check(home).check(library) == .changed)
}

@Test func onlyKnownSafeKindsAreOfferedAnythingElseStaysAndIsCounted() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("key=ABCD-1234".utf8).write(to: { try! write(support + "Pro Synth/Presets/engine.cfg", in: root); return root.appendingPathComponent(support + "Pro Synth/Presets/engine.cfg") }())
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth"], in: root)
    try write("Library/Application Support/Maker Content/Sounds/Pad.wav", in: root)
    try Data("<library><id>9F2C-11AA</id></library>".utf8).write(to: { try! write("Library/Application Support/Maker Content/Library.xml", in: root)
        return root.appendingPathComponent("Library/Application Support/Maker Content/Library.xml") }())
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5), receipts: ReceiptListings.read(under: root))
    let synth = try product("Pro Synth", inventory)
    let library = MusicContentItem(name: "Sounds", vendors: ["Maker"], url: root.appendingPathComponent("Library/Application Support/Maker Content"), kind: .installed,
                                   state: .present(.unknown), owners: [synth], tie: .vendor)
    let items = PlugInUninstall.scan(inventory, apps: [], receipts: ReceiptListings.read(under: root), content: [library], systemRoot: root)

    #expect(!items.contains { ["Presets", "engine.cfg", "Maker Content"].contains($0.url.lastPathComponent) }, "\(items.map(\.url.lastPathComponent))")
    let own = items.filter { $0.uninstall?.path == synth && $0.sharedBy.isEmpty }
    #expect(names(own.filter { $0.ruleID == PlugInUninstall.filesRuleID }) == ["Init.fxp"], "What it recognises next to it is still offered")
    #expect(AppUninstall.staying(chosen: own, offered: items).map(\.text).contains("Pro Synth: 1 part stays · Holds files CacheDrop doesn’t recognise"))
}

@Test func anUnreadableFolderAtAnyDepthRefusesTheItemAtTheScanAndBeforeActing() throws {
    let (root, home) = try fixture()
    let deep = root.appendingPathComponent(support + "Pro Synth/Presets/a/b/c/d/locked")
    defer { chmod(deep.path, 0o755); try? FileManager.default.removeItem(at: root) }
    try write(support + "Pro Synth/Presets/a/b/c/d/locked/Hidden.fxp", in: root)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth"], in: root)
    let (_, items) = scan(root, home)
    let presets = try #require(items.first { $0.url.lastPathComponent == "Presets" })
    #expect(check(home).check(presets) == nil)

    // A folder five levels down can no longer be read: what is in it is unknown.
    chmod(deep.path, 0o000)
    #expect(check(home).check(presets) != nil, "Before acting")
    #expect(!scan(root, home).items.contains { $0.url.lastPathComponent == "Presets" }, "At the scan")
}

@Test func anyReceiptNotTheProductsListingFilesInVendorContentIsASharer() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = "Library/Application Support/Maker Content"
    try write(folder + "/Sounds/Pad.wav", in: root)
    try write(folder + "/Sounds/Lead.wav", in: root)
    // The vendor's standalone app's pkg, which installs no plug-in, wrote a file into the content folder.
    try receipt("com.maker.hub.pkg", listing: [folder + "/Sounds/Pad.wav"], in: root)
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5), receipts: ReceiptListings.read(under: root))
    let synth = try product("Pro Synth", inventory)
    let library = MusicContentItem(name: "Sounds", vendors: ["Maker"], url: root.appendingPathComponent(folder), kind: .installed,
                                   state: .present(.unknown), owners: [synth], tie: .vendor)
    let items = PlugInUninstall.scan(inventory, apps: [], receipts: ReceiptListings.read(under: root), content: [library], systemRoot: root)
    let content = try #require(items.first { $0.url == library.url })

    #expect(content.sharedBy.contains("receipt:com.maker.hub.pkg"), "\(content.sharedBy)")
    #expect(check(home).check(content) == nil)
    // Another app's pkg, installed after the scan, lists a file in it: refused before acting.
    try receipt("com.other.app.pkg", listing: [folder + "/Sounds/Lead.wav"], in: root)
    #expect(check(home).check(content) == .changed)
}

@Test func aFolderOfOnlyKnownSafeKindsWithFindersIconAndDSStoreIsOffered() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = "Library/Application Support/Maker Content"
    for name in ["Sounds/Pad.wav", "Kits/Drums.nki", "Art/Cover.png", "Icon\r", ".DS_Store", "Sounds/.DS_Store"] { try write(folder + "/" + name, in: root) }
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5), receipts: ReceiptListings.read(under: root))
    let library = MusicContentItem(name: "Sounds", vendors: ["Maker"], url: root.appendingPathComponent(folder), kind: .installed,
                                   state: .present(.unknown), owners: [try product("Pro Synth", inventory)], tie: .vendor)
    let items = PlugInUninstall.scan(inventory, apps: [], receipts: ReceiptListings.read(under: root), content: [library], systemRoot: root)
    let content = try #require(items.first { $0.url == library.url })
    #expect(check(home).check(content) == nil)
}

@Test func aPreferencesPlistAlwaysStaysWhateverItsKeys() throws {
    let (root, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let prefs = "Library/Preferences/com.maker.prosynth.plist"
    try plist(prefs, ["UnlockCode": "7Q2-ZZ9", "Theme": "Dark"], in: root)
    try receipt("com.maker.prosynth.pkg", listing: [plugIns + "Components/Pro Synth.component", plugIns + "VST3/Pro Synth.vst3", support + "Pro Synth", prefs], in: root)
    let (_, items) = scan(root, home)
    #expect(!items.contains { $0.url.lastPathComponent == "com.maker.prosynth.plist" })
    #expect(PlugInUninstall.fileRefusal(root.appendingPathComponent(prefs).path) == .unrecognised("com.maker.prosynth.plist"), "Nor moved")
}

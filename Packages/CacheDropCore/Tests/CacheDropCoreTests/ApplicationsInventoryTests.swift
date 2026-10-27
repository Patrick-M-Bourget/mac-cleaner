import Foundation
import Testing
@testable import CacheDropCore

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ApplicationsInventoryTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
private func setMode(_ url: URL, _ mode: Int) throws { try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }

/// #268: an item can go to the Trash without a password when its folder is writable and, for a folder, it is writable too.
@Test func anItemIsRemovableOnlyWhenItsFolderAndAFolderItselfAreWritable() throws {
    let root = try temporaryFolder()
    defer { try? setMode(root, 0o755); try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Synth.app"), file = root.appendingPathComponent("license.txt")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    try Data([1]).write(to: file)
    #expect(Removability.canMoveToTrash(app))

    try setMode(file, 0o444)
    #expect(Removability.canMoveToTrash(file), "A read-only file in a writable folder can still be moved")
    try setMode(app, 0o555)
    #expect(!Removability.canMoveToTrash(app), "A read-only folder can't")
    try setMode(app, 0o755)
    try setMode(root, 0o555)
    #expect(!Removability.canMoveToTrash(app), "Nothing in a read-only folder can")
    #expect(!Removability.canMoveToTrash(root.appendingPathComponent("missing.app")))
}

/// #271: in a writable folder with the sticky bit (like /Library/Application Support's shared folders), only the item's
/// owner or the folder's may move it. A test can't make another user's file, so it asks as another user instead.
@Test func aStickyFolderLetsOnlyTheOwnerMoveAnItem() throws {
    let root = try temporaryFolder()
    defer { try? setMode(root, 0o755); try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("shared.plist")
    try Data([1]).write(to: file)
    let stranger = getuid() + 1_000
    #expect(Removability.canMoveToTrash(file, asUser: stranger), "Without the sticky bit, a writable folder is enough")
    try setMode(root, 0o1777)
    #expect(Removability.canMoveToTrash(file), "Its owner still can")
    #expect(!Removability.canMoveToTrash(file, asUser: stranger), "Anyone else can't, though the folder is writable")
}

/// An app bundle with an Info.plist and `bytes` of executable.
private func makeApp(_ url: URL, id: String, bytes: Int, copyright: String? = nil) throws -> InstalledApp {
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": id]
    if let copyright { info["NSHumanReadableCopyright"] = copyright }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
    try Data(repeating: 1, count: bytes).write(to: url.appendingPathComponent("Contents/MacOS/main"))
    return InstalledApp(name: url.deletingPathExtension().lastPathComponent, bundleID: id, path: url.path)
}

/// Decision 51: every app in an Applications folder, largest first, except Apple's, system apps and CacheDrop.
@Test func appsListsTheApplicationsFoldersAppsLargestFirstWithoutApplesOrCacheDrop() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let apps = root.appendingPathComponent("Applications")
    let big = try makeApp(apps.appendingPathComponent("Big Synth.app"), id: "com.maker.big", bytes: 400_000, copyright: "© 2024 Maker Audio Inc. All rights reserved.")
    let small = try makeApp(apps.appendingPathComponent("Tools/Small.app"), id: "com.other.small", bytes: 20_000)
    let installed = [small, big, big,
                     try makeApp(apps.appendingPathComponent("Notes.app"), id: "com.apple.Notes", bytes: 1_000),
                     try makeApp(apps.appendingPathComponent("CacheDrop.app"), id: "com.patrickbourget.CacheDrop", bytes: 1_000),
                     try makeApp(apps.appendingPathComponent("Big Synth.app/Contents/Helpers/Helper.app"), id: "com.maker.helper", bytes: 1_000),
                     try makeApp(root.appendingPathComponent("Elsewhere/Loose.app"), id: "com.other.loose", bytes: 1_000),
                     InstalledApp(name: "Gone", bundleID: "com.other.gone", path: apps.appendingPathComponent("Gone.app").path),
                     InstalledApp(name: "Chess", bundleID: "com.other.chess", path: "/System/Applications/Chess.app")]

    let listed = ApplicationsInventory.apps(installed, excluding: "com.patrickbourget.CacheDrop")
    #expect(listed.map(\.name) == ["Big Synth", "Small"])
    #expect(listed.first?.maker == "Maker Audio Inc")
    #expect(listed.map(\.bundleID) == ["com.maker.big", "com.other.small"])
    #expect(listed.first?.parts.map(\.url.lastPathComponent) == ["Big Synth.app"])
    #expect(listed.allSatisfy { !$0.needsPassword && $0.volume == nil })
}

@Test func anEntryOnAnotherVolumeNamesItAndOneNothingCanMoveNeedsAPassword() {
    #expect(ApplicationsInventory.volume(of: URL(fileURLWithPath: "/Volumes/Studio SSD/Applications/Big.app")) == "Studio SSD")
    #expect(ApplicationsInventory.volume(of: URL(fileURLWithPath: "/Applications/Big.app")) == nil)
    let locked = InventoryEntry.Part(name: "VST3", url: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/A.vst3"), size: .measured(1), removable: false)
    let open = InventoryEntry.Part(name: "AU", url: URL(fileURLWithPath: "/Users/me/Library/Audio/Plug-Ins/Components/A.component"), size: .measured(2), removable: true)
    #expect(InventoryEntry(id: "a", name: "A", maker: nil, volume: nil, parts: [locked]).needsPassword)
    #expect(!InventoryEntry(id: "a", name: "A", maker: nil, volume: nil, parts: [locked, open]).needsPassword, "A partly removable product offers what it can")
    #expect(InventoryEntry(id: "a", name: "A", maker: nil, volume: nil, parts: [locked, open]).size == .measured(3))
}

private func plugIn(_ url: URL, _ format: PlugInFormat, id: String, maker: String? = "Maker", bytes: Int64) -> PlugInFile {
    PlugInFile(url: url, format: format, bundleID: id, name: url.deletingPathExtension().lastPathComponent, maker: maker, version: nil, architectures: [],
               size: .measured(bytes))
}

/// Decision 51: one row per plug-in product with its formats as items, largest first, never Apple's.
@Test func plugInsListOneEntryPerProductWithItsFormatsAndNeverApples() throws {
    let root = try temporaryFolder()
    defer { try? setMode(root.appendingPathComponent("VST3"), 0o755); try? FileManager.default.removeItem(at: root) }
    for folder in ["Components", "VST3"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true) }
    let au = root.appendingPathComponent("Components/Pro Synth.component"), vst3 = root.appendingPathComponent("VST3/Pro Synth.vst3")
    let locked = root.appendingPathComponent("VST3/Locked.vst3")
    for url in [au, vst3, locked] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    try setMode(root.appendingPathComponent("VST3"), 0o555)
    let inventory = PlugInInventory(products: PlugInInventory.group([
        plugIn(au, .au, id: "com.maker.prosynth.au", bytes: 300), plugIn(vst3, .vst3, id: "com.maker.prosynth.vst3", bytes: 200),
        plugIn(locked, .vst3, id: "com.vendor.locked", maker: "Vendor", bytes: 100),
        plugIn(root.appendingPathComponent("Components/AUDelay.component"), .au, id: "com.apple.audio.units.Delay", maker: "Apple", bytes: 900),
    ], receipts: [:]))

    let listed = ApplicationsInventory.plugIns(inventory)
    #expect(listed.map(\.name) == ["Pro Synth", "Locked"])
    #expect(listed.first?.parts.map(\.name) == ["AU", "VST3"])
    #expect(listed.first?.size == .measured(500))
    #expect(listed.map(\.bundleID) == ["com.maker.prosynth.au", "com.vendor.locked"])
    #expect(listed.map(\.needsPassword) == [false, true], "Pro Synth's AU can still go; Locked has nothing that can")
}

/// Decision 41: a product's vendor, and the vendor's own tool, are known by bundle ID, never by name ("Waves" isn't
/// "Wavesfactory", and an app merely named "Native Access" isn't Native Instruments' tool).
@Test func aVendorsOwnToolIsFoundAmongTheAppsByBundleID() {
    func entry(_ name: String, _ bundleID: String?) -> InventoryEntry { InventoryEntry(id: name, name: name, maker: nil, volume: nil, parts: [], bundleID: bundleID) }
    let nativeAccess = entry("Native Access", "com.native-instruments.nativeaccess2")
    let apps = [nativeAccess, entry("Big Synth", "com.bigsynth.app"), entry("UA Connect", "com.example.fake-connect")]
    #expect(ApplicationsInventory.vendorTool(for: entry("Kontakt 8", "com.native-instruments.kontakt-8.component"), among: apps) == nativeAccess)
    #expect(ApplicationsInventory.vendorTool(for: entry("Kontakt 8", "com.Native-Instruments.Kontakt"), among: apps) == nativeAccess)
    #expect(ApplicationsInventory.vendorTool(for: entry("Pulse", "com.wavesfactory.pulse"), among: apps) == nil, "Wavesfactory isn't Waves")
    #expect(ApplicationsInventory.vendorTool(for: entry("Console", "com.uaudio.console"), among: apps) == nil, "That UA Connect isn't Universal Audio's")
    #expect(ApplicationsInventory.vendorTool(for: entry("Native Access", "com.native-instruments.nativeaccess2"), among: apps) == nil, "The tool needs no tool")
    #expect(ApplicationsInventory.vendorTool(for: entry("Unknown", nil), among: apps) == nil)
}

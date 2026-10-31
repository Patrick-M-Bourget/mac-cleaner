import Foundation
import Testing
@testable import CacheDropCore

// #318: installer receipts are read once per scan and handed to leftovers, app uninstall and plug-ins. Every test builds a
// disposable fixture system root; `lsbom` is stood in by a closure, so nothing in this Mac's `/var/db/receipts` is read.

private struct NoApps: AppPresence {
    func installedApps() -> [InstalledApp]? { [] }
    func isRegistered(bundleID: String) -> Bool { false }
}

/// A fixture root with three non-Apple receipts (one with a relative install prefix, one whose BOM can't be read) and
/// Apple's, each a plist and a placeholder BOM; `listings` is what `lsbom -s` prints for each BOM, by receipt name.
private func fixture() throws -> (root: URL, home: URL, listings: [String: String]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropReceipts-\(UUID())").resolvingSymlinksInPath()
    let home = root.appendingPathComponent("Users/me"), receipts = root.appendingPathComponent("var/db/receipts")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
    for (name, prefix) in [("com.maker.synth.pkg", "/"), ("com.maker.fx.pkg", "Library"), ("com.maker.broken.pkg", "/"), ("com.apple.pkg.Core", "/")] {
        let info: [String: Any] = ["PackageIdentifier": name, "PackageVersion": "1.0", "InstallPrefixPath": prefix]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: receipts.appendingPathComponent(name + ".plist"))
        try Data().write(to: receipts.appendingPathComponent(name + ".bom"))
    }
    return (root, home, [
        "com.maker.synth.pkg": ".\n./Applications\n./Applications/Synth.app\n./Applications/Synth.app/Contents\n./Users/me/Library/Application Support/Synth\n",
        "com.maker.fx.pkg": ".\n./Audio/Plug-Ins/VST3/FX.vst3\n",
        "com.maker.broken.pkg": "lsbom: Can't open BOM\n",
    ])
}

@Test func oneScanListsEachReceiptOnceAndHandsThatToLeftoversAppUninstallAndPlugIns() throws {
    let (root, home, listings) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    var listed: [String] = []

    let read = ReceiptListings.read(under: root) { bom in
        let name = bom.deletingPathExtension().lastPathComponent
        listed.append(name)
        return listings[name]
    }
    let receipts = ReadReceipts(read, home: home)
    let synth = InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: root.appendingPathComponent("Applications/Synth.app").path)
    _ = RemovedAppLeftovers.scan(home: home, apps: NoApps(), receipts: receipts)
    _ = AppUninstall.scan(synth, excluding: nil, home: home, apps: NoApps(), receipts: receipts, leftovers: [])
    let inventory = PlugInInventory.scan(home: home, systemRoot: root, receipts: read)
    _ = PlugInUninstall.scan(inventory, apps: [synth], receipts: read, systemRoot: root)

    // One `lsbom` per non-Apple receipt, for the whole scan.
    #expect(listed.sorted() == ["com.maker.broken.pkg", "com.maker.fx.pkg", "com.maker.synth.pkg"])
    #expect(read.unread.contains("com.maker.broken.pkg.plist"))
    // Leftovers and app uninstall see the apps and Library paths each receipt lists, relative install prefixes included.
    #expect(receipts.receipts() == [
        InstallerReceipt(id: "com.maker.fx.pkg", apps: [], paths: []),
        InstallerReceipt(id: "com.maker.synth.pkg", apps: [root.path + "/Applications/Synth.app"], paths: [home.path + "/Library/Application Support/Synth"]),
    ])
}

/// A missing record stays readable, including prefixes at the Library, format-folder and bundle levels (#329).
@Test(arguments: [
    ("Library", ".\n./Audio/Plug-Ins/VST3/FX.vst3/Contents/Info.plist\n"),
    ("Library/Audio/Plug-Ins/VST3", ".\n./FX.vst3/Contents/Info.plist\n"),
    ("Library/Audio/Plug-Ins/VST3/FX.vst3", ".\n./Contents/Info.plist\n"),
])
func aMissingRecordedFileDoesNotMakeARelativeReceiptUnread(example: (prefix: String, listing: String)) throws {
    let (root, home, listings) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("var/db/receipts/com.maker.fx.pkg.plist")
    let info: [String: Any] = ["PackageIdentifier": "com.maker.fx.pkg", "InstallPrefixPath": example.prefix]
    try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: file)
    let read = ReceiptListings.read(under: root) { bom in
        bom.deletingPathExtension().lastPathComponent == "com.maker.fx.pkg" ? example.listing : listings[bom.deletingPathExtension().lastPathComponent]
    }
    #expect(read.byReceipt["com.maker.fx.pkg"]?.contains(root.path + "/Library/Audio/Plug-Ins/VST3/FX.vst3/Contents/Info.plist") == true)
    #expect(read.unread == ["com.maker.broken.pkg.plist"])
    #expect(PlugInInventory.scan(home: home, systemRoot: root, receipts: read).products.isEmpty)
}

@Test(arguments: [".\n./../Users/me/Library/Preferences/Other.plist\n", ".\n./Audio/../../Other\n", ".\n.not-a-bom-path\n", ".\n.//Library/Other\n", ".\n./bad\0path\n"])
func anInvalidReceiptEntryKeepsTheWholeReceiptUnread(listing: String) throws {
    let (root, _, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let read = ReceiptListings.read(under: root) { _ in listing }
    #expect(read.byReceipt.isEmpty)
    #expect(Set(read.unread) == ["com.maker.synth.pkg.plist", "com.maker.fx.pkg.plist", "com.maker.broken.pkg.plist"])
}

@Test(arguments: ["Library/../Users/me", "../outside", "Library/bad\0prefix"])
func anInvalidInstallPrefixKeepsTheWholeReceiptUnread(prefix: String) throws {
    let (root, _, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("var/db/receipts/com.maker.fx.pkg.plist")
    let info: [String: Any] = ["PackageIdentifier": "com.maker.fx.pkg", "InstallPrefixPath": prefix]
    try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: file)
    let read = ReceiptListings.read(under: root) { _ in ".\n./Audio/Plug-Ins/VST3/FX.vst3\n" }
    #expect(read.byReceipt["com.maker.fx.pkg"] == nil)
    #expect(read.unread == ["com.maker.fx.pkg.plist"])
}

@Test func aReceiptDatabaseThatCannotBeListedIsUnknownNeverAnEmptySuccessfulRead() throws {
    let (root, _, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("var/db/receipts")
    try FileManager.default.removeItem(at: folder)
    // A file in place of the folder gives a deterministic enumeration failure, even under an elevated test runner.
    try Data().write(to: folder)
    let read = ReceiptListings.read(under: root)
    #expect(read.byReceipt.isEmpty)
    #expect(!read.unread.isEmpty)
}

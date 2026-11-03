import Foundation
import Testing
@testable import CacheDropCore

private func app(_ name: String, _ bundleID: String, at path: String? = nil) -> InventoryEntry {
    let url = URL(fileURLWithPath: path ?? "/Applications/\(name).app")
    return InventoryEntry(id: url.path, name: name, maker: nil, volume: nil,
                          parts: [.init(name: url.lastPathComponent, url: url, size: .measured(10), removable: true)], bundleID: bundleID)
}

/// Decision 151: DAWs, vendor managers and plug-ins' standalone apps leave Apps for Audio software, by bundle ID only (41).
@Test func audioAppsLeaveAppsByBundleIDOnlyNeverByName() {
    let synth = PlugInFile(url: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/Pro Synth.vst3"), format: .vst3, bundleID: "com.maker.prosynth.vst3",
                           name: "Pro Synth", maker: "Maker", version: nil, architectures: [], size: .measured(5))
    let inventory = PlugInInventory(products: PlugInInventory.group([synth], receipts: [:]))
    let apps = [
        app("Ableton Live 12 Suite", "com.ableton.live"),           // a plug-in host
        app("REAPER", "COM.COCKOS.REAPER"),                          // matched without regard to case
        app("Native Access", "com.native-instruments.nativeaccess2"), // a vendor's manager
        app("Pro Synth", "com.maker.prosynth.app"),                  // the product's own standalone app
        app("Ableton Notes", "com.example.notes"),                   // named like audio software, but not tied to it
        app("Slack", "com.tinyspeck.slackmacgap"),
    ]
    let split = AudioSoftware.split(apps, plugIns: inventory)
    #expect(split.apps.map(\.name) == ["Ableton Notes", "Slack"])
    #expect(split.audio.map(\.name) == ["Ableton Live 12 Suite", "REAPER", "Native Access", "Pro Synth"])
}

/// #704: a host listed from a primary source (Ardour's own build script) leaves Apps by its exact bundle ID; an app with its
/// name and executable but another bundle ID stays in Apps, and an Ardour version not listed stays too (never by name, 41).
@Test func newlyListedHostsAreRecognisedByTheirExactBundleIDOnly() {
    let apps = [
        app("Ardour9", "org.ardour.Ardour9"),
        app("Ardour8", "org.ardour.Ardour8"),
        app("Ardour", "com.example.ardour"),         // the same name, another maker's ID
        app("Ardour7", "org.ardour.Ardour7"),       // a version the list doesn't name
    ]
    let split = AudioSoftware.split(apps, plugIns: PlugInInventory(products: []))
    #expect(split.audio.map(\.name) == ["Ardour9", "Ardour8"])
    #expect(split.apps.map(\.name) == ["Ardour", "Ardour7"])
    #expect(PlugInUninstall.hosts.first { $0.name == "Ardour" }?.bundleIDs == ["org.ardour.Ardour8", "org.ardour.Ardour9"])
}

private func driver(_ relative: String, in root: URL, id: String, copyright: String? = nil, bytes: Int = 0) throws -> URL {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": id]
    if let copyright { info["NSHumanReadableCopyright"] = copyright }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
    try Data(count: bytes).write(to: url.appendingPathComponent("Contents/MacOS/code"))
    return url
}

/// Decision 151: audio and MIDI drivers, never Apple's; a root-owned one can't move without a password, a user-owned one can.
@Test func driversListAudioAndMIDIDriversWithMakerAndSayWhichNeedAPassword() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("AudioSoftwareTests-" + UUID().uuidString)
    let system = base.appendingPathComponent("root"), home = base.appendingPathComponent("home")
    let hal = system.appendingPathComponent("Library/Audio/Plug-Ins/HAL")
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hal.path); try? FileManager.default.removeItem(at: base) }
    try driver("Library/Audio/Plug-Ins/HAL/Interface.driver", in: system, id: "com.maker.interface.driver", copyright: "Copyright © 2025 Maker Audio. All rights reserved.", bytes: 9_000)
    try driver("Library/Audio/Plug-Ins/HAL/AppleThing.driver", in: system, id: "com.apple.audio.thing")
    try driver("Library/Audio/MIDI Drivers/Keys.plugin", in: system, id: "com.keys.midi", bytes: 4_000)
    try driver("Library/Audio/Plug-Ins/HAL/Loopback.driver", in: home, id: "com.loop.back", bytes: 1_000)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: hal.path)

    let drivers = AudioSoftware.drivers(home: home, systemRoot: system)
    #expect(drivers.map(\.name) == ["Interface", "Keys", "Loopback"], "Largest first, never Apple's")
    #expect(drivers.map(\.maker) == ["Maker Audio", nil, nil])
    #expect(drivers.map(\.needsPassword) == [true, false, false], "A driver in a folder only root can change stays")
    #expect(drivers.first?.bundleID == "com.maker.interface.driver")
}

private func product(_ name: String, maker: String?, bytes: Int64) -> InventoryEntry {
    let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/\(name).vst3")
    return InventoryEntry(id: url.path, name: name, maker: maker, volume: nil, parts: [.init(name: "VST3", url: url, size: .measured(bytes), removable: true)])
}

/// Decision 151: plug-ins grouped by maker, largest maker first (or by the sort's column), those with no maker last under Other makers.
@Test func plugInsGroupByMakerInTheSortsOrderWithOtherMakersLast() {
    let products = [product("Kontakt", maker: "Native Instruments", bytes: 900), product("Solo", maker: "Tiny Co", bytes: 950),
                    product("Massive", maker: "Native Instruments", bytes: 200), product("Loose", maker: nil, bytes: 5_000),
                    product("Arp", maker: "arturia", bytes: 300)]
    let bySize = AudioSoftware.byMaker(products, sort: ListSort(), bytes: { $0.size.sortBytes })
    #expect(bySize.map(\.maker) == ["Native Instruments", "Tiny Co", "arturia", nil], "Native Instruments' 1,100 beats Tiny Co's 950; Other makers last")
    #expect(bySize[0].products.map(\.name) == ["Kontakt", "Massive"], "Products keep the order they came in")
    let byName = AudioSoftware.byMaker(products, sort: ListSort(column: .name, ascending: true), bytes: { $0.size.sortBytes })
    #expect(byName.map(\.maker) == ["arturia", "Native Instruments", "Tiny Co", nil], "Names as Finder sorts them; Other makers still last")
}

private struct NoApps: AppPresence {
    func installedApps() -> [InstalledApp]? { [] }
    func isRegistered(bundleID: String) -> Bool { false }
}
private struct RunningNamed: RunningAppChecking {
    var names: Set<String> = []
    func isRunning(_ owner: RuleOwner) -> Bool? { names.contains(owner.name) }
}

/// #701: Reason 13's additional devices, one row each (Reason Studios Help 19526087405074); they go to the Trash one by one,
/// never while Reason or Reason Companion runs, and Companion installs them again.
@Test func reasonsOptionalDevicesAreListedOneByOneAndGoToTheTrashOnlyWithReasonClosed() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("AudioSoftwareTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = home.appendingPathComponent(AudioSoftware.optionalDevices)
    for (name, bytes) in [("Pangea", 3_000), ("Humana", 9_000)] {
        let file = folder.appendingPathComponent(name).appendingPathComponent("data.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: file)
    }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)

    let devices = AudioSoftware.optionalDevices(home: home)
    #expect(devices.map(\.name) == ["Humana", "Pangea"], "Largest first")
    #expect(devices.allSatisfy { $0.maker == "Reason Studios" })

    let items = AudioSoftware.uninstallItems(devices, hosts: AudioSoftware.reasonHosts)
    #expect(items.map(\.url.lastPathComponent) == ["Humana", "Pangea"])
    #expect(items.allSatisfy { $0.isUninstalled(with: $0.url.path) }, "Each is its own row's item")
    let check = { (running: Set<String>) in
        CandidateCheck(catalog: Catalog(rules: AppRuleFamily.uninstallRules), running: RunningNamed(names: running), inUse: FixtureNothingInUse(),
                       home: home, apps: NoApps())
    }
    #expect(check([]).check(items[0]) == nil, "Goes to the Trash with Reason closed")
    #expect(check(["Reason"]).check(items[0]) != nil, "Refused while Reason runs")
    #expect(check(["Reason Companion"]).check(items[0]) != nil, "Refused while Reason Companion runs")
}

/// Decision 151: a driver the user can move gets an item; one in a folder only an administrator can change gets none.
@Test func onlyDriversTheUserCanMoveBecomeItems() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("AudioSoftwareTests-" + UUID().uuidString)
    let system = base.appendingPathComponent("root"), home = base.appendingPathComponent("home")
    let hal = system.appendingPathComponent("Library/Audio/Plug-Ins/HAL")
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hal.path); try? FileManager.default.removeItem(at: base) }
    try driver("Library/Audio/Plug-Ins/HAL/Interface.driver", in: system, id: "com.maker.interface.driver", bytes: 9_000)
    let loop = try driver("Library/Audio/Plug-Ins/HAL/Loopback.driver", in: home, id: "com.loop.back", bytes: 1_000)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: hal.path)
    let items = AudioSoftware.uninstallItems(AudioSoftware.drivers(home: home, systemRoot: system), hosts: [])
    #expect(items.map(\.url.path) == [loop.path])
}

/// Decision 151: Sounds and samples lists the vendor libraries MusicContent knows, Splice's sounds and the shop Rack Extensions,
/// read-only, largest first, each with who it is from.
@Test func soundsAndSamplesListVendorLibrariesSpliceAndRackExtensions() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("AudioSoftwareTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    for (path, bytes) in [("Music/Ableton/Factory Packs/Core Library/a.wav", 40_000), ("Splice/sounds/kick.wav", 4_000),
                          (AudioSoftware.rackExtensions + "/SomeDevice/data.bin", 200_000)] {
        let file = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: file)
    }
    // The fixture home stands in for the system root, so `/Library/...` locations are read there too.
    let sounds = AudioSoftware.sounds(home: home, systemRoot: home)
    #expect(sounds.map(\.name) == ["Rack Extensions", "Packs", "Splice sounds"])
    #expect(sounds.map(\.maker) == ["Reason Studios", "Ableton", "Splice"])
    // The user's own content says so.
    let preset = home.appendingPathComponent("Music/Ableton/User Library/Presets/a.adv")
    try FileManager.default.createDirectory(at: preset.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: 1_000).write(to: preset)
    #expect(AudioSoftware.sounds(home: home, systemRoot: home).first { $0.name == "User Library" }?.maker == "Ableton · Yours")
}

/// #714: a sound row offers its vendor's manager (`VendorTool`) when that app is installed; none when it isn't, and none for a
/// vendor with no known manager (Reason Studios, Splice).
@Test func soundsOfferTheirVendorsManagerOnlyWhenItIsInstalled() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("AudioSoftwareTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    for path in ["Applications/Waves/Data/Instrument Data/Waves Sample Libraries/a.wav", "Library/Arturia/Presets/a.preset",
                 "Splice/sounds/kick.wav", AudioSoftware.rackExtensions + "/SomeDevice/data.bin"] {
        let file = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_000).write(to: file)
    }
    let sounds = AudioSoftware.sounds(home: home, systemRoot: home)
    let apps = [app("Waves Central", "com.wavesaudio.wavescentral"), app("Slack", "com.tinyspeck.slackmacgap")]
    let managers: [String: String?] = Dictionary(uniqueKeysWithValues: sounds.map { ($0.name, AudioSoftware.manager(of: $0, among: apps)?.name) })
    #expect(managers == ["Sample libraries": "Waves Central", "Resources": nil, "Splice sounds": nil, "Rack Extensions": nil])
    #expect(sounds.allSatisfy { AudioSoftware.manager(of: $0, among: []) == nil })
}

/// #714: the user's own content ("· Yours") never offers a manager, even from a vendor whose manager is installed. No vendor
/// CacheDrop knows has both today, so the row is built from a synthetic item.
@Test func yourSoundsNeverOfferAManager() {
    let item = { (kind: MusicContentItem.Kind) in
        MusicContentItem(name: "Presets", vendors: ["Waves"], url: URL(fileURLWithPath: "/Users/Shared/Waves Presets"), kind: kind,
                         state: .present(.measured(1_000)), owners: [], tie: .vendor)
    }
    let apps = [app("Waves Central", "com.wavesaudio.wavescentral")]
    #expect(AudioSoftware.manager(of: AudioSoftware.sound(item(.installed)), among: apps)?.name == "Waves Central")
    #expect(AudioSoftware.sound(item(.yours)).maker == "Waves · Yours")
    #expect(AudioSoftware.manager(of: AudioSoftware.sound(item(.yours)), among: apps) == nil)
}

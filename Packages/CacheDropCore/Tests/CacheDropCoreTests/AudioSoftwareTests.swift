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

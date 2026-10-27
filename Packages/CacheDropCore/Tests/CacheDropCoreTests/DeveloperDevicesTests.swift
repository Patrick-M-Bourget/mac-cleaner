import Foundation
import Testing
@testable import CacheDropCore

/// Simulators and Android emulators (#134). Every test uses a temp fixture home, a stand-in simctl that prints
/// canned JSON, and a fixture `.android`; the real simctl and the real `~/.android` are never touched.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropDevices-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ home: URL, _ relative: String, bytes: Int = 100, text: String? = nil) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let text { try text.write(to: file, atomically: true, encoding: .utf8) } else { try Data(repeating: 1, count: bytes).write(to: file) }
}
private let devicesFolder = "Library/Developer/CoreSimulator/Devices"
private let shutdownUDID = "11111111-1111-4111-8111-111111111111"
private let bootedUDID = "22222222-2222-4222-8222-222222222222"
private let unavailableUDID = "33333333-3333-4333-8333-333333333333"
private let usedRuntime = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
private let unusedRuntime = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
private let bundledRuntime = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"

/// `simctl list devices -j` as Xcode 16 prints it: one shutdown and one booted iOS 18 device, one unavailable iOS 16 device.
private let devicesJSON = """
{
  "devices" : {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-0" : [
      { "lastBootedAt" : "2026-09-01T10:00:00Z", "dataPath" : "/x/\(shutdownUDID)/data", "dataPathSize" : 4096, "udid" : "\(shutdownUDID)",
        "isAvailable" : true, "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-16", "state" : "Shutdown", "name" : "iPhone 16" },
      { "udid" : "\(bootedUDID)", "isAvailable" : true, "state" : "Booted", "name" : "iPad Air" }
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-16-4" : [
      { "udid" : "\(unavailableUDID)", "isAvailable" : false, "availabilityError" : "runtime profile not found", "state" : "Shutdown", "name" : "iPhone 14" }
    ],
    "com.apple.CoreSimulator.SimRuntime.watchOS-11-0" : []
  }
}
"""
/// `simctl runtime list -j`: iOS 18 is used by an available device, watchOS 11 by none, and iOS 17 came with Xcode (not deletable).
private let runtimesJSON = """
{
  "\(usedRuntime)" : { "build" : "22A3351", "deletable" : true, "identifier" : "\(usedRuntime)", "kind" : "Disk Image", "lastUsedAt" : "2026-09-01T10:00:00Z",
    "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-18-0", "sizeBytes" : 8000000000, "state" : "Ready", "version" : "18.0" },
  "\(unusedRuntime)" : { "build" : "22R349", "deletable" : true, "identifier" : "\(unusedRuntime)", "kind" : "Disk Image", "lastUsedAt" : "2026-03-02T08:30:00.123Z",
    "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.watchOS-11-0", "sizeBytes" : 4500000000, "state" : "Ready", "version" : "11.0" },
  "\(bundledRuntime)" : { "build" : "21A328", "deletable" : false, "identifier" : "\(bundledRuntime)", "kind" : "Bundled with Xcode",
    "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-17-0", "sizeBytes" : 6000000000, "state" : "Ready", "version" : "17.0" }
}
"""

/// A stand-in simctl inside the fixture that lists `devices` and `runtimes`, and logs every other call to `<home>/simctl.log`.
private func standInSimctl(_ home: URL, devices: String = devicesJSON, runtimes: String = runtimesJSON, exitStatus: Int = 0) throws -> URL {
    try write(home, "fixture/devices.json", text: devices)
    try write(home, "fixture/runtimes.json", text: runtimes)
    let tool = home.appendingPathComponent("tools/simctl")
    let script = """
    #!/bin/sh
    case "$*" in
    "list devices -j") cat '\(home.path)/fixture/devices.json' ;;
    "runtime list -j") cat '\(home.path)/fixture/runtimes.json' ;;
    *) echo "$*" >> '\(home.path)/simctl.log'; exit \(exitStatus) ;;
    esac
    """
    try write(home, "tools/simctl", text: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    return tool
}
private func simctlLog(_ home: URL) -> String { (try? String(contentsOf: home.appendingPathComponent("simctl.log"), encoding: .utf8)) ?? "" }
private func makeDevice(_ home: URL, _ udid: String, bytes: Int = 3000) throws { try write(home, devicesFolder + "/\(udid)/data/entry", bytes: bytes) }

private struct Running: RunningAppChecking {
    let names: Set<String>
    func isRunning(_ owner: RuleOwner) -> Bool? {
        names.contains { name in owner.bundleIDs.contains(name) || owner.executables.contains { fnmatch($0, name, 0) == 0 } }
    }
}
private let nothingRunning = Running(names: [])

@Test func simulatorDevicesThatArentRunningAreOfferedOneByOneWithSizeAndLastUse() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for udid in [shutdownUDID, bootedUDID, unavailableUDID] { try makeDevice(home, udid) }
    let simctl = try standInSimctl(home)
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).filter { $0.ruleID == "simulator-devices" }
    // The booted one is in use and the unavailable one belongs to "Unavailable simulators".
    let device = try #require(found.first)
    #expect(found.count == 1)
    #expect(device.url == home.appendingPathComponent(devicesFolder + "/" + shutdownUDID))
    #expect(device.itemName == "iPhone 16 (iOS 18.0)")
    #expect(device.toolArgument == shutdownUDID)
    #expect(device.action == .tool)
    #expect(device.logicalBytes == 3000)
    #expect(device.lastUsed == ISO8601DateFormatter().date(from: "2026-09-01T10:00:00Z"))
    #expect(catalog.rule("simulator-devices")?.tool?.commandLine(for: device.toolArgument) == "simctl delete \(shutdownUDID)")
    // Without simctl nothing is offered.
    #expect(!catalog.discover(fixture: home).contains { $0.ruleID == "simulator-devices" })
}

@Test func onlyDeletableRuntimesNoAvailableSimulatorUsesAreOfferedEachOnItsOwn() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let simctl = try standInSimctl(home)
    let found = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: onlyTool("simctl", simctl)).filter { $0.ruleID == "simulator-runtimes" }
    // iOS 18 runs available devices, iOS 17 came with Xcode; only watchOS 11 is offered, with simctl's size and last use.
    let runtime = try #require(found.first)
    #expect(found.count == 1)
    #expect(runtime.itemName == "watchOS 11.0 (22R349)")
    #expect(runtime.toolArgument == unusedRuntime)
    #expect(runtime.logicalBytes == 4_500_000_000)
    #expect(runtime.lastUsed == SimulatorInventory.date("2026-03-02T08:30:00.123Z"))
    #expect(runtime.lastUsed != nil)
}

@Test func twoRuntimesOnTheSameAnchorAreTwoItemsAndBothCount() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    // No device is available, so both deletable runtimes are unused.
    let simctl = try standInSimctl(home, devices: #"{ "devices" : {} }"#)
    let found = Catalog(rules: fixtureRules).discover(fixture: home, locateTool: onlyTool("simctl", simctl)).filter { $0.ruleID == "simulator-runtimes" }
    #expect(Set(found.compactMap(\.toolArgument)) == [usedRuntime, unusedRuntime])
    #expect(Set(found.map(\.id)).count == 2)
}

@Test func simulatorsAreRemovedOnlyThroughSimctlAndRefusedWhileSimulatorOrXcodeRuns() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let simctl = try standInSimctl(home)
    let catalog = Catalog(rules: fixtureRules)
    let items = catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).filter { $0.ruleID.hasPrefix("simulator-") }.sorted { $0.ruleID < $1.ruleID }
    #expect(items.count == 2)
    #expect(items.allSatisfy { $0.action == .tool && $0.toolURL == simctl })
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))

    for app in ["com.apple.iphonesimulator", "com.apple.dt.Xcode"] {
        let check = CandidateCheck(catalog: catalog, running: Running(names: [app]))
        let refused = await CleanupExecutor(journal: journal, check: check, trash: TrashNeverUsed()).execute(CatalogApproval(candidates: items, previewOnly: false))
        #expect(refused.records.allSatisfy { $0.state == .skipped && $0.message == "Simulator or Xcode is running. Quit it, then scan again." })
    }
    #expect(simctlLog(home).isEmpty)

    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: nothingRunning), trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: items, previewOnly: false))
    #expect(result.records.map(\.state) == [.succeeded, .succeeded])
    #expect(result.records.map(\.message) == ["Ran simctl delete \(shutdownUDID)", "Ran simctl runtime delete \(unusedRuntime)"])
    #expect(result.records.map(\.itemName) == ["iPhone 16 (iOS 18.0)", "watchOS 11.0 (22R349)"])
    #expect(simctlLog(home) == "delete \(shutdownUDID)\nruntime delete \(unusedRuntime)\n")
    // simctl decides what goes; CacheDrop never deletes the device folder itself.
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(devicesFolder + "/" + shutdownUDID).path))
}

@Test func simctlArgumentsAreOnlyIdentifiersFromItsOwnList() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let flagged = devicesJSON.replacingOccurrences(of: "\"udid\" : \"\(shutdownUDID)\"", with: "\"udid\" : \"--all\"")
    try write(home, devicesFolder + "/--all/data/entry")
    let runtimes = runtimesJSON.replacingOccurrences(of: "\"identifier\" : \"\(unusedRuntime)\"", with: "\"identifier\" : \"all\"")
    let simctl = try standInSimctl(home, devices: flagged, runtimes: runtimes)
    #expect(!Catalog(rules: fixtureRules).discover(fixture: home, locateTool: onlyTool("simctl", simctl)).contains { $0.ruleID.hasPrefix("simulator-") })
    #expect(!SimulatorInventory.isIdentifier("-\(shutdownUDID.dropFirst())"))
    #expect(SimulatorInventory.isIdentifier(shutdownUDID))
}

@Test func anUnreadableSimulatorListOffersNothingAndSaysSo() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let simctl = try standInSimctl(home, devices: "not json")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home, locateTool: onlyTool("simctl", simctl))
    #expect(!discovery.candidates.contains { $0.ruleID.hasPrefix("simulator-") && $0.ruleID != "xcode-simulators" })
    #expect(discovery.notes.map(\.text) == [SimulatorInventory.notice])
}

/// #212, Decision 45: simctl failing when stopped work is measured again leaves both simulator rules unmeasured, never gone.
@Test func bothSimulatorRulesAreUnmeasuredWhenSimctlFailsLater() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let catalog = Catalog(rules: fixtureRules)
    let stopped = catalog.discover(fixture: home, locateTool: onlyTool("simctl", try standInSimctl(home))).filter { $0.ruleID.hasPrefix("simulator-") }
    #expect(Set(stopped.map(\.ruleID)) == ["simulator-devices", "simulator-runtimes"])
    let failing = try standInSimctl(home, devices: "not json")
    let findings = catalog.measuredAgain(stopped, in: catalog.only(stopped).discovery(fixture: home, locateTool: onlyTool("simctl", failing)))
    #expect(findings.count == stopped.count)
    #expect(findings.values.allSatisfy { $0 == .unmeasured })
}

@Test func theCheckRefusesAPerItemToolArgumentThatLooksLikeAnOption() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let simctl = try standInSimctl(home)
    let catalog = Catalog(rules: fixtureRules)
    var device = try #require(catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).first { $0.ruleID == "simulator-devices" })
    #expect(CandidateCheck(catalog: catalog, running: nothingRunning).check(device) == nil)
    device.toolItem = "--set"
    #expect(CandidateCheck(catalog: catalog, running: nothingRunning).check(device) == .changed)
}

/// The stand-in simctl's device list with one more device, on `runtime`.
private func devicesJSON(adding udid: String, on runtime: String, available: Bool) -> String {
    devicesJSON.replacingOccurrences(of: "\"\(runtime)\" : []", with: """
    "\(runtime)" : [ { "udid" : "\(udid)", "isAvailable" : \(available), "state" : "Shutdown", "name" : "Apple Watch" } ]
    """)
}
private let watchRuntime = "com.apple.CoreSimulator.SimRuntime.watchOS-11-0"
private let watchUDID = "44444444-4444-4444-8444-444444444444"

@Test func aSimulatorBootedOrRemovedAfterTheScanIsRefusedJustBeforeActing() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let simctl = try standInSimctl(home)
    let catalog = Catalog(rules: fixtureRules)
    let device = try #require(catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).first { $0.ruleID == "simulator-devices" })
    let check = CandidateCheck(catalog: catalog, running: nothingRunning)
    #expect(check.check(device) == nil)
    try write(home, "fixture/devices.json", text: devicesJSON.replacingOccurrences(of: #""state" : "Shutdown", "name" : "iPhone 16""#, with: #""state" : "Booted", "name" : "iPhone 16""#))
    #expect(check.check(device) == .ownerRunning("This simulator"))
    try write(home, "fixture/devices.json", text: #"{ "devices" : {} }"#)
    #expect(check.check(device) == .missing)
    try write(home, "fixture/devices.json", text: "not json")
    #expect(check.check(device) == .inUseUnknown("a simulator"))
    #expect(simctlLog(home).isEmpty)
}

@Test func aRuntimeADeviceStartedUsingAfterTheScanIsRefusedJustBeforeActing() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let simctl = try standInSimctl(home)
    let catalog = Catalog(rules: fixtureRules)
    let runtime = try #require(catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).first { $0.ruleID == "simulator-runtimes" })
    let check = CandidateCheck(catalog: catalog, running: nothingRunning)
    #expect(check.check(runtime) == nil)
    try write(home, "fixture/devices.json", text: devicesJSON(adding: watchUDID, on: watchRuntime, available: true))
    #expect(check.check(runtime) == .inUse("A simulator"))
    #expect(check.check(runtime)?.reason == "A simulator is using it. It is kept.")
    try write(home, "fixture/devices.json", text: devicesJSON)
    try write(home, "fixture/runtimes.json", text: runtimesJSON.replacingOccurrences(of: #""identifier" : "\#(unusedRuntime)""#, with: #""identifier" : "\#(bundledRuntime)x""#))
    #expect(check.check(runtime) == .missing)
}

@Test func aRuntimeAnUnavailableDeviceUsesCountsAsUsed() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeDevice(home, shutdownUDID)
    let catalog = Catalog(rules: fixtureRules)
    // Before the scan: never offered.
    let unavailable = devicesJSON(adding: watchUDID, on: watchRuntime, available: false)
    var simctl = try standInSimctl(home, devices: unavailable)
    #expect(!catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).contains { $0.ruleID == "simulator-runtimes" })
    // After the scan: refused.
    simctl = try standInSimctl(home)
    let runtime = try #require(catalog.discover(fixture: home, locateTool: onlyTool("simctl", simctl)).first { $0.ruleID == "simulator-runtimes" })
    try write(home, "fixture/devices.json", text: unavailable)
    #expect(CandidateCheck(catalog: catalog, running: nothingRunning).check(runtime) == .inUse("A simulator"))
}

// MARK: Android

private let avdHome = ".android/avd"
private let images = "Library/Android/sdk/system-images"
/// An AVD folder with its config and the `.ini` beside it that Android Studio reads.
private func makeAVD(_ home: URL, _ name: String, image: String?, bytes: Int = 2000) throws {
    try write(home, avdHome + "/\(name).avd/userdata-qemu.img", bytes: bytes)
    let config = ["avd.ini.displayname=\(name.replacingOccurrences(of: "_", with: " "))", "hw.lcd.density=420"] + (image.map { ["image.sysdir.1=\($0)"] } ?? [])
    try write(home, avdHome + "/\(name).avd/config.ini", text: config.joined(separator: "\n") + "\n")
    try write(home, avdHome + "/\(name).ini", text: "avd.ini.encoding=UTF-8\npath=\(home.path)/\(avdHome)/\(name).avd\npath.rel=avd/\(name).avd\ntarget=android-34\n")
}
private func makeImage(_ home: URL, _ relative: String, bytes: Int = 5000) throws { try write(home, images + "/\(relative)/system.img", bytes: bytes) }

/// Records what would go to the Trash and moves it into a fixture folder, never the real Trash.
private final class FixtureTrash: TrashMoving, @unchecked Sendable {
    let folder: URL
    private(set) var moved: [String] = []
    init(_ folder: URL) { self.folder = folder }
    func moveToTrash(_ url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        moved.append(url.lastPathComponent)
        return target
    }
}

@Test func androidVirtualDevicesAreOfferedOneByOneWithSizeAndLastUse() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeAVD(home, "Pixel_8_API_34", image: "system-images/android-34/google_apis/arm64-v8a/", bytes: 2000)
    try makeAVD(home, "Tablet", image: "system-images/android-33/default/arm64-v8a/", bytes: 700)
    try write(home, avdHome + "/stray.txt")
    let found = Catalog(rules: fixtureRules).discover(fixture: home).filter { $0.ruleID == "android-virtual-devices" }.sorted { $0.url.path < $1.url.path }
    #expect(found.map(\.url.lastPathComponent) == ["Pixel_8_API_34.avd", "Tablet.avd"])
    #expect(found.map(\.itemName) == ["Pixel 8 API 34", "Tablet"])
    #expect(found.allSatisfy { $0.action == .trash && $0.isDirectory && $0.lastUsed != nil })
    #expect(found.first?.logicalBytes ?? 0 >= 2000)
}

@Test func onlySystemImagesNoVirtualDeviceUsesAreOffered() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeAVD(home, "Pixel", image: "system-images/android-34/google_apis/arm64-v8a/")
    try makeAVD(home, "Absolute", image: home.path + "/" + images + "/android-33/default/arm64-v8a")
    for image in ["android-34/google_apis/arm64-v8a", "android-34/google_apis_playstore/arm64-v8a", "android-33/default/arm64-v8a", "android-30/default/x86_64"] {
        try makeImage(home, image)
    }
    let found = Catalog(rules: fixtureRules).discover(fixture: home).filter { $0.ruleID == "android-system-images" }
    #expect(Set(found.compactMap(\.itemName)) == ["Android 34 · google_apis_playstore · arm64-v8a", "Android 30 · default · x86_64"])
    #expect(found.allSatisfy { $0.action == .delete && $0.logicalBytes == 5000 && $0.lastUsed != nil })
}

@Test func noSystemImageIsOfferedWhenAVirtualDevicesImageCantBeRead() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeAVD(home, "Unknown", image: nil)
    try makeImage(home, "android-30/default/x86_64")
    let discovery = Catalog(rules: fixtureRules).discovery(fixture: home)
    #expect(!discovery.candidates.contains { $0.ruleID == "android-system-images" })
    #expect(discovery.notes.map(\.text) == [AndroidSDK.unreadableNotice])
}

@Test func androidItemsAreRefusedWhileTheEmulatorOrAndroidStudioRuns() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeAVD(home, "Pixel", image: "system-images/android-34/google_apis/arm64-v8a/")
    try makeImage(home, "android-30/default/x86_64")
    let catalog = Catalog(rules: fixtureRules)
    let items = catalog.discover(fixture: home).filter { $0.ruleID.hasPrefix("android-") }
    #expect(items.count == 2)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    for process in ["emulator", "qemu-system-aarch64", "com.google.android.studio"] {
        let check = CandidateCheck(catalog: catalog, running: Running(names: [process]), home: home)
        let result = await CleanupExecutor(journal: journal, check: check, trash: TrashNeverUsed()).execute(CatalogApproval(candidates: items, previewOnly: false))
        #expect(result.records.allSatisfy { $0.state == .skipped && $0.message == "Android Studio or the emulator is running. Quit it, then scan again." }, "\(process)")
    }
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(avdHome + "/Pixel.avd/userdata-qemu.img").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(images + "/android-30/default/x86_64/system.img").path))
}

@Test func aVirtualDeviceGoesToTrashWithItsIniAndAnUnusedImageIsDeleted() async throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeAVD(home, "Pixel", image: "system-images/android-34/google_apis/arm64-v8a/")
    try makeAVD(home, "Keep", image: "system-images/android-33/default/arm64-v8a/")
    try makeImage(home, "android-33/default/arm64-v8a")
    try makeImage(home, "android-30/default/x86_64")
    let catalog = Catalog(rules: fixtureRules)
    let items = catalog.discover(fixture: home).filter { $0.ruleID == "android-system-images" || $0.url.lastPathComponent == "Pixel.avd" }
    #expect(items.count == 2)
    let trash = FixtureTrash(home.appendingPathComponent("fixture-trash"))
    let check = CandidateCheck(catalog: catalog, running: nothingRunning, home: home)
    let result = await CleanupExecutor(journal: try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite")), check: check, trash: trash)
        .execute(CatalogApproval(candidates: items, previewOnly: false))
    #expect(result.records.allSatisfy { $0.state == .succeeded }, "\(result.records.map(\.message))")
    #expect(Set(trash.moved) == ["Pixel.avd", "Pixel.ini"])
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(images + "/android-30/default/x86_64").path))
    // The image the remaining device uses, and that device, stay.
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(images + "/android-33/default/arm64-v8a/system.img").path))
    #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(avdHome + "/Keep.ini").path))
}

@Test func anImageAVirtualDeviceStartedUsingAfterTheScanIsRefused() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeImage(home, "android-30/default/x86_64")
    let catalog = Catalog(rules: fixtureRules)
    let image = try #require(catalog.discover(fixture: home).first { $0.ruleID == "android-system-images" })
    let check = CandidateCheck(catalog: catalog, running: nothingRunning, home: home)
    #expect(check.check(image) == nil)
    try makeAVD(home, "New", image: "system-images/android-30/default/x86_64")
    #expect(check.check(image) == .inUse("An Android virtual device"))
}

@Test func androidSystemImagesAreNeverRecommendedButChosenOneByOne() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try makeImage(home, "android-30/default/x86_64")
    let catalog = Catalog(rules: fixtureRules)
    let found = catalog.discover(fixture: home)
    #expect(found.contains { $0.ruleID == "android-system-images" })
    #expect(RecommendedPlan(catalog: catalog, candidates: found, check: { _ in nil }).candidates.isEmpty)
}

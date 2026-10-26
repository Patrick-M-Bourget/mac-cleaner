import Foundation
import Testing
@testable import StillCore

/// Simulators and Android emulators (#134). Every test uses a temp fixture home, a stand-in simctl that prints
/// canned JSON, and a fixture `.android`; the real simctl and the real `~/.android` are never touched.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillDevices-\(UUID())")
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
    // simctl decides what goes; Still never deletes the device folder itself.
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

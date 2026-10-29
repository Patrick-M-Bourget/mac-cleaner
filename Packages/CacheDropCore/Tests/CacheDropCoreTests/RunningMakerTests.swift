import Foundation
import Testing
@testable import CacheDropCore

// #240: a removed app's leftovers wait while anything of its maker runs, a plain background process as much as an app.
// Every test lists fixture processes whose executables sit in temp folders; the real process table is never read.

private func fixtureFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropRunningMaker-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}
/// A bundle with an Info.plist and an executable that does nothing; it is never run.
@discardableResult
private func bundle(_ relative: String, in root: URL, id: String, copyright: String? = nil) throws -> String {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": id]
    if let copyright { info["NSHumanReadableCopyright"] = copyright }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
    let executable = url.appendingPathComponent("Contents/MacOS/" + url.deletingPathExtension().lastPathComponent)
    try Data().write(to: executable)
    return executable.path
}
/// A plain executable with no bundle around it.
private func tool(_ relative: String, in root: URL) throws -> String {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: url)
    return url.path
}

private struct Processes: ProcessListing {
    var list: [RunningProcess]?
    func processes() -> [RunningProcess]? { list }
}
private func checker(_ paths: [String]) -> SystemRunningAppChecker {
    SystemRunningAppChecker(processes: Processes(list: paths.map { RunningProcess(path: $0) }))
}
private func maker(_ vendor: String) -> RuleOwner { RuleOwner(name: vendor, bundleIDPrefixes: [vendor + "."]) }

@Test func aBackgroundHelperOfTheMakerCountsAsRunning() throws {
    let root = try fixtureFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    // Not an app the Dock or Launch Services shows: a helper started by a launch agent.
    let helper = try bundle("Library/Application Support/Gone/Gone Agent.app", in: root, id: "com.gone.agent")
    let xpc = try bundle("Applications/Other.app/Contents/XPCServices/Fetcher.xpc", in: root, id: "com.other.fetcher")

    #expect(checker([helper]).isRunning(maker("com.gone")) == true)
    #expect(checker([xpc]).isRunning(maker("com.other")) == true)
    #expect(checker([helper, xpc]).isRunning(maker("com.unrelated")) == false)
}

@Test func aBackgroundProcessCountsForItsMakerByNameAsInstalledBundlesDo() throws {
    let root = try fixtureFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    // #251's maker-wide rules: Reason Studios makes com.reasonstudios.* though this helper still carries Propellerhead's ID.
    let helper = try bundle("Library/Application Support/Reason/Reason Helper.app", in: root, id: "se.propellerheads.helper",
                            copyright: "© 2024 Reason Studios AB. All rights reserved.")
    // A plain executable in a folder named for its maker, and a privileged helper named by its bundle ID.
    let daemon = try tool("Library/Application Support/FabFilter/Sync/fabsync", in: root)
    let privileged = try tool("Library/PrivilegedHelperTools/com.toolmaker.helper", in: root)

    #expect(checker([helper]).isRunning(maker("com.reasonstudios")) == true)
    #expect(checker([helper]).isRunning(maker("se.propellerheads")) == true)
    #expect(checker([daemon]).isRunning(maker("com.fabfilter")) == true)
    #expect(checker([privileged]).isRunning(maker("com.toolmaker")) == true)
    #expect(checker([helper, daemon, privileged]).isRunning(maker("com.gone")) == false)
}

@Test func aSharedHostingNamespaceStaysOneMaker() throws {
    let root = try fixtureFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let alice = try bundle("Applications/Clipper.app", in: root, id: "io.github.alice.clipper")

    // Coarse until a real-Mac listing shows it blocks too much (#259): any io.github process holds back io.github leftovers.
    #expect(checker([alice]).isRunning(maker("io.github")) == true)
    let tie = LeftoverTie(app: "Notes", bundleID: "io.github.bob.notes", vendor: "io.github", evidence: .bundleID)
    #expect(tie.owner.bundleIDPrefixes == ["io.github."])
    #expect(checker([alice]).isRunning(tie.owner) == true)
    let receipt = LeftoverTie(app: "Notes", bundleID: nil, vendor: "io.github", evidence: .receipt("io.github.bob.notes.pkg"))
    #expect(receipt.owner.bundleIDPrefixes == ["io.github."])
    #expect(LeftoverTie(app: "Live", bundleID: "com.ableton.live", vendor: "com.ableton", evidence: .bundleID).owner
        == RuleOwner(name: "Ableton", bundleIDPrefixes: ["com.ableton."]))
}

@Test func macOSOwnProcessesNeverStandForAMaker() throws {
    let root = try fixtureFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let finder = try bundle("System/Library/CoreServices/Finder.app", in: root, id: "com.apple.finder", copyright: "Copyright © 2001–2026 Apple Inc.")

    #expect(checker([finder]).isRunning(maker("com.applecart")) == false)
}

@Test func anUnreadableProcessListMeansTheMakerMayBeRunning() {
    #expect(SystemRunningAppChecker(processes: Processes(list: nil)).isRunning(maker("com.gone")) == nil)
    // Owners without a maker never need the list.
    #expect(SystemRunningAppChecker(processes: Processes(list: nil)).isRunning(RuleOwner(name: "Nothing")) == false)
}

/// Counts how often the process list is read.
private final class CountingProcesses: ProcessListing, @unchecked Sendable {
    let list: [RunningProcess]?
    private let lock = NSLock()
    private var count = 0
    init(_ list: [RunningProcess]?) { self.list = list }
    var reads: Int { lock.withLock { count } }
    func processes() -> [RunningProcess]? { lock.withLock { count += 1 }; return list }
}

/// Bundle IDs and command lines are read from the injected listing too, not only makers and paths (#261): an owner whose app
/// and tool really run on this Mac (the Dock, this test process) isn't running in an empty fixture list, and each check reads
/// the list once.
@Test func everyRunningCheckReadsOneInjectedProcessListOnce() throws {
    let executable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).lastPathComponent
    let owner = RuleOwner(name: "Fixture", bundleIDs: ["com.apple.dock"], executables: [executable], paths: ["/Applications/Fixture.app"])
    let empty = CountingProcesses([])
    #expect(SystemRunningAppChecker(processes: empty).isRunning(owner) == false)
    #expect(empty.reads == 1)

    let app = CountingProcesses([RunningProcess(path: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", bundleID: "com.apple.dock")])
    #expect(SystemRunningAppChecker(processes: app).isRunning(owner) == true)
    #expect(app.reads == 1)
    let tool = CountingProcesses([RunningProcess(path: "/usr/local/bin/\(executable)", arguments: ["/usr/local/bin/\(executable)", "--flag"])])
    #expect(SystemRunningAppChecker(processes: tool).isRunning(owner) == true)
    #expect(tool.reads == 1)
    // A process whose command line can't be read (another user's) is only its executable, which a tool owner doesn't match by path.
    let unread = CountingProcesses([RunningProcess(path: "/opt/other/\(executable)")])
    #expect(SystemRunningAppChecker(processes: unread).isRunning(owner) == false)
    #expect(SystemRunningAppChecker(processes: CountingProcesses(nil)).isRunning(owner) == nil)
}

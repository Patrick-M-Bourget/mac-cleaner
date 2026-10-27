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

@Test func aSharedHostingNamespaceIsNotOneMaker() throws {
    let root = try fixtureFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let alice = try bundle("Applications/Clipper.app", in: root, id: "io.github.alice.clipper")

    #expect(checker([alice]).isRunning(maker("io.github.alice")) == true)
    #expect(checker([alice]).isRunning(maker("io.github.bob")) == false)
    // A leftover's owner names the maker inside the namespace, so only that maker's processes block it.
    let tie = LeftoverTie(app: "Notes", bundleID: "io.github.bob.notes", vendor: "io.github", evidence: .bundleID)
    #expect(tie.owner.bundleIDPrefixes == ["io.github.bob."])
    #expect(tie.owner.name == "Bob")
    let receipt = LeftoverTie(app: "Notes", bundleID: nil, vendor: "io.github", evidence: .receipt("io.github.bob.notes.pkg"))
    #expect(receipt.owner.bundleIDPrefixes == ["io.github.bob."])
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

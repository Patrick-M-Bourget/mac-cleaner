import Foundation
import Darwin
import StillCore

private struct GuardIdentity: Decodable {
    let device: Int32
    let inode: UInt64
    let owner: UInt32
}
private struct GuardManifest: Decodable {
    let schema: Int
    let source: String
    let runID: String
    let standardRootInitiallyAbsent: Bool
    let ownedRoot: String
    let project: String
    let derivedData: String
    let projectMetadata: [String]
    let standardRootIdentity: GuardIdentity
    let ownedRootIdentity: GuardIdentity
}
private struct QualificationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// A worker-only crash at a public owner boundary, never a production execution hook.
private final class CrashEnvironment: XcodeBuildEnvironment, @unchecked Sendable {
    let native: NativeXcodeBuildEnvironment
    private let lock = NSLock()
    private var armed = false
    private var observations = 0
    init(_ native: NativeXcodeBuildEnvironment) { self.native = native }
    func arm() { lock.lock(); armed = true; observations = 0; lock.unlock() }
    func now() -> Date { native.now() }
    func validateInstallation() throws { try native.validateInstallation() }
    func standardDerivedDataURL() throws -> URL { try native.standardDerivedDataURL() }
    func projects(in root: URL) throws -> XcodeProjectMapping { try native.projects(in: root) }
    func ownerObservation() throws -> XcodeOwnerObservation {
        let observation = try native.ownerObservation()
        lock.lock()
        if armed { observations += 1 }
        let crash = armed && observations == 2 && observation.activity == .closed
        lock.unlock()
        if crash {
            FileHandle.standardError.write(Data("Owned worker SIGKILL after execution-phase owner observation; inspect public durable records to establish the intent boundary.\n".utf8))
            kill(getpid(), SIGKILL)
            exit(99)
        }
        return observation
    }
}

@main struct XcodeQualificationRunner {
    static func require(_ condition: Bool, _ reason: String) throws {
        if !condition { throw QualificationError(reason) }
    }
    static func object<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
    static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    private static func checkedIdentity(_ url: URL, expected: GuardIdentity? = nil, directory: Bool = true) throws {
        var info = stat()
        try require(url.isFileURL && url.resolvingSymlinksInPath().path == url.path && lstat(url.path, &info) == 0,
                    "Canonical existing qualification path required")
        try require(info.st_uid == getuid() && info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG), "Owned qualification path type required")
        if let expected {
            try require(info.st_dev == expected.device && info.st_ino == expected.inode && info.st_uid == expected.owner,
                        "Qualification identity changed")
        }
    }
    static func selectedApplication() throws -> URL {
        let selected = Process(); let pipe = Pipe()
        selected.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select"); selected.arguments = ["-p"]
        selected.standardOutput = pipe
        try selected.run(); let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); selected.waitUntilExit()
        let developer = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        try require(selected.terminationStatus == 0 && developer.hasSuffix(".app/Contents/Developer"), "Selected full Xcode required")
        return URL(fileURLWithPath: developer).deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
    }
    private static func manifest(_ path: String, source: String, run: String) throws -> (GuardManifest, URL) {
        guard let temporary = ProcessInfo.processInfo.environment["RUNNER_TEMP"], !temporary.isEmpty else { throw QualificationError("RUNNER_TEMP required") }
        let runner = URL(fileURLWithPath: temporary).resolvingSymlinksInPath()
        let url = URL(fileURLWithPath: path)
        try require(url.path.hasPrefix(runner.path + "/"), "Runner-contained manifest required")
        try checkedIdentity(url, directory: false)
        var fileInfo = stat(); try require(lstat(url.path, &fileInfo) == 0 && fileInfo.st_size <= 65_536 && fileInfo.st_nlink == 1, "Bounded manifest required")
        let value = try JSONDecoder().decode(GuardManifest.self, from: Data(contentsOf: url))
        try require(value.schema == 1 && value.source == source && value.runID == run && value.standardRootInitiallyAbsent,
                    "Fresh same-run/source qualification proof required")
        let owned = URL(fileURLWithPath: value.ownedRoot, isDirectory: true)
        try require(owned.deletingLastPathComponent().path == runner.path && owned.lastPathComponent.hasPrefix("StillXcodeStandard-"), "Fresh owned fixture root required")
        try checkedIdentity(owned, expected: value.ownedRootIdentity)
        var info = stat(); try require(lstat(owned.path, &info) == 0 && info.st_mode & 0o777 == 0o700, "Private fixture root required")
        let project = URL(fileURLWithPath: value.project, isDirectory: true)
        try require(project.path == owned.appendingPathComponent("Sources/Probe.xcodeproj").path, "Exact generated project required")
        try checkedIdentity(project)
        let standard = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        try checkedIdentity(standard, expected: value.standardRootIdentity)
        let derived = URL(fileURLWithPath: value.derivedData, isDirectory: true)
        try require(derived.deletingLastPathComponent().path == standard.path && derived.lastPathComponent.hasPrefix("Probe-"), "Exact standard project root required")
        try checkedIdentity(derived)
        try require(value.projectMetadata == [derived.appendingPathComponent("info.plist").path], "Exact native mapping proof required")
        try checkedIdentity(URL(fileURLWithPath: value.projectMetadata[0]), directory: false)
        return (value, owned)
    }
    static func main() async {
        do { try await run() }
        catch {
            try? emit(["error": String(describing: error), "qualificationPassed": false])
            exit(1)
        }
    }
    static func run() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let environment = ProcessInfo.processInfo.environment
        try require(environment["GITHUB_ACTIONS"] == "true" && environment["RUNNER_ENVIRONMENT"] == "github-hosted",
                    "Fresh GitHub-hosted qualification required")
        guard let run = environment["GITHUB_RUN_ID"], !run.isEmpty, let source = environment["GITHUB_SHA"], !source.isEmpty else { throw QualificationError("Run/source required") }
        let arguments = Array(CommandLine.arguments.dropFirst())
        try require(arguments.count == 1 || arguments.count == 2, "Explicit qualification command required")
        let command = arguments[0]
        let application = try selectedApplication()
        let native = NativeXcodeBuildEnvironment(applicationURL: application)
        if command == "owners" {
            try require(arguments.count == 1, "Owners accepts no paths")
            let observed = try native.ownerObservation()
            try emit(["activity": observed.activity.rawValue, "reason": observed.reason as Any? ?? NSNull(), "source": source, "runID": run,
                      "selectedApplication": application.path, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started])
            return
        }
        try require(arguments.count == 2 && ["action", "crash", "records", "replay"].contains(command), "Known manifest-bound command required")
        let (proof, owned) = try manifest(arguments[1], source: source, run: run)
        let crash = CrashEnvironment(native)
        let journal = owned.appendingPathComponent(command == "action" ? "action-journal.json" : "crash-journal.json")
        let module = XcodeIntermediates(environment: command == "crash" ? crash : native, journalURL: journal)
        if command == "records" {
            let records = try await module.records()
            try require(records.count == 1 && records[0].unresolved && records[0].artifacts.contains { $0.status == .unknown }, "Public unresolved intent required after worker crash")
            try emit(["command": command, "source": source, "runID": run, "records": try object(records), "qualificationPassed": true])
            return
        }
        let inspection = await module.inspectStandardDerivedData()
        let findings = inspection.projects.filter { $0.projectURL.path == proof.project }
        try require(inspection.unavailableReason == nil && inspection.owner.activity == .closed && findings.count == 1 && findings[0].unavailableReason == nil,
                    "Expected owned project's native inspection must be closed and available")
        let artifacts = findings[0].artifacts.sorted { $0.relativePath < $1.relativePath }
        try require(artifacts.count == 2 && Set(artifacts.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }) == ["main.o", "helper.o"], "Exactly two generated native artifacts required")
        let approval = try await module.approve(artifactIDs: Set(artifacts.map(\.id)))
        if command == "crash" {
            crash.arm()
            let outcome = await module.execute(approval, cancellation: CleanupCancellation())
            throw QualificationError("Expected owned worker signal did not occur: " + outcome.disposition.rawValue)
        }
        if command == "replay" {
            let before = try object(await module.records()) as? NSArray
            let outcome = await module.execute(approval, cancellation: CleanupCancellation())
            let after = try object(await module.records()) as? NSArray
            try require(outcome.disposition == .rejected && before == after, "Unresolved public records must block fresh approval without replay")
            try emit(["command": command, "source": source, "runID": run, "run": try object(outcome), "records": try object(await module.records()), "qualificationPassed": true])
            return
        }
        let standard = try native.standardDerivedDataURL()
        let replaced = standard.appendingPathComponent(artifacts[0].relativePath)
        try require(replaced.path.hasPrefix(proof.derivedData + "/Build/Intermediates.noindex/"), "Owned generated target required")
        let original = try Data(contentsOf: replaced)
        let temporary = replaced.deletingLastPathComponent().appendingPathComponent("Still-replacement-" + UUID().uuidString)
        try original.write(to: temporary, options: .withoutOverwriting)
        try require(rename(temporary.path, replaced.path) == 0, "Atomic owned replacement failed")
        let late = replaced.deletingLastPathComponent().appendingPathComponent("Still-late-unapproved.o")
        try original.write(to: late, options: .withoutOverwriting)
        let outcome = await module.execute(approval, cancellation: CleanupCancellation())
        let reloaded = XcodeIntermediates(environment: native, journalURL: journal)
        let records = try await reloaded.records()
        let replay = await module.execute(approval, cancellation: CleanupCancellation())
        let unchanged = standard.appendingPathComponent(artifacts[1].relativePath)
        try require(outcome.artifacts.filter { $0.status == .succeeded }.count == 1 && outcome.artifacts.filter { $0.status == .skipped }.count == 1 && !outcome.unresolved,
                    "Exact execution must remove one unchanged and skip one replaced object")
        let replacedPreserved = try Data(contentsOf: replaced) == original
        let latePreserved = try Data(contentsOf: late) == original
        try require(replacedPreserved && latePreserved && !FileManager.default.fileExists(atPath: unchanged.path) && records.count == 1 && records[0].id == outcome.id && replay.disposition == .rejected, "Frozen target/reload/replay qualification failed")
        try emit(["command": command, "source": source, "runID": run, "run": try object(outcome), "durableReloadCount": records.count,
                  "replayDisposition": replay.disposition.rawValue, "lateFile": late.path, "lateFilePreserved": latePreserved,
                  "replacedFilePreserved": replacedPreserved, "artifactCount": artifacts.count,
                  "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started, "qualificationPassed": true])
    }
}

import Foundation
import Darwin
import CryptoKit
import StillCore

@main struct ChromeCleanupRunner {
    struct Refusal: Error, CustomStringConvertible { let description: String }
    struct Activity: Codable, Sendable {
        let pid: Int32
        let parentPID: UInt32?
        let uid: UInt32?
        let status: UInt32?
        let executableBasename: String
        let selectedBundle: Bool
    }
    struct RunningRefusal: Error, CustomStringConvertible {
        let description: String
        let activity: [Activity]
    }
    /// Hosted diagnostic only, invoked after verified same-run provenance and a
    /// real public .running result. Never records arguments or private paths.
    static func activityDiagnostics(_ bundle: URL) -> [Activity] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, Int(count) < pids.count else { return [] }
        var matching: [Activity] = []
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0 else { continue }
            let path = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let selected = path.hasPrefix(bundle.path + "/")
            guard selected || path.hasSuffix("/Contents/MacOS/Google Chrome") || path.contains("/Google Chrome Framework.framework/") else { continue }
            var details = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let observed = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size) == size
            matching.append(.init(pid: pid, parentPID: observed ? details.pbi_ppid : nil,
                                  uid: observed ? details.pbi_uid : nil, status: observed ? details.pbi_status : nil,
                                  executableBasename: URL(fileURLWithPath: path).lastPathComponent,
                                  selectedBundle: selected))
        }
        return matching
    }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Refusal(description: message) }
    }
    static func canonical(_ string: String) throws -> URL {
        let url = URL(fileURLWithPath: string)
        try require(string.hasPrefix("/"), "Absolute fixture path required")
        if let physical = realpath(string, nil) {
            defer { free(physical) }
            try require(String(cString: physical) == string, "Physical canonical fixture path required")
        } else {
            try require(errno == ENOENT, "Fixture path is inaccessible")
            guard let parent = realpath(url.deletingLastPathComponent().path, nil) else { throw Refusal(description: "Existing canonical parent required") }
            defer { free(parent) }
            try require(String(cString: parent) + "/" + url.lastPathComponent == string, "Canonical parent and leaf required")
            return URL(fileURLWithPath: String(cString: parent), isDirectory: true).standardizedFileURL.appendingPathComponent(url.lastPathComponent)
        }
        return url.standardizedFileURL
    }
    static func inside(_ child: URL, _ parent: URL) -> Bool { child.path.hasPrefix(parent.path + "/") }
    static func main() async {
        do {
            let environment = ProcessInfo.processInfo.environment
            try require(environment["GITHUB_ACTIONS"] == "true" && environment["RUNNER_ENVIRONMENT"] == "github-hosted", "Ephemeral GitHub-hosted macOS only")
            var arguments: [String: String] = [:]
            let input = Array(CommandLine.arguments.dropFirst())
            try require(input.count.isMultiple(of: 2), "Use --root --data --bundle --profile --journal [--provision]")
            for offset in stride(from: 0, to: input.count, by: 2) {
                try require(arguments[input[offset]] == nil, "Duplicate option refused")
                arguments[input[offset]] = input[offset + 1]
            }
            func value(_ name: String) throws -> String {
                guard let value = arguments[name] else { throw Refusal(description: "Missing " + name) }; return value
            }
            let root = try canonical(value("--root"))
            let data = try canonical(value("--data"))
            let bundle = try canonical(value("--bundle"))
            let profile = try value("--profile")
            let journal = try canonical(value("--journal"))
            let runner = try canonical(environment["RUNNER_TEMP"] ?? "")
            let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            try require(root.deletingLastPathComponent().path == temporary.path && root.lastPathComponent.hasPrefix("StillChromeProbe-"), "Owned ephemeral Chrome probe root required")
            var info = stat()
            try require(lstat(root.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && info.st_uid == getuid() && info.st_mode & 0o022 == 0, "Unsafe fixture root")
            try require(inside(data, root) && inside(bundle, runner), "Data and vendor bundle must remain inside their disposable roots")
            try require(profile == "Default" || profile == "Profile 1", "Only the qualified synthetic profile identifiers are supported")
            try require(journal.deletingLastPathComponent().path == root.path && journal.lastPathComponent.hasPrefix("swift-journal-") && journal.pathExtension == "json", "Owned standalone Swift journal required")
            let provision = try canonical(arguments["--provision"] ?? environment["STILL_CHROME_SWIFT_PROVISION"] ?? "")
            try require(inside(provision, runner), "Vendor provenance must belong to this runner")
            let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: provision)) as? [String: Any]
            try require(metadata?["githubRunID"] as? String == environment["GITHUB_RUN_ID"] && metadata?["githubSHA"] as? String == environment["GITHUB_SHA"], "Same-run vendor provenance required")
            try require(metadata?["provisioningComplete"] as? Bool == true && metadata?["sealedBundleVerified"] as? Bool == true && (metadata?["bundle"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path } == bundle.path, "Verified regular Stable bundle required")
            try NativeChromeCacheEnvironment().validateInstallation(at: bundle)
            let binary = try Data(contentsOf: bundle.appendingPathComponent("Contents/MacOS/Google Chrome"), options: .mappedIfSafe)
            let digest = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
            try require(digest == metadata?["executableSHA256"] as? String, "Provisioned executable changed")
            let service = ChromeCacheService(journalURL: journal)
            let inspected = await service.inspect(.init(applicationURL: bundle, dataRootURL: data, cacheRootURL: data, customLocation: true))
            guard let group = inspected.groups.first(where: { $0.profileIdentifier == profile && $0.availability == .eligible }) else {
                if inspected.availability == .running {
                    throw RunningRefusal(description: inspected.unavailableReason ?? "Browser activity observed", activity: activityDiagnostics(bundle))
                }
                throw Refusal(description: inspected.unavailableReason ?? "Requested generated cache group is unavailable")
            }
            let approval = try await service.approve(groupIDs: [group.id])
            let run = await service.execute(approval, cancellation: CleanupCancellation())
            let completed = run.groups.count == 1 && run.groups[0].status == .succeeded && !run.unresolved
            let runData = try JSONEncoder().encode(run)
            let serialized = try JSONSerialization.jsonObject(with: runData)
            let result: [String: Any] = ["removed": run.groups.reduce(0) { $0 + $1.removedFiles }, "status": completed ? "completed" : "stopped", "reason": run.groups.compactMap(\.reason).joined(separator: "; "), "coreRun": serialized, "productionSwiftAdapter": true]
            let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            FileHandle.standardOutput.write(output); FileHandle.standardOutput.write(Data("\n".utf8))
            if !completed { exit(1) }
        } catch {
            var output: [String: Any] = ["removed": 0, "status": "stopped", "reason": String(describing: error), "productionSwiftAdapter": true]
            if let running = error as? RunningRefusal,
               let data = try? JSONEncoder().encode(running.activity),
               let diagnostic = try? JSONSerialization.jsonObject(with: data) {
                output["activityDiagnostic"] = diagnostic
            }
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8)) }
            exit(1)
        }
    }
}

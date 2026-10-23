import Foundation
import Darwin
import StillCore

private func interrupt() -> Never {
    guard kill(getpid(), SIGKILL) == 0 else { _exit(71) }
    while true { pause() }
}
private struct CrashJournal: CleanupJournaling {
    let base: SQLiteCleanupJournal
    let stage: String
    func claim(_ batch: CleanupApproval) throws -> Bool {
        if stage == "beforeClaim" { interrupt() }
        let claimed = try base.claim(batch)
        if stage == "afterClaim" { interrupt() }
        return claimed
    }
    func intent(_ record: CleanupRecord) throws {
        try base.intent(record)
        if stage == "afterIntent" { interrupt() }
    }
    func outcome(_ record: CleanupRecord) throws {
        try base.outcome(record)
        if stage == "afterOutcome" { interrupt() }
    }
    func records() throws -> [CleanupRecord] { try base.records() }
}
private struct OwnedHoldingOperation: TrashOperating {
    let holding: URL
    let stage: String
    func trash(_ target: PlannedTarget) throws -> URL? {
        // Fixture adapter only: no native Trash call or personal Trash inspection.
        try FileManager.default.moveItem(at: target.url, to: holding)
        if stage == "afterMutation" { interrupt() }
        return holding
    }
}
@main struct RecoveryProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 4, args[1] == "--child" {
            let root = URL(fileURLWithPath: args[2], isDirectory: true)
            let stage = args[3]
            guard root.lastPathComponent.hasPrefix("RecoveryStage-") else { throw CocoaError(.fileReadNoPermission) }
            let scope = root.appendingPathComponent("Downloads")
            let scan = try await FolderScanner().scan(scope)
            var draft = PlanDraft()
            _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: scope))
            let batch = try draft.approve(draft.review())
            let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("cleanup.sqlite"))
            _ = await TrashExecutor(journal: CrashJournal(base: journal, stage: stage), operation: OwnedHoldingOperation(holding: root.appendingPathComponent("owned-holding.pdf"), stage: stage)).execute(batch)
            throw CocoaError(.executableRuntimeMismatch)
        }
        guard args.count == 2, args[1] == "--run" else { print("Usage: RecoveryProbe --run; owns and removes only its disposable fixtures"); return }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("StillRecoveryProbe-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        var results: [[String: Any]] = []
        for stage in ["beforeClaim", "afterClaim", "afterIntent", "afterMutation", "afterOutcome"] {
            let fixture = root.appendingPathComponent("RecoveryStage-" + stage)
            let scope = fixture.appendingPathComponent("Downloads")
            try manager.createDirectory(at: scope, withIntermediateDirectories: true)
            let original = scope.appendingPathComponent("owned.pdf"), holding = fixture.appendingPathComponent("owned-holding.pdf")
            let sentinel = Data([1, 2, 3])
            try sentinel.write(to: original)
            let child = Process()
            child.executableURL = URL(fileURLWithPath: args[0]).standardizedFileURL
            child.arguments = ["--child", fixture.path, stage]
            child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.standardError
            try child.run()
            let deadline = Date().addingTimeInterval(10)
            while child.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit(); throw CocoaError(.executableRuntimeMismatch) }
            child.waitUntilExit()
            guard child.terminationReason == .uncaughtSignal, child.terminationStatus == SIGKILL else {
                print("Unexpected termination at \(stage): reason \(child.terminationReason.rawValue), status \(child.terminationStatus)")
                throw CocoaError(.executableRuntimeMismatch)
            }
            let reader = try SQLiteCleanupJournal(url: fixture.appendingPathComponent("cleanup.sqlite"), readOnly: true)
            let beforeOriginal = try? Data(contentsOf: original), beforeHolding = try? Data(contentsOf: holding)
            let snapshot = try CleanupRecoverySnapshot(journal: reader)
            _ = try CleanupRecoverySnapshot(journal: reader)
            let records = try reader.records()
            let expected: [CleanupTargetState] = stage == "beforeClaim" ? [] : stage == "afterClaim" ? [.pending] : stage == "afterOutcome" ? [.succeeded] : [.intent]
            guard records.map(\.state) == expected,
                  beforeOriginal == (try? Data(contentsOf: original)), beforeHolding == (try? Data(contentsOf: holding)),
                  beforeOriginal == sentinel || beforeHolding == sentinel else { throw CocoaError(.fileReadCorruptFile) }
            results.append(["boundary": stage, "terminationSignal": child.terminationStatus,
                "persistedStates": records.map { $0.state.rawValue }, "recoveryUnresolved": snapshot.unresolvedCount,
                "notStarted": snapshot.pendingCount, "originalPresent": beforeOriginal != nil, "holdingPresent": beforeHolding != nil,
                "unchangedByRepeatedRecovery": true, "operationAdapter": "owned-directory rename, not native Trash"])
        }
        let report: [String: Any] = ["hostOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "boundaries": results, "fixtureCleanup": "owned root removed at exit", "powerLossQualified": false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}

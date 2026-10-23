import AppKit
import Observation
import StillCore
import SwiftUI

@MainActor @Observable final class CleanupExecutionModel {
    private(set) var isRunning = false
    private(set) var result: CleanupExecutionResult?
    private(set) var before: StartupVolumeCapacity?
    private(set) var after: StartupVolumeCapacity?
    private(set) var error: String?
    private(set) var progress: CleanupExecutionProgress?
    private(set) var stopRequested = false
    private(set) var retryScopes: [URL] = []
    var canRetry: Bool { !isRunning && result?.targets.contains(where: { $0.state != .succeeded }) == true }
    private var executor: TrashExecutor?
    private var cancellation = CleanupCancellation()
    func clear() { guard !isRunning else { return }; result = nil; error = nil; before = nil; after = nil }
    func cancel() { stopRequested = true; cancellation.cancel() }
    func run(_ batch: CleanupApproval) async {
        guard !isRunning else { return }
        isRunning = true; cancellation = CleanupCancellation(); result = nil; error = nil; progress = nil; stopRequested = false; retryScopes = []
        defer { isRunning = false; executor = nil }
        do {
            let journal = try await Task.detached(priority: .userInitiated) {
                try CleanupJournalLocation.writer()
            }.value
            before = await Task.detached { StartupVolumeCapacity.read() }.value
            let worker = TrashExecutor(journal: journal, operation: executionOperation(batch), cancellation: cancellation)
            executor = worker
            result = await worker.execute(batch) { update in await MainActor.run { self.progress = update } }
            let unfinished = Set(result?.targets.filter { $0.state != .succeeded }.map(\.originalURL) ?? [])
            retryScopes = Array(Set(batch.targets.filter { unfinished.contains($0.url) }.map(\.scope)))
            after = await Task.detached { StartupVolumeCapacity.read() }.value
        } catch { self.error = "The local operation journal is unavailable. No files were moved. Recheck and create a new plan." }
    }
    private func executionOperation(_ batch: CleanupApproval) -> any TrashOperating {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-slow-trash"),
           let requested = ProcessInfo.processInfo.environment["STILL_TEST_DOWNLOADS_ROOT"],
           let root = try? DownloadsRoot(url: URL(fileURLWithPath: requested)), root.url.lastPathComponent.hasPrefix("StillSelectionUI-"),
           batch.targets.allSatisfy({ $0.downloadsRoot.url == root.url && $0.downloadsRoot.resourceID == root.resourceID }) {
            return SlowFixtureTrash(root: root.url)
        }
        #endif
        return NativeTrashOperation()
    }
    var observedChange: Int64? {
        guard let before, let after, let volume = before.volumeID, volume == after.volumeID,
              before.metric == after.metric, before.total == after.total,
              let first = before.available, let last = after.available else { return nil }
        return last - first
    }
}

struct CleanupExecutionView: View {
    @Bindable var model: CleanupExecutionModel
    var retryMessage: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: model.isRunning ? "Moving selected files to Trash" : "Cleanup results", subtitle: "Each exact file has its own result. Moving to Trash does not empty Trash.")
            if model.isRunning {
                ProgressView(value: Double(model.progress?.resolved ?? 0), total: Double(max(1, model.progress?.total ?? 1)))
                StatusRow(text: model.stopRequested ? "Stopping after the current file reaches a recorded outcome…" : "\(model.progress?.resolved ?? 0) of \(model.progress?.total ?? 0) targets reported", symbol: "clock")
            }
            if let retryMessage { StatusRow(text: retryMessage, symbol: "arrow.clockwise", role: .caution) }
            if let error = model.error { StatusRow(text: error, symbol: "exclamationmark.circle", role: .failure) }
            if let result = model.result {
                SummarySurface {
                    VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                        Text("Planned logical size: \(bytes(result.plannedLogicalBytes))")
                        Text("Planned allocated size held in Trash: \(result.trashHeldAllocatedBytes.map(bytes) ?? "Unknown")")
                        Text("Observed startup-volume available-capacity change: \(model.observedChange.map { ($0 >= 0 ? "+" : "−") + bytes(abs($0)) } ?? "Unknown")")
                        Text("Capacity is sampled independently and may change for other reasons. APFS sharing and snapshots prevent an exact exclusive-space promise.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack { ForEach([CleanupTargetState.succeeded, .failed, .skipped, .cancelled, .unknown], id: \.self) { state in Text("\(title(state)): \(result.targets.filter { $0.state == state }.count)").font(.caption) } }
                if let failure = result.journalFailure { StatusRow(text: failure, symbol: "exclamationmark.triangle", role: .failure) }
                ForEach(result.targets) { record in
                    SettingsRow(title: record.originalURL.lastPathComponent, detail: record.originalURL.path) {
                        StatusRow(text: "\(title(record.state)) · \(record.message)", symbol: record.state == .succeeded ? "checkmark.circle" : "info.circle", role: record.state == .succeeded ? .success : .neutral)
                        if let returned = record.trashURL, record.state == .succeeded {
                            Text(returned.path).font(.caption).textSelection(.enabled).accessibilityIdentifier("trashLocation-" + record.originalURL.lastPathComponent)
                            Button("Reveal in Trash") { NSWorkspace.shared.activateFileViewerSelecting([returned]) }.accessibilityLabel("Reveal \(record.originalURL.lastPathComponent) in Trash")
                        }
                    }
                    Divider()
                }
                StatusRow(text: "This plan is consumed. Choose and recheck a location before making another plan. Unknown outcomes must be reviewed; they are never repeated automatically.", symbol: "arrow.clockwise")
            }
        }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    private func title(_ state: CleanupTargetState) -> String {
        switch state { case .pending: "Not started"; case .intent, .unknown: "Unknown"; case .succeeded: "Succeeded"; case .failed: "Failed"; case .skipped: "Skipped"; case .cancelled: "Cancelled" }
    }
}

#if DEBUG
/// Delays only an explicitly configured, chooser-bound owned fixture. Still calls the real native adapter.
private struct SlowFixtureTrash: TrashOperating {
    let root: URL
    func trash(_ target: PlannedTarget) throws -> URL? {
        guard target.downloadsRoot.url == root, root.lastPathComponent.hasPrefix("StillSelectionUI-") else { throw CleanupValidationError.changedOrProtected }
        Thread.sleep(forTimeInterval: 5)
        return try NativeTrashOperation().trash(target)
    }
}
#endif

import AppKit
import Observation
import StillCore
import SwiftUI

extension AppLifecycleController: HistoryMaintenanceLifecycle {
    var operationActive: Bool { operationInProgress || selection.execution.isRunning }
    var maintenanceActive: Bool { get { maintenanceInProgress } set { maintenanceInProgress = newValue } }
}

@MainActor @Observable final class CleanupHistoryModel {
    var snapshot: CleanupHistorySnapshot?
    var message: String?
    var blocked = false
    var busy = false
    func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let loaded = try await HistoryLoadCoordinator.load(lifecycle: AppLifecycleController.shared) { mayMaintain in
                try await Task.detached {
                    guard let reader = try CleanupJournalLocation.existingReader() else { return (CleanupHistorySnapshot(records: []), false) }
                    if mayMaintain {
                        let journal = try CleanupJournalLocation.writer()
                        let maintenance = try journal.retainCompletedRuns()
                        let compacted = maintenance.removedRecords == 0 ? true : try journal.compact().completed
                        return (try journal.completedHistory(), !compacted)
                    }
                    return (try reader.completedHistory(), false)
                }.value
            }
            snapshot = loaded.0
            if loaded.1 { message = "Expired completed history was removed, but journal compaction did not finish. Disk reclamation is not confirmed." }
            blocked = false
        } catch { blocked = true; message = "The local journal cannot be read. Clear and reset are unavailable; keep its recovery records." }
    }
    func clear() async {
        guard !busy, !AppLifecycleController.shared.maintenanceInProgress, !AppLifecycleController.shared.operationInProgress else { message = "Wait for the current cleanup to finish."; return }
        busy = true; defer { busy = false }
        let lifecycle = AppLifecycleController.shared
        lifecycle.maintenanceInProgress = true; defer { lifecycle.maintenanceInProgress = false }
        do {
            let result = try await Task.detached {
                let journal = try CleanupJournalLocation.writer()
                let removed = try journal.clearCompletedRuns()
                let compacted = try journal.compact()
                return (removed, compacted, try journal.completedHistory())
            }.value
            snapshot = result.2
            try await GrowthHistoryModel.shared.clearCompletedHistory()
            message = "Cleared \(result.0.removedRuns) completed runs. Recovery facts retained." + (result.1.completed ? " Local journal compacted." : " Journal compaction was deferred or failed; disk reclamation is not confirmed.")
        } catch { message = "History maintenance did not finish. Some completed records may already be cleared; recovery facts remain protected." }
    }
    func reset() async -> Bool {
        let lifecycle = AppLifecycleController.shared
        guard !busy, !lifecycle.maintenanceInProgress, !lifecycle.operationInProgress, !lifecycle.selection.execution.isRunning else { message = "Reset is blocked while cleanup is running. Stop and review its results first."; return false }
        busy = true; lifecycle.maintenanceInProgress = true
        defer { busy = false; lifecycle.maintenanceInProgress = false }
        do {
            // This check is deliberately inside the write transaction, never based on cached UI.
            let result = try await Task.detached {
                let journal = try CleanupJournalLocation.writer()
                let removed = try journal.clearCompletedRuns(requireNoRecovery: true)
                let compacted = try journal.compact()
                return (removed, compacted)
            }.value
            try lifecycle.resetPreferences()
            try await GrowthHistoryModel.shared.resetHistory()
            lifecycle.selection.endSession(); lifecycle.selection.execution.clear()
            await lifecycle.inspection.resetSession()
            snapshot = CleanupHistorySnapshot(records: [])
            message = "Still’s preferences, selected locations and completed history were reset. Original files and macOS access grants are unchanged." + (result.1.completed ? "" : " Journal compaction did not finish; disk reclamation is not confirmed.")
            blocked = false
            return true
        } catch CleanupJournalError.recoveryRequired {
            blocked = true; message = "Reset is blocked by unfinished cleanup records. Open recovery review; no operations will resume automatically."
        } catch {
            blocked = true; message = "Reset could not finish safely. The journal or a preference service is unavailable; some completed history may already be cleared. Review recovery before trying again."
        }
        return false
    }
}

struct CleanupHistoryView: View {
    @State private var model = CleanupHistoryModel()
    @ObservedObject private var lifecycle = AppLifecycleController.shared
    @State private var confirmingClear = false
    @State private var confirmingReset = false
    var showRecovery: () -> Void
    var didReset: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "History", subtitle: "Completed cleanup runs stored locally. Recovery records are kept separately.")
            if let message = model.message {
                StatusRow(text: message, symbol: model.blocked ? "exclamationmark.triangle" : "info.circle", role: model.blocked ? .caution : .neutral, identifier: "historyStatus")
            }
            if model.blocked || (model.snapshot?.protectedRecordCount ?? 0) > 0 {
                SettingsRow(title: "Recovery facts are protected", detail: "Unfinished runs are excluded from Clear and retention. Reset requires them to be resolved.") {
                    Button("Open recovery review", action: showRecovery).accessibilityIdentifier("historyRecovery")
                }
            }
            SettingsRow(title: "Manage Still’s local data", detail: "Clearing completed runs also clears aggregate growth baselines. Reset additionally forgets preferences and selected locations, and stops alerts and login launch.") {
                HStack {
                    Button("Clear completed runs…") { confirmingClear = true }.accessibilityIdentifier("clearHistory")
                    Button("Reset Still…") { confirmingReset = true }.accessibilityIdentifier("resetStill")
                }.disabled(model.busy || lifecycle.operationInProgress)
            }
            if let snapshot = model.snapshot {
                if snapshot.completedRuns.isEmpty {
                    EmptyState(title: "No completed runs", detail: "Completed per-file results appear here after a cleanup. Nothing is selected or retried from history.", symbol: "clock")
                }
                ForEach(snapshot.completedRuns) { run in
                    SummarySurface {
                        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(StillDesign.TypeStyle.section)
                            if run.usesApprovalDate { Text("Approval date shown; outcome time was not recorded by this version.").font(.caption).foregroundStyle(.secondary) }
                            Text("Recorded file results: \(run.records.count)").font(.callout)
                            Text("Planned logical size: " + bytes(run.plannedLogicalBytes)).font(.callout)
                            Text("Planned allocation retained in Trash: " + (run.trashHeldAllocatedBytes.map(bytes) ?? "Unknown"))
                            Text("Observed startup-volume capacity change: " + (run.capacity?.observedChange.map { ($0 >= 0 ? "+" : "−") + bytes(abs($0)) } ?? "Unknown"))
                            Text("Capacity samples are independent and can change for other reasons. Allocation is an estimate, not an exclusive-space promise.").font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Per-file results") {
                                VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
                                    ForEach(run.records) { record in
                                        SettingsRow(title: record.originalURL.lastPathComponent, detail: record.originalURL.path) {
                                            StatusRow(text: "\(record.state.rawValue.capitalized) · \(record.message)", symbol: record.state == .succeeded ? "checkmark.circle" : "info.circle")
                                            Text("Action: \(record.action) · Policy \(record.policyVersion)").font(.caption).foregroundStyle(.secondary)
                                            if let trash = record.trashURL {
                                                Text("Recorded resulting location: " + trash.path).font(.caption).textSelection(.enabled)
                                                Button("Reveal recorded location") { NSWorkspace.shared.activateFileViewerSelecting([trash]) }
                                            }
                                        }
                                    }
                                }.padding(.leading, StillDesign.Space.xl)
                            }
                        }
                    }
                }
            } else if model.busy { ProgressView("Reading local history…") }
            Text("Completed records are retained for 90 days within a 250 MB payload budget. Interrupted runs are exempt. Trash contents remain until you empty Trash in Finder.").font(.caption).foregroundStyle(.secondary)

        }
        .task { await model.load() }
        .confirmationDialog("Clear completed runs?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear completed runs", role: .destructive) { Task { await model.clear() } }
        } message: { Text("Completed per-file history and growth baselines will be removed. Recovery facts, consumed approval IDs, original files and Trash contents remain.") }
        .confirmationDialog("Reset Still?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Still", role: .destructive) { Task { if await model.reset() { didReset() } } }
        } message: { Text("Forget Still’s preferences, selected locations and completed history; stop alerts and login launch. Original files, Trash and macOS access grants remain. Unfinished or unreadable journal records block reset.") }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
}

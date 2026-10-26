import AppKit
import Observation
import StillCore
import SwiftUI

extension AppLifecycleController: HistoryMaintenanceLifecycle {
    var operationActive: Bool { operationInProgress || selection.execution.isRunning }
    var maintenanceActive: Bool { get { maintenanceInProgress } set { maintenanceInProgress = newValue } }
}

enum HistoryActivityFilter: String, CaseIterable { case all = "All activity", scans = "Scans", cleanups = "Cleanups" }
private enum HistoryActivityItem: Identifiable {
    case scan(ScanActivity), cleanup(CleanupHistoryRun), chrome(ChromeCacheRun)
    var id: String { switch self { case .scan(let value): "scan-" + value.id.uuidString; case .cleanup(let value): "cleanup-" + value.id.uuidString; case .chrome(let value): "chrome-" + value.id.uuidString } }
    var date: Date { switch self { case .scan(let value): value.completedAt; case .cleanup(let value): value.date; case .chrome(let value): value.observedAt } }
}

@MainActor @Observable final class CleanupHistoryModel {
    var filter = HistoryActivityFilter.all
    var expandedScans: Set<UUID> = []
    let growthReturn = HistoryGrowthReturnContext()
    var chromeRuns: [ChromeCacheRun]?
    var chromeLoadError: String?
    var snapshot: CleanupHistorySnapshot?
    var message: String?
    var loadError: String?
    var blocked = false
    var busy = false
    func load(maintainCompleted: Bool = true) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let loaded = try await HistoryLoadCoordinator.load(lifecycle: AppLifecycleController.shared) { mayMaintain in
                try await Task.detached {
                    guard let reader = try CleanupJournalLocation.existingReader() else { return (CleanupHistorySnapshot(records: []), false) }
                    if mayMaintain && maintainCompleted {
                        let journal = try CleanupJournalLocation.writer()
                        let maintenance = try journal.retainCompletedRuns()
                        let compacted = maintenance.removedRecords == 0 ? true : try journal.compact().completed
                        return (try journal.completedHistory(), !compacted)
                    }
                    return (try reader.completedHistory(), false)
                }.value
            }
            snapshot = loaded.0
            loadError = nil
            if loaded.1 { message = "Expired completed history was removed, but journal compaction did not finish. Disk reclamation is not confirmed." }
            blocked = false
        } catch { snapshot = nil; blocked = true; loadError = "Cleanup history is unavailable. The local journal cannot be read. Clear and reset are unavailable; keep its recovery records." }
        do {
            chromeRuns = try await AppLifecycleController.shared.selection.chrome.records()
            chromeLoadError = nil
        } catch { chromeRuns = nil; chromeLoadError = "Chrome cleanup history is unavailable. Its recovery records are retained; no cleanup resumes automatically." }
    }
    func clear() async {
        let lifecycle = AppLifecycleController.shared
        guard !busy, !lifecycle.maintenanceInProgress, !lifecycle.operationInProgress, !lifecycle.selection.execution.isRunning else { message = "Wait for the current cleanup to finish."; return }
        busy = true; defer { busy = false }
        lifecycle.maintenanceInProgress = true; defer { lifecycle.maintenanceInProgress = false }
        var clearedRuns: Int?
        var compactionCompleted = false
        do {
            let chromeJournal = ChromeCacheService(journalURL: try LocalStateLocation.root(create: true).appendingPathComponent("chrome-cleanup.json"))
            _ = try await chromeJournal.clearCompletedRecords()
            chromeRuns = try await chromeJournal.records()
            let result = try await Task.detached {
                let journal = try CleanupJournalLocation.writer()
                let removed = try journal.clearCompletedRuns()
                // Compaction/readback cannot turn an already committed clear into an unknown count.
                let compacted = try? journal.compact()
                return (removed, compacted?.completed ?? false, try? journal.completedHistory())
            }.value
            clearedRuns = result.0.removedRuns; compactionCompleted = result.1
            snapshot = result.2
            if snapshot == nil { blocked = true; loadError = "Cleanup history is unavailable. The local journal cannot be read. Clear and reset are unavailable; keep its recovery records." }
            else { blocked = false; loadError = nil }
            try await GrowthHistoryModel.shared.clearCompletedHistory()
            await ScanActivityHistory.shared.load(maintain: false)
            let noun = result.0.removedRuns == 1 ? "run" : "runs"
            message = "Cleared \(result.0.removedRuns) completed cleanup \(noun), scan activity and growth baselines. Recovery facts retained." + compactionMessage(compactionCompleted)
        } catch {
            if let clearedRuns {
                let noun = clearedRuns == 1 ? "run" : "runs"
                message = "Cleared \(clearedRuns) completed cleanup \(noun). Scan activity and growth baseline clearing could not be confirmed. Recovery facts remain protected." + compactionMessage(compactionCompleted)
            } else {
                message = "Cleanup history clearing could not be confirmed. Scan activity and growth baselines were not cleared. Recovery facts remain protected."
            }
        }
    }
    private func compactionMessage(_ completed: Bool) -> String {
        completed ? " Local journal compacted." : " Journal compaction was deferred or failed; disk reclamation is not confirmed."
    }
    func reset() async -> Bool {
        let lifecycle = AppLifecycleController.shared
        guard !busy, !lifecycle.maintenanceInProgress, !lifecycle.operationInProgress, !lifecycle.selection.execution.isRunning else { message = "Reset is blocked while cleanup is running. Stop and review its results first."; return false }
        busy = true; lifecycle.maintenanceInProgress = true
        defer { busy = false; lifecycle.maintenanceInProgress = false }
        enum ResetStage { case journal, appearance, remainingPreferences }
        var resetStage = ResetStage.journal
        do {
            let chromeJournal = ChromeCacheService(journalURL: try LocalStateLocation.root(create: true).appendingPathComponent("chrome-cleanup.json"))
            _ = try await chromeJournal.clearCompletedRecords(requireNoRecovery: true)
            chromeRuns = try await chromeJournal.records()
            // This check is deliberately inside the write transaction, never based on cached UI.
            let result = try await Task.detached {
                let journal = try CleanupJournalLocation.writer()
                let removed = try journal.clearCompletedRuns(requireNoRecovery: true)
                let compacted = try journal.compact()
                return (removed, compacted)
            }.value
            resetStage = .appearance
            try lifecycle.selection.chrome.resetInspectionPreference()
            try lifecycle.resetAppearancePreference()
            resetStage = .remainingPreferences
            try lifecycle.resetPreferences()
            try lifecycle.locations.reset()
            try await GrowthHistoryModel.shared.resetHistory()
            try await ExclusionsModel.shared.reset()
            lifecycle.selection.endSession(); lifecycle.selection.execution.clear()
            await lifecycle.inspection.resetSession()
            lifecycle.planPresentation.reset()
            lifecycle.downloadsExplorer.openDownloads(); lifecycle.locationsExplorer.openLocations()
            lifecycle.workspaceNavigation.explorerVisible = false
            lifecycle.workspaceNavigation.planReturnsToExplorer = false
            snapshot = CleanupHistorySnapshot(records: [])
            message = "Still’s preferences, custom exclusions, selected locations and completed history were reset. Original files and macOS access grants are unchanged." + (result.1.completed ? "" : " Journal compaction did not finish; disk reclamation is not confirmed.")
            blocked = false
            return true
        } catch CleanupJournalError.recoveryRequired {
            blocked = true; message = "Reset is blocked by unfinished cleanup records. Open recovery review; no operations will resume automatically."
        } catch {
            blocked = true
            switch resetStage {
            case .journal:
                message = "Reset could not finish safely. The journal is unavailable; preferences are unchanged and some completed history may already be cleared. Review recovery before trying again."
            case .appearance:
                message = "Reset could not clear the appearance preference. The current appearance is retained; some completed history may already be cleared. Review recovery before trying again."
            case .remainingPreferences:
                message = "Reset could not finish safely. Appearance was reset to Automatic, but another preference service is unavailable; some completed history may already be cleared. Review recovery before trying again."
            }
        }
        return false
    }
}

struct CleanupHistoryView: View {
    @Bindable var model: CleanupHistoryModel
    @Binding var expandedRuns: Set<UUID>
    @Bindable private var scans = ScanActivityHistory.shared
    var showRecovery: () -> Void
    var manageLocalRecords: () -> Void
    var goOverview: () -> Void
    var viewPlan: () -> Void
    var showGrowth: ((UUID) -> Void)? = nil
    private var items: [HistoryActivityItem] {
        let scanItems: [HistoryActivityItem] = model.filter == .cleanups ? [] : (scans.records ?? []).map(HistoryActivityItem.scan)
        let cleanupItems: [HistoryActivityItem] = model.filter == .scans ? [] : (model.snapshot?.completedRuns ?? []).map(HistoryActivityItem.cleanup)
        let chromeItems: [HistoryActivityItem] = model.filter == .scans ? [] : (model.chromeRuns ?? []).map(HistoryActivityItem.chrome)
        return (scanItems + cleanupItems + chromeItems).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    private var unavailable: Bool {
        switch model.filter { case .all: scans.records == nil || model.snapshot == nil || model.chromeLoadError != nil; case .scans: scans.records == nil; case .cleanups: model.snapshot == nil || model.chromeLoadError != nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "History", subtitle: "Recorded scans and cleanup outcomes stored locally. Recovery facts are kept separately.")
            HistoryActivityFilterControl(selection: $model.filter)
            if let message = model.message {
                StatusRow(text: message, symbol: model.blocked ? "exclamationmark.triangle" : "info.circle", role: model.blocked ? .caution : .neutral, identifier: "historyStatus")
            }
            if let error = model.chromeLoadError { HistoryStoreFailure(message: error, retryTitle: "Try Chrome history again", enabled: !model.busy) { Task { await model.load() } } }
            ScanHistoryRecordingNotice()
            if let error = model.loadError {
                HistoryStoreFailure(message: error, retryTitle: "Try cleanup history again", enabled: !model.busy) { Task { await model.load() } }
            }
            if let error = scans.loadError {
                HistoryStoreFailure(message: error, retryTitle: "Try scan history again", enabled: !scans.isLoading) { Task { await scans.load() } }
            }
            if readingHistory { ProgressView("Reading local history…") }
            if model.blocked || (model.snapshot?.protectedRecordCount ?? 0) > 0 {
                SettingsRow(title: "Recovery facts are protected", detail: "Unfinished runs are excluded from Clear and retention. Reset requires them to be resolved.") {
                    Button("Open recovery review", action: showRecovery).accessibilityIdentifier("historyRecovery")
                }
            }
            if model.chromeRuns?.contains(where: \.unresolved) == true {
                StatusRow(text: "Unresolved Chrome cache outcomes are protected. Review their recorded group results below. They will not resume or retry automatically; Reset stays blocked.", symbol: "exclamationmark.triangle", role: .caution)
            }
            LocalRecordsEntry(action: manageLocalRecords)
            ForEach(items) { item in
                switch item {
                case .scan(let activity):
                    ScanActivitySummary(activity: activity, expanded: Binding(get: { model.expandedScans.contains(activity.id) }, set: { if $0 { model.expandedScans.insert(activity.id) } else { model.expandedScans.remove(activity.id) } }), showGrowth: showGrowth, growthReturn: model.growthReturn, growthFeedRevision: items.map(\.id))
                case .cleanup(let run): cleanup(run)
                case .chrome(let run):
                    SummarySurface {
                        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            Label("Chrome cache cleanup", systemImage: "globe").font(StillDesign.TypeStyle.section)
                            Text(run.observedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            ChromeResultsSection(result: run)
                        }
                    }
                }
            }
            if items.isEmpty {
                if readingHistory { EmptyView() }
                else if unavailable {
                    HistoryActivityUnavailableState()
                } else {
                    HistoryActivityEmptyState(filter: model.filter, goOverview: goOverview, viewPlan: viewPlan)
                }
            }
            HistoryRetentionNote()
        }.task { await reload() }
    }
    private var readingHistory: Bool {
        model.busy || scans.isLoading || (model.snapshot == nil && model.loadError == nil) || (scans.records == nil && scans.loadError == nil)
    }
    private func reload() async {
        async let cleanup: Void = model.load()
        async let scanRecords: Void = scans.load()
        _ = await (cleanup, scanRecords)
        guard !Task.isCancelled else { return }
        model.growthReturn.finishReload(revision: items.map(\.id))
    }
    private func cleanup(_ run: CleanupHistoryRun) -> some View {
                    SummarySurface {
                        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            Label("Cleanup run", systemImage: "checklist").font(StillDesign.TypeStyle.section)
                            Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(StillDesign.TypeStyle.section)
                            if run.usesApprovalDate { Text("Approval date shown; outcome time was not recorded by this version.").font(.caption).foregroundStyle(.secondary) }
                            Text("Recorded file results: \(run.records.count)").font(.callout)
                            Text("Planned logical size: " + bytes(run.plannedLogicalBytes)).font(.callout)
                            Text("Planned allocation retained in Trash: " + (run.trashHeldAllocatedBytes.map(bytes) ?? "Unknown"))
                            Text("Observed startup-volume capacity change: " + (run.capacity?.observedChange.map { ($0 >= 0 ? "+" : "−") + bytes(abs($0)) } ?? "Unknown"))
                            Text("Capacity samples are independent and can change for other reasons. Allocation is an estimate, not an exclusive-space promise.").font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Per-file results", isExpanded: Binding(
                                get: { expandedRuns.contains(run.id) },
                                set: { if $0 { expandedRuns.insert(run.id) } else { expandedRuns.remove(run.id) } }
                            )) {
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
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
}

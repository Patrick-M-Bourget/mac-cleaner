import AppKit
import Observation
import CacheDropCore
import SwiftUI

extension AppLifecycleController: HistoryMaintenanceLifecycle {
    var operationActive: Bool { operationInProgress || selection.workspaceRunning || updateInstallation.blocksNewWork }
    var maintenanceActive: Bool { get { maintenanceInProgress } set { maintenanceInProgress = newValue } }
}

enum HistoryActivityFilter: String, CaseIterable { case all = "All activity", scans = "Scans", cleanups = "Cleanups" }
private enum HistoryActivityItem: Identifiable {
    case scan(ScanActivity), cleanup(CleanupHistoryRun)
    var id: String { switch self { case .scan(let value): "scan-" + value.id.uuidString; case .cleanup(let value): "cleanup-" + value.id.uuidString } }
    var date: Date { switch self { case .scan(let value): value.completedAt; case .cleanup(let value): value.date } }
}

@MainActor @Observable final class CleanupHistoryModel {
    var filter = HistoryActivityFilter.all
    var expandedScans: Set<UUID> = []
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
                        let maintenance = try journal.retainCompletedRuns(maximumBytes: 250_000_000)
                        let compacted = maintenance.removedRecords == 0 ? true : try journal.compact().completed
                        return (try journal.completedHistory(), !compacted)
                    }
                    return (try reader.completedHistory(), false)
                }.value
            }
            snapshot = loaded.0; loadError = nil
            if loaded.1 { message = "Older history was removed, but CacheDrop couldn’t finish shrinking its history file." }
            blocked = false
        } catch {
            snapshot = nil; blocked = true
            loadError = "CacheDrop couldn’t read its cleanup history. Clear and Reset are off until it can."
        }
    }

    func clear() async {
        let lifecycle = AppLifecycleController.shared
        guard !busy, !lifecycle.updateInstallation.blocksNewWork, !lifecycle.maintenanceInProgress, !lifecycle.operationInProgress, !lifecycle.selection.workspaceRunning else { message = "Wait for the current cleanup to finish."; return }
        busy = true; defer { busy = false }
        lifecycle.maintenanceInProgress = true; defer { lifecycle.maintenanceInProgress = false }
        var clearedRuns: Int?
        var compactionCompleted = false
        do {
            let result = try await Task.detached {
                let journal = try CleanupJournalLocation.writer()
                let removed = try journal.clearCompletedRuns()
                // Compaction/readback cannot turn an already committed clear into an unknown count.
                let compacted = try? journal.compact()
                return (removed, compacted?.completed ?? false, try? journal.completedHistory())
            }.value
            clearedRuns = result.0.removedRuns; compactionCompleted = result.1
            snapshot = result.2
            if snapshot == nil { blocked = true; loadError = "CacheDrop couldn’t read its cleanup history. Clear and Reset are off until it can." }
            else { blocked = false; loadError = nil }
            try await StorageTrendsHistoryModel.shared.clearCompletedHistory()
            await ScanActivityHistory.shared.load(maintain: false)
            let noun = result.0.removedRuns == 1 ? "cleanup" : "cleanups"
            message = "History cleared: \(result.0.removedRuns) \(noun) and every scan." + compactionMessage(compactionCompleted)
        } catch {
            if let clearedRuns {
                let noun = clearedRuns == 1 ? "cleanup" : "cleanups"
                message = "Cleared \(clearedRuns) \(noun), but CacheDrop couldn’t confirm its scans were cleared." + compactionMessage(compactionCompleted)
            } else {
                message = "CacheDrop couldn’t confirm its cleanups were cleared, so its scans weren’t cleared either."
            }
        }
    }
    private func compactionMessage(_ completed: Bool) -> String {
        completed ? "" : " CacheDrop couldn’t shrink its history file yet."
    }
    func reset() async -> Bool {
        let lifecycle = AppLifecycleController.shared
        guard !busy, !lifecycle.updateInstallation.blocksNewWork, !lifecycle.maintenanceInProgress, !lifecycle.operationInProgress, !lifecycle.selection.workspaceRunning else { message = "Wait for the current scan or cleanup to finish, then reset."; return false }
        busy = true; lifecycle.maintenanceInProgress = true
        defer { busy = false; lifecycle.maintenanceInProgress = false }
        enum ResetStage { case journal, appearance, remainingPreferences }
        var resetStage = ResetStage.journal
        var downloadsClearedRuns: Int?
        do {
            // This check is deliberately inside the write transaction, never based on cached UI.
            let result = try await Task.detached {
                let journal = try CleanupJournalLocation.writer()
                let removed = try journal.clearCompletedRuns(requireNoRecovery: true)
                let compacted = try journal.compact()
                return (removed, compacted)
            }.value
            downloadsClearedRuns = result.0.removedRuns
            resetStage = .appearance
            try lifecycle.resetAppearancePreference()
            resetStage = .remainingPreferences
            try lifecycle.resetPreferences()
            try lifecycle.locations.reset()
            try await StorageTrendsHistoryModel.shared.resetHistory()
            try await ProtectedItemsModel.shared.reset()
            lifecycle.selection.endSession()
            await lifecycle.inspection.resetSession()
            lifecycle.planPresentation.reset()
            lifecycle.locationsExplorer.openLocations()
            lifecycle.workspaceNavigation.explorerVisible = false
            lifecycle.workspaceNavigation.planReturnsToExplorer = false
            snapshot = CleanupHistorySnapshot(records: [])
            message = "CacheDrop was reset: its settings, Protected items, chosen folders and history are gone. Your files and the access you gave in System Settings are unchanged." + (result.1.completed ? "" : " CacheDrop couldn’t shrink its history file yet.")
            blocked = false
            return true
        } catch CleanupJournalError.recoveryRequired {
            blocked = true; message = "Reset waits until the interrupted cleanup is reviewed."
        } catch {
            blocked = true
            switch resetStage {
            case .journal:
                message = "Reset couldn’t finish: CacheDrop couldn’t open its history. Your settings are unchanged, and some finished cleanups may already be cleared. Review any interrupted cleanup before you try again."
            case .appearance:
                message = "Reset couldn’t clear the appearance setting, so it stays as it is. Some finished cleanups may already be cleared. Review any interrupted cleanup before you try again."
            case .remainingPreferences:
                message = "Reset couldn’t finish: appearance went back to System, but other settings couldn’t be reset. Some finished cleanups may already be cleared. Review any interrupted cleanup before you try again."
            }
        }
        if let downloadsClearedRuns, downloadsClearedRuns > 0 {
            message = (message ?? "Reset didn’t finish.") + " Finished cleanups cleared: \(downloadsClearedRuns)."
        }
        return false
    }
}

struct CleanupHistoryView: View {
    @Bindable var model: CleanupHistoryModel
    @Binding var expandedRuns: Set<UUID>
    @Bindable private var scans = ScanActivityHistory.shared
    var showRecovery: () -> Void
    var goOverview: () -> Void
    private var items: [HistoryActivityItem] {
        let scanItems: [HistoryActivityItem] = model.filter == .cleanups ? [] : (scans.records ?? []).map(HistoryActivityItem.scan)
        let cleanupItems: [HistoryActivityItem] = model.filter == .scans ? [] : (model.snapshot?.completedRuns ?? []).map(HistoryActivityItem.cleanup)
        return (scanItems + cleanupItems).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    private var unavailable: Bool {
        switch model.filter { case .all: scans.records == nil || model.snapshot == nil; case .scans: scans.records == nil; case .cleanups: model.snapshot == nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            HStack(alignment: .firstTextBaseline) {
                PageHeader(title: "History")
                HistoryActivityFilterControl(selection: $model.filter)
            }
            if let message = model.message {
                StatusRow(text: message, symbol: model.blocked ? "exclamationmark.triangle" : "info.circle", role: model.blocked ? .caution : .neutral, identifier: "historyStatus")
            }
            ScanHistoryRecordingNotice()
            if let error = model.loadError {
                HistoryStoreFailure(message: error, retryTitle: "Try cleanup history again", enabled: !model.busy) { Task { await model.load() } }
            }
            if let error = scans.loadError {
                HistoryStoreFailure(message: error, retryTitle: "Try scan history again", enabled: !scans.isLoading) { Task { await scans.load() } }
            }
            // Nothing known yet: skeleton rows (#308).
            if readingHistory && items.isEmpty { SkeletonRows(.line, identifier: "historySkeleton") }
            if model.blocked || (model.snapshot?.protectedRecordCount ?? 0) > 0 {
                SettingsRow(title: "An interrupted cleanup needs review", detail: "History keeps it until you review it.") {
                    Button("Review interrupted cleanup", action: showRecovery).accessibilityIdentifier("historyRecovery")
                }
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .scan(let activity):
                            ScanActivitySummary(activity: activity, expanded: Binding(get: { model.expandedScans.contains(activity.id) }, set: { if $0 { model.expandedScans.insert(activity.id) } else { model.expandedScans.remove(activity.id) } }))
                        case .cleanup(let run): cleanup(run)
                        }
                        Divider()
                    }
                }
            } else if !readingHistory {
                if unavailable { HistoryActivityUnavailableState() }
                else { HistoryActivityEmptyState(filter: model.filter, goOverview: goOverview) }
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
    }
    private func cleanup(_ run: CleanupHistoryRun) -> some View {
        HistoryRow(symbol: run.isPreview ? "eye" : run.isPutBack ? "arrow.uturn.backward" : run.isEmptyFromTrash ? "xmark.bin" : "checklist", title: run.title, date: run.date,
                   size: SizeFormatter.text(run.headline.bytes), sizeNote: run.headline.note,
                   expanded: Binding(get: { expandedRuns.contains(run.id) }, set: { if $0 { expandedRuns.insert(run.id) } else { expandedRuns.remove(run.id) } }),
                   identifier: "cleanupRun:" + run.id.uuidString) {
            if run.usesApprovalDate { note("Shows when you started the cleanup; this version of CacheDrop didn’t record when it finished.") }
            if run.isPreview {
                note("Dry run · Nothing on disk changed. No space was freed.")
            } else if !run.isPutBack {
                if run.records.contains(where: { $0.cleanupAction == .trash }) {
                    note("In Trash until you empty it: " + SizeFormatter.text(run.trashHeldAllocatedBytes))
                }
                // The row leads with the measured freed space (#569); the estimate it's measured against is here, once.
                if !run.records.movedOnlyToTrash {
                    note("Estimated before cleanup: " + SizeFormatter.text(run.plannedBytes))
                }
            }
            ForEach(run.records) { record in
                HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.md) {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                        Text(record.originalURL.lastPathComponent + " · " + PathDisplay.shortLocation(of: record.originalURL.path))
                            .lineLimit(1).truncationMode(.middle).help(record.originalURL.path)
                        Text(record.outcomeLine + ((record.laterMeasurementText ?? record.settledText).map { " " + $0 } ?? "")).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).help("Action: " + record.actionTitle + (record.dryRun == true ? " · Dry run" : ""))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    let putBack = run.putBackIDs.contains(record.id) || TrashModel.shared.putBackOutcomes[record.id] == .restored(record.originalURL)
                    // Deleted from the Trash (#359): no Reveal in Trash and no Put back.
                    let emptied = run.emptiedIDs.contains(record.id) || TrashModel.shared.emptiedIDs.contains(record.id)
                    if let trash = record.trashURL, !putBack, !emptied, !record.isPutBack {
                        Button("Reveal in Trash") { Finder.reveal([trash]) }.buttonStyle(.link).help(trash.path)
                    }
                    if record.canPutBack, !emptied {
                        PutBackLink(record: record, alreadyPutBack: run.putBackIDs.contains(record.id)) { Task { await model.load(maintainCompleted: false) } }
                    }
                }
            }
        }
    }
    private func note(_ text: String) -> some View { Text(text).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

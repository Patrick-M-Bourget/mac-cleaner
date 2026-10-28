import SwiftUI

/// Both callers use the same maintenance presentation and the existing guarded model.
struct LocalRecordsEntry: View {
    var action: () -> Void
    var body: some View {
        SettingsRow(title: "Local records", detail: "Manage completed history and CacheDrop’s local settings.") {
            Button("Manage local records", action: action).accessibilityIdentifier("manageLocalRecords")
        }
    }
}

struct LocalRecordsView: View {
    @Bindable var model: CleanupHistoryModel
    @ObservedObject private var lifecycle = AppLifecycleController.shared
    @State private var confirmingClear = false
    @State private var confirmingReset = false
    var showRecovery: () -> Void
    var didReset: () -> Void
    /// The back button above the title, from the page that opened this one.
    var back: BackButton? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Local records", subtitle: "Manage what CacheDrop stores on this Mac. Original files and macOS access grants stay unchanged.", back: back)
            if let error = model.loadError { StatusRow(text: error, symbol: "exclamationmark.triangle", role: .caution) }
            if let message = model.message {
                StatusRow(text: message, symbol: model.blocked ? "exclamationmark.triangle" : "info.circle", role: model.blocked ? .caution : .neutral, identifier: "historyStatus")
            }
            if model.blocked || (model.snapshot?.protectedRecordCount ?? 0) > 0 {
                SettingsRow(title: "Recovery facts are protected", detail: "Unfinished runs are excluded from Clear and retention. Reset requires them to be resolved.") {
                    Button("Open recovery review", action: showRecovery).accessibilityIdentifier("localRecordsRecovery")
                }
            }
            LocalRecordsMaintenanceControls(enabled: !model.busy && !lifecycle.operationInProgress,
                clear: { confirmingClear = true }, reset: { confirmingReset = true })
        }
        .task { await model.load(maintainCompleted: false) }
        .confirmationDialog("Clear completed history?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear completed history", role: .destructive) { Task { await model.clear() } }
        } message: { Text("Scan activity, completed cleanup records and retained growth baselines will be removed, regardless of the History filter. Recovery facts, consumed approval IDs, current selections, appearance, original files and Trash contents remain.") }
        .confirmationDialog("Reset CacheDrop?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset CacheDrop", role: .destructive) { Task { if await model.reset() { didReset() } } }
        } message: { Text("Forget CacheDrop’s preferences, custom exclusions, selected locations and completed history; stop alerts and login launch. Original files, Trash and macOS access grants remain. Unfinished or unreadable journal records block reset.") }
    }
}

/// Pure presentation shared with inert Gallery examples. Maintenance stays in the model.
struct LocalRecordsMaintenanceControls: View {
    var enabled = true
    var clear: () -> Void
    var reset: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            SettingsRow(title: "Completed history", detail: "Remove scan activity, completed cleanup results and retained growth baselines together. Recovery facts, consumed approvals, current selections, appearance, original files and Trash remain.") {
                Button("Clear completed history…", action: clear).accessibilityIdentifier("clearHistory")
            }
            SettingsRow(title: "Reset CacheDrop", detail: "Forget preferences and selected locations, and stop alerts and login launch. Unfinished or unreadable recovery records block Reset.") {
                Button("Reset CacheDrop…", action: reset).accessibilityIdentifier("resetCacheDrop")
            }
        }.disabled(!enabled)
    }
}

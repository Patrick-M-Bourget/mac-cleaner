import SwiftUI

/// Both callers use the same maintenance presentation and the existing guarded model.
struct LocalRecordsEntry: View {
    var action: () -> Void
    var body: some View {
        SettingsRow(title: "Local records", detail: "Manage completed history and Still’s local settings.") {
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
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "Local records", subtitle: "Manage what Still stores on this Mac. Original files and macOS access grants stay unchanged.")
            if let message = model.message {
                StatusRow(text: message, symbol: model.blocked ? "exclamationmark.triangle" : "info.circle", role: model.blocked ? .caution : .neutral, identifier: "historyStatus")
            }
            if model.blocked || (model.snapshot?.protectedRecordCount ?? 0) > 0 {
                SettingsRow(title: "Recovery facts are protected", detail: "Unfinished runs are excluded from Clear and retention. Reset requires them to be resolved.") {
                    Button("Open recovery review", action: showRecovery).accessibilityIdentifier("localRecordsRecovery")
                }
            }
            SettingsRow(title: "Completed history", detail: "Remove completed per-file results and aggregate growth baselines. Recovery facts, consumed approvals, original files and Trash remain.") {
                Button("Clear completed runs…") { confirmingClear = true }.accessibilityIdentifier("clearHistory")
            }.disabled(model.busy || lifecycle.operationInProgress)
            SettingsRow(title: "Reset Still", detail: "Forget preferences and selected locations, and stop alerts and login launch. Unfinished or unreadable recovery records block Reset.") {
                Button("Reset Still…") { confirmingReset = true }.accessibilityIdentifier("resetStill")
            }.disabled(model.busy || lifecycle.operationInProgress)
        }
        .task { await model.load(maintainCompleted: false) }
        .confirmationDialog("Clear completed runs?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear completed runs", role: .destructive) { Task { await model.clear() } }
        } message: { Text("Completed per-file history and growth baselines will be removed. Recovery facts, consumed approval IDs, original files and Trash contents remain.") }
        .confirmationDialog("Reset Still?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Still", role: .destructive) { Task { if await model.reset() { didReset() } } }
        } message: { Text("Forget Still’s preferences, custom exclusions, selected locations and completed history; stop alerts and login launch. Original files, Trash and macOS access grants remain. Unfinished or unreadable journal records block reset.") }
    }
}

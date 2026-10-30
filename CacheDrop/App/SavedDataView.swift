import SwiftUI

/// Both callers use the same maintenance presentation and the existing guarded model.
struct SavedDataEntry: View {
    var action: () -> Void
    var body: some View {
        SettingsRow(title: "Saved data", detail: "Clear History, or reset CacheDrop’s settings.") {
            // A quiet link; the page's buttons are its own actions (#426).
            Button("Manage saved data", action: action).buttonStyle(.link).accessibilityIdentifier("manageLocalRecords")
        }
    }
}

struct SavedDataView: View {
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
            PageHeader(title: "Saved data", subtitle: "What CacheDrop keeps on this Mac. Your files and the access you gave in System Settings stay as they are.", back: back)
            if let error = model.loadError { StatusRow(text: error, symbol: "exclamationmark.triangle", role: .caution) }
            if let message = model.message {
                StatusRow(text: message, symbol: model.blocked ? "exclamationmark.triangle" : "info.circle", role: model.blocked ? .caution : .neutral, identifier: "historyStatus")
            }
            if model.blocked || (model.snapshot?.protectedRecordCount ?? 0) > 0 {
                SettingsRow(title: "An interrupted cleanup needs review", detail: "History keeps it until you review it.") {
                    Button("Review interrupted cleanup", action: showRecovery).accessibilityIdentifier("localRecordsRecovery")
                }
            }
            SavedDataMaintenanceControls(enabled: !model.busy && !lifecycle.operationInProgress,
                clear: { confirmingClear = true }, reset: { confirmingReset = true })
        }
        .task { await model.load(maintainCompleted: false) }
        .confirmationDialog("Clear completed history?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear completed history", role: .destructive) { Task { await model.clear() } }
        } message: { Text("Every scan and finished cleanup leaves History, whatever its filter shows, and Storage trends starts again. An interrupted cleanup, your selections, settings, files and the Trash stay.") }
        .confirmationDialog("Reset CacheDrop?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset CacheDrop", role: .destructive) { Task { if await model.reset() { didReset() } } }
        } message: { Text("CacheDrop forgets its settings, Protected items, chosen folders and history, and stops alerts and opening at login. Your files, the Trash and the access you gave in System Settings stay. You can’t reset while an interrupted cleanup needs review or History can’t be read.") }
    }
}

/// Pure presentation shared with inert Gallery examples. Maintenance stays in the model.
struct SavedDataMaintenanceControls: View {
    var enabled = true
    var clear: () -> Void
    var reset: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            SettingsRow(title: "Completed history", detail: "Remove every scan and finished cleanup from History; Storage trends starts again. An interrupted cleanup, your selections, settings, files and the Trash stay.") {
                Button("Clear completed history…", action: clear).accessibilityIdentifier("clearHistory")
            }
            SettingsRow(title: "Reset CacheDrop", detail: "Forget settings and chosen folders, and stop alerts and opening at login. Not possible while an interrupted cleanup needs review.") {
                Button("Reset CacheDrop…", action: reset).accessibilityIdentifier("resetCacheDrop")
            }
        }.disabled(!enabled)
    }
}

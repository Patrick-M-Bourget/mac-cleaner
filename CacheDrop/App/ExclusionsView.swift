import SwiftUI
import Observation
import CacheDropCore

@MainActor @Observable final class ExclusionsModel {
    static let shared = ExclusionsModel()
    private var store: ExclusionStore?
    private(set) var rules: [ExclusionRule] = []
    private(set) var busy = false
    private(set) var error: String?
    var preview: ExclusionRule?
    private func open() throws -> ExclusionStore {
        if let store { return store }
        let value = ExclusionStore(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Exclusions", isDirectory: true))
        store = value; return value
    }
    func policyForScan() async throws -> ExclusionPolicy {
        guard !busy else { throw CocoaError(.fileReadNoPermission) }
        do {
            let policy = try await open().policy()
            rules = policy.rules; error = nil
            return policy
        } catch {
            self.error = "CacheDrop couldn’t read your Protected items, so it can’t scan. Reopen CacheDrop, or reset it in Saved data."
            throw error
        }
    }
    func load() async {
        do { _ = try await policyForScan(); error = nil }
        catch { self.error = "CacheDrop couldn’t read your Protected items, so it can’t scan until it can. What’s always protected stays protected." }
    }
    var editingBlocked: Bool {
        busy || AppLifecycleController.shared.maintenanceInProgress || AppLifecycleController.shared.selection.workspaceRunning
    }
    func choose() async {
        guard !editingBlocked else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a file or folder for CacheDrop to leave out of its scans. Nothing is changed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { preview = try await Task.detached { try ExclusionRule.capture(url) }.value; error = nil }
        catch { self.error = "CacheDrop couldn’t check that item. Nothing was saved." }
    }
    func save() async {
        guard !editingBlocked, let preview else { return }
        busy = true; AppLifecycleController.shared.maintenanceInProgress = true
        defer { busy = false; AppLifecycleController.shared.maintenanceInProgress = false }
        do {
            let verified = try await Task.detached { try ExclusionRule.capture(URL(fileURLWithPath: preview.path)) }.value
            guard verified.path == preview.path, verified.volumeID == preview.volumeID, verified.boundary == preview.boundary else { throw CocoaError(.fileReadUnknown) }
            try await mutate { try await $0.add(preview) }
            self.preview = nil
        } catch { self.error = "CacheDrop couldn’t save it. Choose the item again; up to 100 items can be protected." }
    }
    func remove(_ rule: ExclusionRule) async {
        guard !editingBlocked else { return }
        busy = true; AppLifecycleController.shared.maintenanceInProgress = true
        defer { busy = false; AppLifecycleController.shared.maintenanceInProgress = false }
        do { try await mutate { try await $0.remove(rule.id) } }
        catch { self.error = "CacheDrop couldn’t remove it." }
    }
    private func mutate(_ operation: (ExclusionStore) async throws -> Void) async throws {
        let lifecycle = AppLifecycleController.shared
        lifecycle.inspection.cancel()
        lifecycle.selection.invalidateCoverage()
        try await GrowthHistoryModel.shared.invalidateCoverage()
        try await operation(open())
        let policy = try await open().policy()
        rules = policy.rules; error = nil
        lifecycle.selection.expectExclusions(policy.fingerprint)
        await lifecycle.inspection.invalidateCoverage()
        // What's protected now leaves every page by itself, as after a cleanup (Decision 58, #437); the rescan waits for
        // this change's maintenance lease to end.
        await lifecycle.selection.catalog.rescan()
    }
    /// Called only inside the history model's fresh recovery guard and maintenance lease.
    func reset() async throws {
        try await open().reset()
        rules = []; preview = nil; error = nil
        AppLifecycleController.shared.selection.expectExclusions("none")
    }
}

/// Locations & access's way to custom exclusions (#313).
struct ProtectedItemsEntry: View {
    var action: () -> Void
    var body: some View {
        SettingsRow(title: "Protected items", detail: "Files and folders CacheDrop leaves out of its scans.") {
            // A quiet link; the page's buttons are its own actions (#426).
            Button("Manage protected items", action: action).buttonStyle(.link).accessibilityIdentifier("openProtectedItems")
        }
    }
}

struct ExclusionsView: View {
    @Bindable var model: ExclusionsModel
    /// The back button above the title, from the page that opened this one.
    var back: BackButton? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Protected items", subtitle: "Files and folders CacheDrop leaves out of its scans. Unticking something in a plan never adds it here.", back: back)
            StatusRow(text: "A protected folder covers everything in it on the same disk. A renamed or moved item is no longer protected; anything saved at its old path is.", symbol: "folder.badge.minus")
            if let error = model.error { StatusRow(text: error, symbol: "exclamationmark.circle", role: .caution) }
            SettingsRow(title: "Always protected", detail: "System libraries, app packages, links and other disks, whatever is listed here.") { Label("Always on", systemImage: "lock") }
            if let preview = model.preview {
                SummarySurface {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                        Text("Protect this item?").font(CacheDropDesign.TypeStyle.section)
                        Text(preview.path).textSelection(.enabled)
                        Text(preview.boundary == .folder ? "This folder and everything in it" : "This file")
                        Text("Disk " + preview.volumeID).font(CacheDropDesign.TypeStyle.caption).textSelection(.enabled)
                        Text("After you save, scan again: what’s protected is left out and not counted.").font(.callout)
                    }
                }
            }
            if model.rules.isEmpty {
                EmptyState(title: "No protected items yet", detail: "Add a file or folder you want CacheDrop to leave out of its scans.", symbol: "folder")
            } else {
                ForEach(model.rules) { rule in
                    SettingsRow(title: rule.path, detail: (rule.boundary == .folder ? "Folder and everything in it" : "File") + " · disk " + rule.volumeID) {
                        Button("Remove") { Task { await model.remove(rule) } }.buttonStyle(.link).accessibilityLabel("Stop protecting " + rule.path)
                    }
                }
            }
            StatusRow(text: "After removing an item, scan again; what it holds starts unticked.", symbol: "arrow.clockwise")
        }.disabled(model.editingBlocked).task { await model.load() }
    }
}

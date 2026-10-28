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
            self.error = "Exclusion settings are unavailable. Scanning is blocked; review Protected items in Locations & access, or reset CacheDrop in Local records."
            throw error
        }
    }
    func load() async {
        do { _ = try await policyForScan(); error = nil }
        catch { self.error = "Exclusion settings could not be read. Scanning is blocked until these settings are available; fixed protections remain active." }
    }
    var editingBlocked: Bool {
        busy || AppLifecycleController.shared.maintenanceInProgress || AppLifecycleController.shared.selection.workspaceRunning
    }
    func choose() async {
        guard !editingBlocked else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Preview exclusion"
        panel.message = "Choose an exact file or folder. Review the rule before saving; no file will be changed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { preview = try await Task.detached { try ExclusionRule.capture(url) }.value; error = nil }
        catch { self.error = "The selected path and volume could not be verified. No rule was saved." }
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
        } catch { self.error = "The exclusion could not be saved. Re-select its location and volume; at most 100 custom rules can be stored. Existing findings require recheck." }
    }
    func remove(_ rule: ExclusionRule) async {
        guard !editingBlocked else { return }
        busy = true; AppLifecycleController.shared.maintenanceInProgress = true
        defer { busy = false; AppLifecycleController.shared.maintenanceInProgress = false }
        do { try await mutate { try await $0.remove(rule.id) } }
        catch { self.error = "The rule could not be removed. Existing findings require recheck." }
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
            Button("Manage protected items", action: action).accessibilityIdentifier("openProtectedItems")
        }
    }
}

struct ExclusionsView: View {
    @Bindable var model: ExclusionsModel
    /// The back button above the title, from the page that opened this one.
    var back: BackButton? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Custom exclusions", subtitle: "Keep exact paths out of explicit folder scans. Choosing an item in a cleanup plan never creates a rule.", back: back)
            StatusRow(text: "Folder rules cover descendants on the same volume. Renamed or moved items stop matching; replacements at the saved path remain excluded. Missing volumes leave rules dormant.", symbol: "folder.badge.minus")
            if let error = model.error { StatusRow(text: error, symbol: "exclamationmark.circle", role: .caution) }
            SettingsRow(title: "Fixed protections", detail: "Protected libraries, packages, symlinks and volume boundaries remain protected independently of custom rules.") { Label("Always active", systemImage: "lock") }
            if let preview = model.preview {
                SummarySurface {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                        Text("Preview exclusion").font(CacheDropDesign.TypeStyle.section)
                        Text(preview.path).textSelection(.enabled)
                        Text(preview.boundary == .folder ? "This folder and its descendants" : "This exact file path")
                        Text("Volume: " + preview.volumeID).font(CacheDropDesign.TypeStyle.caption).textSelection(.enabled)
                        Text("Saving invalidates current findings and approval. Selected choices remain pending until a complete recheck. Excluded bytes stay unknown.").font(.callout)
                    }
                }
            }
            if model.rules.isEmpty {
                EmptyState(title: "No custom exclusions", detail: "Add an explicit path rule when you want a file or folder omitted from scans. Fixed protections remain active.", symbol: "folder")
            } else {
                ForEach(model.rules) { rule in
                    SettingsRow(title: rule.path, detail: (rule.boundary == .folder ? "Folder and descendants" : "Exact file") + " · volume " + rule.volumeID) {
                        Button("Remove rule") { Task { await model.remove(rule) } }.accessibilityLabel("Remove exclusion for " + rule.path)
                    }
                }
            }
            StatusRow(text: "Removing a rule requires a new scan. Newly visible files start unchecked. These rules do not control independent developer-tool inventories.", symbol: "arrow.clockwise")
        }.disabled(model.editingBlocked).task { await model.load() }
    }
}

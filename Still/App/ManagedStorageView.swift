import AppKit
import Observation
import StillCore
import SwiftUI

@MainActor final class NativeManagedAppLauncher: ManagedApplicationLaunching {
    func open(identifiers: [String]) async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-managed-launcher"),
           let outcome = ProcessInfo.processInfo.environment["STILL_TEST_MANAGED_LAUNCH"] {
            return outcome == "opened"
        }
#endif
        for identifier in identifiers {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { continue }
            do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init()); return true }
            catch { continue }
        }
        return false
    }
}

@MainActor @Observable final class ManagedStorageModel {
    private let inventory = ManagedStorageInventory()
    private let launcher = NativeManagedAppLauncher()
    var rows: [ManagedStorageObservation] = []
    var category: ManagedStorageCategory = .deviceBackups
    var message: String?
    var inspecting = false
    var opening = false

    var guidance: ManagedStorageGuidance { ManagedStorageGuidance(category: category) }
    var selected: ManagedStorageObservation? { rows.first { $0.category == category } }
    func load() async { rows = await inventory.observations() }
    func chooseLocation() {
        guard category != .releaseArchives else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a managed location"
        panel.message = "Metadata only. Managed folders and library contents are protected and will not be traversed."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Inspect selected object"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let requestedCategory = category
        inspecting = true
        message = nil
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            await inventory.inspect(requestedCategory, selected: url)
            rows = await inventory.observations()
            inspecting = false
        }
    }
    func openOwner() async {
        let request = guidance
        opening = true
        defer { opening = false }
        switch await request.open(using: launcher) {
        case .opened: message = "Opened \(request.appName). Follow the instructions below in that app."
        case .unavailable: message = "\(request.appName) could not be opened. The instructions and Apple guide remain available."
        }
    }
}

struct ManagedStorageView: View {
    @Bindable var model: ManagedStorageModel
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            PageHeader(title: "App-managed storage")
            Text("Management guidance").foregroundStyle(.secondary)
            Text("Libraries and backups stay protected. Only explicitly selected object metadata is inspected; these rows never become cleanup targets or promised savings.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(model.rows) { row in
                Button {
                    model.category = row.category
                    model.message = nil
                } label: {
                    HStack(alignment: .top) {
                        CategoryBadge(category: .managed)
                        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                            Text(row.category.title).font(.headline).foregroundStyle(.primary)
                            Text(allocation(row.allocation)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: model.category == row.category ? "chevron.down" : "chevron.right").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, StillDesign.Space.sm).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Review \(row.category.title)")
                    .accessibilityValue(allocation(row.allocation))
                    .disabled(model.inspecting || model.opening)
                Divider()
            }
            if let selected = model.selected {
                SummarySurface {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    Text("\(selected.category.title) guidance").font(.title3.weight(.semibold))
                    Text(allocation(selected.allocation)).foregroundStyle(.secondary)
                    if selected.category == .releaseArchives {
                        ReleaseArchiveGuidance(guidance: model.guidance)
                    } else {
                        Text(selected.coverage).foregroundStyle(.secondary)
                    }
                    if let url = selected.selectedURL { Text(url.path).textSelection(.enabled).font(.caption) }
                    if let time = selected.observedAt { Text("Observed \(time.formatted())").font(.caption).foregroundStyle(.secondary) }
                    if selected.category != .releaseArchives {
                        Text(model.guidance.steps)
                        Text(model.guidance.consequence).font(.callout).foregroundStyle(.secondary)
                    }
                    if let message = model.message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("managedGuidanceStatus") }
                    HStack {
                        Button("Open \(model.guidance.appName)") { Task { await model.openOwner() } }
                            .disabled(model.inspecting || model.opening)
                        Link("Read Apple guidance", destination: model.guidance.supportURL)
                    }
                    if selected.category != .systemData && selected.category != .releaseArchives {
                        Button("Inspect selected location…") { model.chooseLocation() }.disabled(model.inspecting || model.opening)
                        Text("A selected regular file can have a measured allocation. Folders, packages and links remain uninspected; no recursive library size is invented.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.inspecting { ProgressView("Reading selected metadata…") }
                }
                }
            }
        }.task { await model.load() }
    }

    private func allocation(_ value: ManagedAllocation) -> String {
        switch value {
        case .measured(let bytes): "Measured selected object: \(bytes == 0 ? "0 bytes" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal))"
        case .unknown: "Unknown allocation"
        case .inaccessible: "Access unavailable"
        case .uninspected: "Not inspected"
        case .notIndependentlyEstimated: "Not independently estimated"
        }
    }
}

/// Shared, inert release-archive content; actions remain on the owning surface.
struct ReleaseArchiveGuidance: View {
    let guidance: ManagedStorageGuidance
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
            StatusRow(text: "Protected from Still cleanup", symbol: "lock", role: .neutral)
            Text(guidance.steps)
            Text(guidance.consequence).font(.callout).foregroundStyle(.secondary)
        }
    }
}

import AppKit
import Observation
import StillCore
import SwiftUI
import QuickLook

@MainActor @Observable
final class FolderInspection {
    private let scanner = FolderScanner()
    private let session: InspectionSession
    private let selection: SessionPlan
    init(selection: SessionPlan) { self.selection = selection; session = InspectionSession(scanner: scanner) }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var previewAccessScope: URL?
    private var refreshRequest: RefreshRequest?
    var scope: URL?
    var result: ScanResult?
    var lastComplete: ScanResult?
    var scopeReports: [ScopeReport] = []
    var selected: FileObservation?
    var isScanning = false
    var message: String?
    var previewURL: URL?

    static func chooseFolder() -> URL? {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.treatsFilePackagesAsDirectories = false
        picker.message = "Inspect metadata in the folder you choose. No cleanup will run."
        picker.prompt = "Scan folder"
        return picker.runModal() == .OK ? picker.url : nil
    }

    func scan(_ url: URL) {
        cancel()
        let previousSelection = scope?.standardizedFileURL == url.standardizedFileURL ? selected : nil
        let sameScope = scope?.standardizedFileURL == url.standardizedFileURL
        let request = selection.beginRefresh(url)
        refreshRequest = request
        let token = UUID()
        generation = token
        scope = url
        if !sameScope { result = nil; selected = nil; lastComplete = nil }
        message = nil
        isScanning = true
        task = Task {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let report = try await session.inspect(url)
                let observed = report.current
                let reports = await session.reports()
                guard !Task.isCancelled, token == generation else { return }
                await selection.finishRefresh(request, scan: observed)
                guard !Task.isCancelled, token == generation else { return }
                refreshRequest = nil
                result = observed
                selection.observe(observed)
                lastComplete = report.lastComplete
                scopeReports = reports
                selected = previousSelection.flatMap { old in observed.observations.first { $0.id == old.id && $0.resourceID == old.resourceID } } ?? observed.observations.first
                isScanning = false
            } catch {
                guard token == generation else { return }
                selection.cancelRefresh(request)
                refreshRequest = nil
                isScanning = false
                message = error is CancellationError ? "Scan stopped. Choose a folder to try again." : "This folder could not be inspected. Choose the folder again or check access in System Settings."
            }
        }
    }

    func show(_ report: ScopeReport) {
        guard !isScanning else { return }
        scope = report.current.scope; result = report.current; lastComplete = report.lastComplete
        selected = report.current.observations.first; message = nil
    }

    func cancel() {
        task?.cancel()
        generation = UUID()
        if let refreshRequest { selection.cancelRefresh(refreshRequest); self.refreshRequest = nil }
        if isScanning { message = "Scan stopped. Selected choices need a complete refresh before review." }
        isScanning = false
    }

    func preview(_ item: FileObservation) {
        closePreviewAccess()
        if let scope, scope.startAccessingSecurityScopedResource() { previewAccessScope = scope }
        task = Task {
            do { previewURL = try await scanner.previewURL(for: item) }
            catch {
                closePreviewAccess()
                message = "Preview unavailable: local contents or resource identity could not be confirmed. No download was requested."
            }
        }
    }

    func closePreviewAccess() {
        previewAccessScope?.stopAccessingSecurityScopedResource()
        previewAccessScope = nil
    }

    func reveal(_ item: FileObservation) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}

struct FolderInspectionView: View {
    @Bindable var model: FolderInspection
    @Bindable var selection: SessionPlan
    let viewPlan: () -> Void
    @State private var search = ""
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            Text("Folder inspection").font(.largeTitle.weight(.semibold))
            if let scope = model.scope { Text(scope.path).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("Recheck folder") { if let scope = model.scope { model.scan(scope) } }.disabled(model.isScanning)
                Button("Choose folder again…") { if let url = FolderInspection.chooseFolder() { model.scan(url) } }.disabled(model.isScanning)
            }
            if model.scopeReports.count > 1 {
                Text("Selected locations").font(.headline)
                ForEach(model.scopeReports, id: \.current.scope) { report in
                    Button(report.current.scope.lastPathComponent + (report.requiresRecheck ? " · Recheck required" : " · Observed")) { model.show(report) }
                        .disabled(model.isScanning)
                }
            }
            if model.isScanning {
                ProgressView("Reading file metadata… Previous observations remain visible until this refresh completes.")
                Button("Stop scan") { model.cancel() }
            }
            if let message = model.message { Text(message).foregroundStyle(.secondary) }
            if let result = model.result {
                HStack {
                    Text("Observed").font(.caption).foregroundStyle(.secondary)
                    Text(result.observedAt, format: .dateTime.year().month().day().hour().minute().second()).font(.caption)
                }
                Text(result.isComplete ? "Scan completed within the selected scope" : "Partial coverage · \(result.issues.count) unreadable or bounded locations")
                    .font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Complete scope logical bytes: \(bytes(result.totalLogicalBytes))")
                    if (!result.isComplete || result.hasUnmeasuredContents) && !result.observations.isEmpty { Text("Known observed logical subtotal: \(bytes(result.logicalBytes)) · Remaining bytes unknown") }
                    Text("Complete scope allocated bytes: \(bytes(result.totalAllocatedBytes))")
                    if result.allocatedUnknownCount > 0 { Text("\(result.allocatedUnknownCount) file allocation measurements unknown") }
                    Text("Selected volume capacity: \(bytes(result.volumeCapacityBytes))")
                    Text("Selected volume available (\(result.volumeAvailableMetric)): \(bytes(result.volumeAvailableBytes))")
                }.font(.callout).monospacedDigit()
                Text("File totals count hardlinked identities once. Package contents and linked folders are not scanned. Allocations are not exclusive reclaimable space.")
                    .font(.caption).foregroundStyle(.secondary)
                CloudInventoryView(report: result.cloudInventory)
                Divider()
                if !result.isComplete {
                    Text("Uninspected bytes: Unknown · Recheck required before cleanup can be considered.").foregroundStyle(.secondary)
                    if let previous = model.lastComplete {
                        Text("Last complete observation: \(previous.observedAt.formatted()) · Historical, not current coverage.").font(.caption).foregroundStyle(.secondary)
                    } else { Text("No previous complete observation for this location.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.url.path).textSelection(.enabled)
                            Text(issue.reason.rawValue + " · " + issue.recovery).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if result.observations.isEmpty { Text(result.isComplete ? "No entries observed in this folder." : "No readable entries observed; this is not an empty-folder result.").foregroundStyle(.secondary) }
                TextField("Search inspected files", text: $search)
                LazyVStack(spacing: 0) {
                    ForEach(result.observations.filter { search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search) }) { item in
                        Button { model.selected = item } label: {
                            HStack(alignment: .top) {
                                Image(systemName: item.kind == .file ? "doc" : "folder")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.url.lastPathComponent).foregroundStyle(.primary)
                                    Text(relative(item.url, to: result.scope)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.kind == .file ? bytes(item.logicalBytes) : item.kind.rawValue).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Inspect \(item.url.lastPathComponent)")
                        if selection.eligible(item, in: result) {
                            Toggle("Select \(item.url.lastPathComponent)", isOn: Binding(get: { selection.draft.contains(item) }, set: { selection.set(item, in: result, selected: $0) }))
                        } else { Text("Browse only · outside eligible Downloads or protected/unknown target").font(.caption).foregroundStyle(.secondary) }
                        Divider()
                    }
                }
                if let item = model.selected {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.url.lastPathComponent).font(.headline)
                        Text(item.url.path).textSelection(.enabled)
                        Text("Logical size: \(bytes(item.logicalBytes))")
                        Text("Allocated size: \(bytes(item.allocatedBytes))")
                        if item.isDuplicateResource { Text("Same resource as another path; counted once in totals.") }
                        if item.kind == .package { Text("Protected package · contents not inspected.") }
                        if item.kind == .symbolicLink { Text("Symbolic link · target not inspected.") }
                        if item.previewAvailability != .local {
                            Text("Preview unavailable: local contents are \(item.previewAvailability.rawValue). No download will be requested.")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Quick Look") { model.preview(item) }
                                .disabled(item.kind != .file || item.previewAvailability != .local)
                            Button("Reveal in Finder") { model.reveal(item) }
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                }
                Text("\(selection.draft.selectedCount) files selected").accessibilityIdentifier("inspectionSelectionSummary")
                Button("View cleanup plan", action: viewPlan).buttonStyle(.borderedProminent)
            }
        }.quickLookPreview($model.previewURL)
            .onChange(of: model.previewURL) { _, url in if url == nil { model.closePreviewAccess() } }
            .onDisappear { model.previewURL = nil; model.closePreviewAccess() }
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value else { return "Unknown" }
        return value < 1_000 ? "\(value) bytes" : ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
    private func relative(_ url: URL, to root: URL) -> String {
        url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
    }
}

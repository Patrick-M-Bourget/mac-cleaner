import AppKit
import Observation
import StillCore
import SwiftUI
import QuickLook

@MainActor @Observable
final class FolderInspection {
    private let scanner = FolderScanner()
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var previewAccessScope: URL?
    var scope: URL?
    var result: ScanResult?
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
        task?.cancel()
        let token = UUID()
        generation = token
        scope = url
        result = nil
        selected = nil
        message = nil
        isScanning = true
        task = Task {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let observed = try await scanner.scan(url)
                guard !Task.isCancelled, token == generation else { return }
                result = observed
                selected = observed.observations.first
                isScanning = false
            } catch {
                guard token == generation else { return }
                isScanning = false
                message = error is CancellationError ? "Scan stopped. Choose a folder to try again." : "This folder could not be inspected. Choose the folder again or check access in System Settings."
            }
        }
    }

    func cancel() { task?.cancel() }

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
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            Text("Folder inspection").font(.largeTitle.weight(.semibold))
            if let scope = model.scope { Text(scope.path).foregroundStyle(.secondary).textSelection(.enabled) }
            if model.isScanning {
                ProgressView("Reading file metadata…")
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
                    Text("Logical file bytes: \(bytes(result.logicalBytes))")
                    Text("Allocated file bytes: \(bytes(result.allocatedBytes))")
                    if result.allocatedUnknownCount > 0 { Text("\(result.allocatedUnknownCount) file allocation measurements unknown") }
                    Text("Selected volume capacity: \(bytes(result.volumeCapacityBytes))")
                    Text("Selected volume available (important usage): \(bytes(result.volumeAvailableBytes))")
                }.font(.callout).monospacedDigit()
                Text("File totals count hardlinked identities once. Package contents and linked folders are not scanned. Allocations are not exclusive reclaimable space.")
                    .font(.caption).foregroundStyle(.secondary)
                CloudInventoryView(report: result.cloudInventory)
                Divider()
                if result.observations.isEmpty { Text("No entries observed in this folder.").foregroundStyle(.secondary) }
                LazyVStack(spacing: 0) {
                    ForEach(result.observations) { item in
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

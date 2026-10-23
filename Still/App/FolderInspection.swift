import Darwin
import AppKit
import Observation
import StillCore
import SwiftUI
import QuickLook

@MainActor @Observable
final class FolderInspection {
    private let scanner: FolderScanner
    private let session: InspectionSession
    private let selection: SessionPlan
    init(selection: SessionPlan) {
        self.selection = selection
        #if DEBUG
        scanner = FolderScanner(supplement: RefreshFixtureMetadata())
        #else
        scanner = FolderScanner()
        #endif
        session = InspectionSession(scanner: scanner)
    }
    private var task: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var generation = UUID()
    private var cancellation: ScanCancellation?
    var progress: ScanProgress?
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
        guard !AppLifecycleController.shared.maintenanceInProgress else { return }
        guard !selection.execution.isRunning else { return }
        cancel()
        previewURL = nil
        closePreviewAccess()
        let previousSelection = scope?.standardizedFileURL == url.standardizedFileURL ? selected : nil
        let sameScope = scope?.standardizedFileURL == url.standardizedFileURL
        let request = selection.beginRefresh(url)
        refreshRequest = request
        let scanCancellation = ScanCancellation()
        cancellation = scanCancellation
        progress = nil
        let token = UUID()
        generation = token
        scope = url
        if !sameScope { result = nil; selected = nil; lastComplete = nil }
        message = nil
        isScanning = true
        task = Task {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let (updates, continuation) = AsyncStream<ScanProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let receiver = Task { [weak self] in
                for await update in updates {
                    guard let self, token == self.generation, !Task.isCancelled else { return }
                    self.progress = update
                }
            }
            defer { continuation.finish(); receiver.cancel() }
            do {
                let growthToken = await GrowthHistoryModel.shared.begin(url)
                let report = try await session.inspect(url, cancellation: scanCancellation, onProgress: { continuation.yield($0) })
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
                progress = nil
                isScanning = false
                await GrowthHistoryModel.shared.complete(observed, token: growthToken)
            } catch {
                guard token == generation else { return }
                selection.cancelRefresh(request)
                refreshRequest = nil
                progress = nil
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

    func resetSession() async {
        cancel(); closePreviewAccess()
        scope = nil; result = nil; lastComplete = nil; scopeReports = []; selected = nil; previewURL = nil; message = nil
        await session.clear()
    }
    func cancel() {
        if isScanning { GrowthHistoryModel.shared.cancelled() }
        cancellation?.cancel()
        task?.cancel()
        generation = UUID()
        if let refreshRequest { selection.cancelRefresh(refreshRequest); self.refreshRequest = nil }
        if isScanning { message = "Stop requested. The current metadata operation may still return; selected choices need a complete refresh before review." }
        progress = nil
        isScanning = false
    }

    func preview(_ item: FileObservation) {
        closePreviewAccess()
        if let scope, scope.startAccessingSecurityScopedResource() { previewAccessScope = scope }
        let token = UUID(); previewGeneration = token
        previewTask = Task {
            do {
                let local = try await scanner.previewURL(for: item)
                guard !Task.isCancelled, previewGeneration == token else { return }
                previewURL = local
            }
            catch {
                guard previewGeneration == token else { return }
                closePreviewAccess()
                message = "Preview unavailable: local contents or resource identity could not be confirmed. No download was requested."
            }
        }
    }

    func closePreviewAccess() {
        previewTask?.cancel()
        previewGeneration = UUID()
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
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            PageHeader(title: "Folder inspection", subtitle: "Inspect names and evidence. Checkboxes update your live cleanup plan.")
            if let scope = model.scope { Text(scope.path).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("Recheck folder") { if let scope = model.scope { model.scan(scope) } }.disabled(model.isScanning)
                Button("Choose folder again…") { if let url = FolderInspection.chooseFolder() { selection.leaveRetryMode(); model.scan(url) } }.disabled(model.isScanning)
            }
            if model.scopeReports.count > 1 {
                Text("Selected locations").font(.headline)
                ForEach(model.scopeReports, id: \.current.scope) { report in
                    Button(report.current.scope.lastPathComponent + (report.requiresRecheck ? " · Recheck required" : " · Observed")) { model.show(report) }
                        .disabled(model.isScanning)
                }
            }
            if model.isScanning {
                if let progress = model.progress {
                    ScanProgressSummary(inspectedEntries: progress.visitedEntries,
                        logicalSubtotal: bytes(progress.knownLogicalSubtotal),
                        recentNames: progress.recentObservations.prefix(5).map { $0.url.lastPathComponent },
                        phaseMessage: progress.phase == .rechecking ? "Rechecking changed coverage (one attempt)…" : progress.phase == .checkingDirectories ? "Checking directory stability…" : "Reading file metadata…")
                } else { ProgressView("Reading file metadata…") }
                if model.result != nil { StatusRow(text: "Previous observations remain visible while this location is rechecked.", symbol: "clock") }
            }
            if let message = model.message { StatusRow(text: message, symbol: "info.circle") }
            if let result = model.result {
                HStack {
                    Text("Observed").font(.caption).foregroundStyle(.secondary)
                    Text(result.observedAt, format: .dateTime.year().month().day().hour().minute().second()).font(.caption)
                }
                StatusRow(text: result.isComplete ? "Scan completed within the selected scope" : "Partial coverage · \(result.issues.count) unreadable or bounded locations", symbol: result.isComplete ? "checkmark.circle" : "exclamationmark.circle", role: result.isComplete ? .success : .caution)
                VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                    Text("Complete scope logical bytes: \(bytes(result.totalLogicalBytes))")
                    if (!result.isComplete || result.hasUnmeasuredContents) && !result.observations.isEmpty { Text("Known observed logical subtotal: \(bytes(result.logicalBytes)) · Remaining bytes unknown") }
                    Text("Complete scope allocated bytes: \(bytes(result.totalAllocatedBytes))")
                    if result.allocatedUnknownCount > 0 { Text("\(result.allocatedUnknownCount) file allocation measurements unknown") }
                }.font(.callout).monospacedDigit()
                Divider()
                if !result.isComplete {
                    Text("Uninspected bytes: Unknown · Recheck required before cleanup can be considered.").foregroundStyle(.secondary)
                    if let previous = model.lastComplete {
                        Text("Last complete observation: \(previous.observedAt.formatted()) · Historical, not current coverage.").font(.caption).foregroundStyle(.secondary)
                    } else { Text("No previous complete observation for this location.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(result.issues.prefix(20).enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                            Text(issue.url.path).textSelection(.enabled)
                            Text((issue.reason == .directoryChanged ? "Directory changed during scanning" : issue.reason == .timeLimit ? "Scan time budget reached" : issue.reason.rawValue) + " · " + issue.recovery).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if result.issues.count > 20 { Text("\(result.issues.count - 20) additional coverage issues. Choose a smaller scope to inspect affected areas.").font(.caption).foregroundStyle(.secondary) }
                if result.observations.isEmpty { Text(result.isComplete ? "No entries observed in this folder." : "No readable entries observed; this is not an empty-folder result.").foregroundStyle(.secondary) }
                TextField("Search inspected files", text: $search)
                LazyVStack(spacing: 0) {
                    ForEach(result.observations.filter { search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search) }) { item in
                        InspectableItemRow(name: item.url.lastPathComponent, detail: relative(item.url, to: result.scope), size: item.kind == .file ? bytes(item.logicalBytes) : item.kind.rawValue, symbol: item.kind == .file ? "doc" : "folder", inspected: model.selected?.id == item.id, inspect: { model.selected = item }) {
                            if selection.eligible(item, in: result) {
                                Toggle("Select \(item.url.lastPathComponent)", isOn: Binding(get: { selection.draft.contains(item) }, set: { selection.set(item, in: result, selected: $0) })).labelsHidden().disabled(selection.isPreparing || selection.execution.isRunning || (model.isScanning && !selection.draft.contains(item)))
                            } else {
                                Image(systemName: "lock").foregroundStyle(.secondary).help("Browse only · outside eligible Downloads or protected/unknown target").accessibilityLabel("Browse only · protected or ineligible target")
                            }
                        }
                        Divider()
                    }
                }
                if let item = model.selected {
                    SummarySurface {
                    VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                        Text(item.url.lastPathComponent).font(StillDesign.TypeStyle.section)
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
                    }
                    }
                }
                DisclosureGroup("Volume and size details") {
                    VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                        Text("Selected volume capacity: \(bytes(result.volumeCapacityBytes))")
                        Text("Selected volume available (\(result.volumeAvailableMetric)): \(bytes(result.volumeAvailableBytes))")
                        Text("File totals count hardlinked identities once. Package contents and linked folders are not scanned. Allocations are not exclusive reclaimable space.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                CloudInventoryView(report: result.cloudInventory)
                Text("\(StillDesign.files(selection.draft.selectedCount)) selected").accessibilityIdentifier("inspectionSelectionSummary")

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

#if DEBUG
/// Controlled latency at the public metadata boundary, only for explicitly picked disposable UI fixtures.
private struct RefreshFixtureMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-slow-refresh"),
           let path = ProcessInfo.processInfo.environment["STILL_TEST_DOWNLOADS_ROOT"] {
            let root = URL(fileURLWithPath: path).standardizedFileURL
            if root.lastPathComponent.hasPrefix("StillSelectionUI-"), url.standardizedFileURL.pathComponents.starts(with: root.pathComponents) {
                Thread.sleep(forTimeInterval: 0.02)
                if ProcessInfo.processInfo.arguments.contains("--ui-test-directory-instability"), url.lastPathComponent == "trigger.txt", Self.isBoundOwnedTemporaryRoot(root) {
                    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: root.path)
                }
            }
        }
        return try FoundationMetadataSupplement().read(url)
    }
    private static func isBoundOwnedTemporaryRoot(_ root: URL) -> Bool {
        let prefix = "StillSelectionUI-"
        guard root.lastPathComponent.hasPrefix(prefix), UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
              root.path == root.resolvingSymlinksInPath().path,
              let expected = ProcessInfo.processInfo.environment["STILL_TEST_DOWNLOADS_ID"] else { return false }
        let runner = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.patrickbourget.StillUITests.xctrunner/Data/tmp")
        let parents = [runner, FileManager.default.temporaryDirectory, URL(fileURLWithPath: "/private/tmp")].map { $0.resolvingSymlinksInPath().path }
        var info = stat()
        return parents.contains(root.deletingLastPathComponent().path) && lstat(root.path, &info) == 0
            && info.st_mode & S_IFMT == S_IFDIR && info.st_uid == geteuid() && "\(info.st_dev):\(info.st_ino)" == expected
    }
}
#endif

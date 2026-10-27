import Darwin
import AppKit
import Observation
import CacheDropCore
import SwiftUI
import QuickLook

@MainActor @Observable
final class FolderInspection {
    private let scanner: FolderScanner
    private let session: InspectionSession
    private let selection: SessionPlan
    init(selection: SessionPlan) {
        self.selection = selection
        scanner = FolderScanner()
        session = InspectionSession(scanner: scanner)
    }
    private var task: Task<Void, Never>?
    private var scanAgainTask: Task<Void, Never>?
    private var scanAgainGeneration = UUID()
    private var batchRequests: [RefreshRequest] = []
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var generation = UUID()
    private var cancellation: ScanCancellation?
    var progress: ScanProgress?
    private var previewAccessScope: URL?
    private var previewLease: ScopeAccessLease?
    private var refreshRequest: RefreshRequest?
    private var activity: ActiveScanActivity?
    var scope: URL?
    var result: ScanResult?
    var lastComplete: ScanResult?
    var scopeReports: [ScopeReport] = []
    var selected: FileObservation?
    private var isScanningCurrent = false
    var isScanning: Bool { isScanningCurrent || scanAgainTask != nil }
    var message: String? { didSet { unavailableScope = nil } }
    /// The location the current message says is unavailable, so Overview can leave it to that location's recovery row (#231).
    private(set) var unavailableScope: URL?
    var previewURL: URL?

    static func chooseFolder(downloads: Bool = false, remembering: Bool = false) -> URL? {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.treatsFilePackagesAsDirectories = false
        picker.message = "Scans inspect metadata only. Cleanup choices come from the cleanup plan."
        if downloads { picker.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }
        picker.prompt = remembering ? "Remember folder" : "Scan folder"
        if remembering { picker.message = "Choose the same folder again to renew access." }
        return picker.runModal() == .OK ? picker.url : nil
    }

    func scan(_ url: URL) {
        guard !AppLifecycleController.shared.operationInProgress, !AppLifecycleController.shared.maintenanceInProgress else { return }
        guard !selection.workspaceRunning else { return }
        cancel()
        startScan(url)
    }

    /// Refresh the existing explicit scopes without replacing live choices or choosing a new scope.
    func scanAgain(scopes explicitScopes: [URL]? = nil, leases: [ScopeAccessLease] = [], unavailable: [URL] = []) {
        guard !AppLifecycleController.shared.operationInProgress, !AppLifecycleController.shared.maintenanceInProgress, !selection.workspaceRunning, !isScanning else { return }
        let focusedScope = scope?.standardizedFileURL
        let roots = Set((explicitScopes ?? (scopeReports.map { $0.current.scope } + selection.refreshScopes + [scope].compactMap { $0 })).map(\.standardizedFileURL)).sorted { $0.path < $1.path }
        guard !roots.isEmpty || !unavailable.isEmpty else { return }
        cancel()
        let token = UUID()
        scanAgainGeneration = token
        batchRequests = selection.beginRefreshBatch(roots)
        scanAgainTask = Task {
            defer { for lease in leases { lease.close() } }
            let epoch = await ScanActivityHistory.shared.begin()
            guard !Task.isCancelled, token == scanAgainGeneration else { return }
            let operation = ActiveScanActivity(roots: Array(Set(roots + unavailable)).sorted { $0.path < $1.path }, epoch: epoch)
            for root in unavailable { operation.failed(root) }
            activity = operation
            for root in roots {
                guard !Task.isCancelled, token == scanAgainGeneration else { return }
                startScan(root, grouped: true)
                await task?.value
                guard !Task.isCancelled, token == scanAgainGeneration else { return }
                if message != nil {
                    selection.endRefreshBatch(batchRequests)
                    batchRequests = []
                    scanAgainTask = nil
                    await finishActivity()
                    AppLifecycleController.shared.capacity.request(.scanEnded)
                    return
                }
                batchRequests.removeAll { $0.scope == root.standardizedFileURL }
            }
            selection.endRefreshBatch(batchRequests)
            batchRequests = []
            scanAgainTask = nil
            await finishActivity()
            AppLifecycleController.shared.capacity.request(.scanEnded)
            if let focusedScope, !selection.unavailableScopes.contains(focusedScope), let report = scopeReports.first(where: { $0.current.scope.standardizedFileURL == focusedScope }) { show(report) }
        }
    }

    private func startScan(_ url: URL, grouped: Bool = false) {
        cancelCurrentScan()
        previewURL = nil
        closePreviewAccess()
        let previousSelection = scope?.standardizedFileURL == url.standardizedFileURL ? selected : nil
        let sameScope = scope?.standardizedFileURL == url.standardizedFileURL
        var request = selection.beginRefresh(url)
        refreshRequest = request
        let scanCancellation = ScanCancellation()
        cancellation = scanCancellation
        progress = nil
        let token = UUID()
        generation = token
        scope = url
        if !sameScope { result = nil; selected = nil; lastComplete = nil }
        message = nil
        isScanningCurrent = true
        task = Task {
            if !grouped {
                let epoch = await ScanActivityHistory.shared.begin()
                guard !Task.isCancelled, token == generation else { return }
                activity = ActiveScanActivity(roots: [url.standardizedFileURL], epoch: epoch)
            }
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
                let policy = try await ExclusionsModel.shared.policyForScan()
                guard !Task.isCancelled, token == generation else { return }
                selection.expectExclusions(policy.fingerprint)
                request = selection.beginRefresh(url)
                refreshRequest = request
                let report = try await session.inspect(url, cancellation: scanCancellation, onProgress: { continuation.yield($0) }, exclusions: policy)
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
                isScanningCurrent = false
                if scanAgainTask == nil { AppLifecycleController.shared.capacity.request(.scanEnded) }
                activity?.observe(observed, baselineID: nil)
                // Large and old files are listed for the explorer once the scan shows; nothing is chosen.
                await selection.catalog.showPickedFiles(observed)
                if !grouped { await finishActivity() }
            } catch {
                guard token == generation else { return }
                selection.cancelRefresh(request)
                refreshRequest = nil
                progress = nil
                isScanningCurrent = false
                message = error is CancellationError ? "Scan stopped. Choose a folder to try again." : ExclusionsModel.shared.error ?? "This folder could not be inspected. Choose the folder again or check access in System Settings."
                activity?.failed(url)
                if !grouped { await finishActivity() }
                if scanAgainTask == nil { AppLifecycleController.shared.capacity.request(.scanEnded) }
            }
        }
    }

    private func finishActivity() async {
        guard let operation = activity else { return }
        activity = nil
        await ScanActivityHistory.shared.record(operation.summary(), epoch: operation.epoch)
    }

    /// Overview projects current included evidence; omitting a scope never keeps it as current.
    func overviewObservation(including scopes: [URL], observations: [URL: ScanResult], unavailable: Set<URL>) -> ScanResult? {
        let included = Set(scopes.map { $0.standardizedFileURL.path })
        let invalid = Set(unavailable.map { $0.standardizedFileURL.path })
        if let scope, included.contains(scope.standardizedFileURL.path) {
            return invalid.contains(scope.standardizedFileURL.path) ? nil : result
        }
        return observations.values.filter { included.contains($0.scope.standardizedFileURL.path) && !invalid.contains($0.scope.standardizedFileURL.path) }
            .max { $0.observedAt < $1.observedAt }
    }

    static let unavailableMessage = "Current coverage: Unknown · This location is unavailable. Reconnect and recheck, or choose it again in Locations & access."
    func markUnavailable(_ url: URL) {
        scope = url
        let previous = scopeReports.first { $0.current.scope.path == url.path }
        lastComplete = previous?.lastComplete ?? previous.flatMap { $0.current.isComplete ? $0.current : nil }
        result = nil; selected = nil
        message = Self.unavailableMessage
        unavailableScope = url.standardizedFileURL
    }

    func show(_ report: ScopeReport) {
        showObserved(report.current, lastComplete: report.lastComplete)
    }
    /// Focus the exact shared observation used by a recommendation, including a newer retry recheck.
    func showObserved(_ scan: ScanResult) {
        let historical = scopeReports.first { $0.current.scope.standardizedFileURL == scan.scope.standardizedFileURL }?.lastComplete
        showObserved(scan, lastComplete: scan.isComplete ? scan : historical)
    }
    private func showObserved(_ scan: ScanResult, lastComplete historical: ScanResult?) {
        guard !isScanning else { return }
        scope = scan.scope; result = scan; lastComplete = historical
        selected = scan.observations.first; message = nil
    }

    func invalidateCoverage() async {
        cancel(); closePreviewAccess()
        result = nil; lastComplete = nil; scopeReports = []; selected = nil; previewURL = nil
        message = "Exclusion settings changed. Recheck this folder to observe the new coverage."
        await session.clear()
    }
    func resetSession() async {
        cancel(); closePreviewAccess()
        scope = nil; result = nil; lastComplete = nil; scopeReports = []; selected = nil; previewURL = nil; message = nil
        await session.clear()
    }
    func cancel() {
        let hadLogicalScan = isScanning
        if let operation = activity {
            if isScanningCurrent { operation.stopped(scope, progress: progress) }
            let summary = operation.summary(stopped: true)
            activity = nil
            Task { await ScanActivityHistory.shared.record(summary, epoch: operation.epoch) }
        }
        scanAgainGeneration = UUID()
        scanAgainTask?.cancel(); scanAgainTask = nil
        selection.endRefreshBatch(batchRequests)
        batchRequests = []
        cancelCurrentScan()
        if hadLogicalScan { AppLifecycleController.shared.capacity.request(.scanEnded) }
    }
    private func cancelCurrentScan() {
        cancellation?.cancel()
        task?.cancel()
        generation = UUID()
        if let refreshRequest { selection.cancelRefresh(refreshRequest); self.refreshRequest = nil }
        if isScanningCurrent { message = "Stop requested. The current metadata operation may still return; selected choices need a complete refresh before review." }
        progress = nil
        isScanningCurrent = false
    }

    func preview(_ item: FileObservation) {
        closePreviewAccess()
        if let scope {
            do { previewLease = try AppLifecycleController.shared.locations.leases(for: [scope]).first }
            catch { message = "Renew access to this location before previewing. No download was requested."; return }
        }
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
        previewLease?.close(); previewLease = nil
    }

    func reveal(_ item: FileObservation) {
        Finder.reveal([item.url])
    }
}

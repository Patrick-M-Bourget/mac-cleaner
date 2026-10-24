import AppKit
import Observation
import QuickLook
import StillCore
import SwiftUI

/// Process-local browsing state. It contains no restored scan or cleanup authority.
@MainActor @Observable final class StorageExplorerContext {
    struct Position {
        var folder: URL?
        var query = ""
        var inspectedID: String?
        var inspectedResource: String?
        var offset = CGPoint.zero
    }
    var allowedScopes: Set<URL>?
    var downloadsScopes: Set<URL>?
    var downloadsOnly = false
    var position = Position()
    private var history: [Position] = []
    var canGoBack: Bool { !history.isEmpty }
    var navigationID = UUID()
    func openDownloads() { reset(downloadsOnly: true, folder: nil) }
    func openLocations() { reset(downloadsOnly: false, folder: nil) }
    func openLocation(_ url: URL) { reset(downloadsOnly: false, folder: url.standardizedFileURL) }
    private func reset(downloadsOnly: Bool, folder: URL?) {
        self.downloadsOnly = downloadsOnly; position = Position(folder: folder); history = []; navigationID = UUID()
    }
    func enter(_ url: URL) {
        history.append(position); position = Position(folder: url.standardizedFileURL); navigationID = UUID()
    }
    @discardableResult func backWithinExplorer() -> Bool {
        guard let previous = history.popLast() else { return false }
        position = previous; navigationID = UUID(); return true
    }
    func returnToRoot() {
        guard position.folder != nil else { return }
        history.append(position); position = Position(); navigationID = UUID()
    }
    func discardUnavailableFolder() {
        position = Position(); history = []; navigationID = UUID()
    }
    func inspect(_ item: FileObservation) {
        position.inspectedID = item.id; position.inspectedResource = item.resourceID
    }
    func clearInspector() { position.inspectedID = nil; position.inspectedResource = nil }
}

/// A read-only evidence snapshot: overlap, scope membership and totals share one owner.
/// It uses supplied observations only and never reads filesystem metadata.
private struct StorageExplorerObservations {
    struct Entry: Identifiable {
        let item: FileObservation
        let scan: ScanResult
        var id: String { item.id + "|" + item.resourceID }
    }
    struct Subtotal {
        let bytes: Int64
        let hasUnknownRemainder: Bool
    }
    let scans: [ScanResult]
    let entries: [Entry]
    init(scans selected: [URL: ScanResult], reports: [ScanResult], allowedScopes: Set<URL>?,
         downloadsOnly: Bool, downloadsScopes: Set<URL>?, observedDownloadsScopes: Set<URL>,
         configuredDownloads: URL?, eligible: (FileObservation, ScanResult) -> Bool) {
        var latest = selected
        for scan in reports {
            if latest[scan.scope].map({ $0.observedAt < scan.observedAt }) ?? true { latest[scan.scope] = scan }
        }
        scans = latest.values.filter { scan in
            (allowedScopes?.contains(scan.scope.standardizedFileURL) ?? true) && (!downloadsOnly || downloadsScopes?.contains(scan.scope.standardizedFileURL) == true || observedDownloadsScopes.contains(scan.scope.standardizedFileURL)
                || configuredDownloads.map { scan.scope.standardizedFileURL.pathComponents.starts(with: $0.pathComponents) } == true)
        }.sorted { $0.scope.path < $1.scope.path }
        var representatives: [String: Entry] = [:]
        for scan in scans.sorted(by: { $0.observedAt > $1.observedAt }) {
            for item in scan.observations {
                let entry = Entry(item: item, scan: scan)
                if let existing = representatives[entry.id] {
                    // One failed overlapping location must not suppress independent valid evidence.
                    if !eligible(existing.item, existing.scan), eligible(item, scan) { representatives[entry.id] = entry }
                } else { representatives[entry.id] = entry }
            }
        }
        entries = representatives.values.sorted { left, right in
            if (left.item.kind == .folder) != (right.item.kind == .folder) { return left.item.kind == .folder }
            return left.item.url.path.localizedStandardCompare(right.item.url.path) == .orderedAscending
        }
    }
    func overlaps(_ scope: URL) -> Bool {
        scans.contains { $0.scope != scope && ($0.scope.pathComponents.starts(with: scope.pathComponents) || scope.pathComponents.starts(with: $0.scope.pathComponents)) }
    }
    func subtotal(in folder: URL, logical: Bool) -> Subtotal {
        let children = entries.filter { $0.item.url != folder && $0.item.url.pathComponents.starts(with: folder.pathComponents) }
        var seen = Set<String>(); var total: Int64 = 0; var unknown = false
        for entry in children where entry.item.kind != .folder && seen.insert(entry.item.resourceID).inserted {
            guard entry.item.kind == .file, let size = (logical ? entry.item.logicalBytes : entry.item.allocatedBytes) else { unknown = true; continue }
            let sum = total.addingReportingOverflow(size)
            if sum.overflow { unknown = true } else { total = sum.partialValue }
        }
        let partial = scans.contains { scan in
            let related = folder.pathComponents.starts(with: scan.scope.pathComponents) || scan.scope.pathComponents.starts(with: folder.pathComponents)
            return (related && scan.excludedEntryCount > 0) || scan.issues.contains {
                $0.url.pathComponents.starts(with: folder.pathComponents) || folder.pathComponents.starts(with: $0.url.pathComponents)
            }
        }
        return Subtotal(bytes: total, hasUnknownRemainder: unknown || partial)
    }
}

/// Browses observed metadata only. The workspace supplies its fixed sibling action strip.
struct StorageExplorerView: View {
    @Bindable var model: FolderInspection
    @Bindable var selection: SessionPlan
    @Bindable var context: StorageExplorerContext
    let backTitle: String
    let back: () -> Void
    private typealias Entry = StorageExplorerObservations.Entry
    private var observations: StorageExplorerObservations {
        StorageExplorerObservations(scans: selection.scans, reports: model.scopeReports.map(\.current),
            allowedScopes: context.allowedScopes, downloadsOnly: context.downloadsOnly,
            downloadsScopes: context.downloadsScopes,
            observedDownloadsScopes: Set(selection.overviewDownloadRows.map { $0.scan.scope.standardizedFileURL }),
            configuredDownloads: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL,
            eligible: { selection.eligible($0, in: $1) })
    }
    private var scans: [ScanResult] { observations.scans }
    private var entries: [Entry] { observations.entries }
    private var folderAvailable: Bool {
        guard let folder = context.position.folder else { return true }
        return scans.contains { $0.scope.standardizedFileURL == folder }
            || entries.contains { $0.item.url.standardizedFileURL == folder && $0.item.kind == .folder }
    }
    private var visible: [Entry] {
        guard folderAvailable, let folder = context.position.folder else { return [] }
        let descendants = entries.filter { $0.item.url != folder && $0.item.url.pathComponents.starts(with: folder.pathComponents) }
        if context.position.query.isEmpty { return descendants.filter { $0.item.url.deletingLastPathComponent().standardizedFileURL == folder } }
        return descendants.filter { relative($0.item.url, to: folder).localizedCaseInsensitiveContains(context.position.query) }
    }
    private var inspected: Entry? {
        guard let id = context.position.inspectedID, let resource = context.position.inspectedResource,
              folderAvailable, context.position.query.isEmpty || !visible.isEmpty else { return nil }
        return entries.first { $0.item.id == id && $0.item.resourceID == resource }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 800
            VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
                Button(context.canGoBack ? "Back to previous folder" : backTitle, systemImage: "chevron.left") {
                    if !context.backWithinExplorer() { back() }
                }.accessibilityIdentifier("explorerBack")
                PageHeader(title: context.downloadsOnly ? "Explore Downloads" : "Explore storage", subtitle: "Browse existing observations. On disk sizes are allocation evidence, not reclaimable space.")
                breadcrumbs
                HStack(alignment: .top, spacing: StillDesign.Space.lg) {
                    list.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide, let entry = inspected { inspector(entry).frame(width: 280) }
                }.frame(maxHeight: .infinity)
                if !wide, let entry = inspected {
                    inspector(entry).frame(maxHeight: min(220, geometry.size.height * 0.35))
                }
            }.padding(StillDesign.Space.page)
        }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.previewURL) { _, value in if value == nil { model.closePreviewAccess() } }
        .onChange(of: entries.map(\.id)) { _, _ in
            if context.position.inspectedID != nil && inspected == nil { context.clearInspector() }
        }
        .onDisappear { model.previewURL = nil; model.closePreviewAccess() }
    }
    private var breadcrumbs: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            HStack {
                Button(context.downloadsOnly ? "Scanned Downloads locations" : "Selected locations") { context.returnToRoot() }
                if folderAvailable, let folder = context.position.folder {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    ForEach(breadcrumbs(for: folder), id: \.self) { ancestor in
                        Button(ancestor.lastPathComponent) { if ancestor != folder { context.enter(ancestor) } }
                            .lineLimit(1).help(ancestor.path)
                        if ancestor != folder { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if folderAvailable, let folder = context.position.folder {
                Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                TextField("Search scanned descendants", text: $context.position.query)
                    .accessibilityIdentifier("explorerSearch")
                Text("Search covers this folder and its scanned descendants only.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ExplorerViewport(context: context).frame(height: 0)
                if context.position.folder == nil {
                    if scans.isEmpty { EmptyState(title: "No scanned locations", detail: "Run a manual scan from Cleanup plan or Overview. Browsing never starts a scan.", symbol: "folder") }
                    ForEach(scans, id: \.scope) { scan in
                        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                            Button(scan.scope.lastPathComponent, systemImage: "folder") { context.enter(scan.scope) }
                                .accessibilityLabel("Open folder " + scan.scope.lastPathComponent)
                            Text(scan.scope.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(scan.totalAllocatedBytes.map { "On disk: " + bytes($0) } ?? "On disk: Unknown · observed subtotal " + bytes(scan.allocatedBytes)).font(.callout)
                            Text(scan.isComplete ? "Observed coverage" : "Partial coverage · uninspected bytes unknown").font(.caption).foregroundStyle(.secondary)
                            if observations.overlaps(scan.scope) {
                                Text("Overlaps another selected location · totals are not additive").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(StillDesign.Space.md)
                        Divider()
                    }
                } else if !folderAvailable {
                    EmptyState(title: "This folder is no longer available in the observations", detail: "Its location may have been omitted, forgotten or changed during a refresh. Browsing cannot scan or restore access.", symbol: "folder.badge.questionmark")
                    Button("Return to selected locations") { context.discardUnavailableFolder() }
                } else if visible.isEmpty {
                    EmptyState(title: context.position.query.isEmpty ? "No observed entries here" : "No matches", detail: context.position.query.isEmpty ? "This describes existing observations only. Unscanned or unavailable contents remain unknown." : "No observed descendants match this search. Your selected files are unchanged.", symbol: "magnifyingglass")
                    if !context.position.query.isEmpty { Button("Clear search") { context.position.query = "" } }
                } else {
                    ForEach(visible) { entry in row(entry); Divider() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("explorerList")
    }
    private func row(_ entry: Entry) -> some View {
        let item = entry.item
        return HStack(spacing: StillDesign.Space.md) {
            if selection.eligible(item, in: entry.scan) || selection.draft.contains(item) {
                Toggle("Select " + item.url.lastPathComponent, isOn: Binding(get: { selection.draft.contains(item) }, set: { selection.set(item, in: entry.scan, selected: $0) }))
                    .labelsHidden().disabled(selection.isPreparing || selection.execution.isRunning || ((model.isScanning || selection.isRefreshing) && !selection.draft.contains(item)))
            } else { Image(systemName: item.kind == .folder ? "folder" : "lock").foregroundStyle(.secondary).frame(width: 20).accessibilityLabel("Browse only") }
            Button {
                if item.kind == .folder { context.enter(item.url) } else { context.inspect(item) }
            } label: {
                VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                    Text(item.url.lastPathComponent).foregroundStyle(.primary)
                    if let folder = context.position.folder, !context.position.query.isEmpty { Text(relative(item.url, to: folder)).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel((item.kind == .folder ? "Open folder " : "Inspect ") + item.url.lastPathComponent)
            Text(item.kind == .folder ? folderAllocation(item.url) : bytes(item.allocatedBytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
            if item.kind == .folder {
                Button { context.inspect(item) } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).accessibilityLabel("Inspect " + item.url.lastPathComponent)
            }
        }.padding(StillDesign.Space.md)
            .background(context.position.inspectedID == item.id && context.position.inspectedResource == item.resourceID ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
    }
    private func inspector(_ entry: Entry) -> some View {
        ExplorerInspector(name: entry.item.url.lastPathComponent, close: { context.clearInspector() }) {
            inspectorField("Location", entry.item.url.path)
            inspectorField("Observed scope", entry.scan.scope.path)
            inspectorField("Observed", entry.scan.observedAt.formatted(date: .abbreviated, time: .shortened))
            inspectorField("Why listed", "Observed during your manual scan of this location. Browsing uses saved metadata only.")
            Text("On disk: " + (entry.item.kind == .folder ? folderAllocation(entry.item.url) : bytes(entry.item.allocatedBytes)))
            Text("Logical size: " + (entry.item.kind == .folder ? folderSubtotal(entry.item.url, logical: true) : bytes(entry.item.logicalBytes)))
            inspectorField("Cleanup action", selection.inspectionRestriction(entry.item, in: entry.scan) ?? "Move this exact file to Trash after selection and confirmation.")
            if selection.inspectionRestriction(entry.item, in: entry.scan) == nil {
                Text("Selection is separate from inspection. Fresh checks run before review and execution; this observation is not a safety guarantee.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Observed allocation is not reclaimable space. Trash may retain storage until emptied.").font(.caption).foregroundStyle(.secondary)
            if entry.item.isDuplicateResource { Text("Shared resource · allocation counts once within a total.") }
            if entry.item.kind == .package || entry.item.kind == .symbolicLink { Text("Protected boundary · contents not inspected.") }
            if entry.item.previewAvailability != .local { Text("Local contents are " + entry.item.previewAvailability.rawValue + ". Preview will not request a download.") }
            HStack {
                Button("Quick Look") { model.showObserved(entry.scan); model.preview(entry.item) }.disabled(entry.item.kind != .file || entry.item.previewAvailability != .local || model.isScanning)
                Button("Reveal in Finder") { model.reveal(entry.item) }
            }
        }
    }
    private func inspectorField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
    private func folderAllocation(_ folder: URL) -> String { folderSubtotal(folder, logical: false) }
    private func folderSubtotal(_ folder: URL, logical: Bool) -> String {
        let subtotal = observations.subtotal(in: folder, logical: logical)
        return bytes(subtotal.bytes) + (subtotal.hasUnknownRemainder ? " observed · remaining unknown" : " observed")
    }

    private func breadcrumbs(for folder: URL) -> [URL] {
        guard let root = scans.map(\.scope).filter({ folder.pathComponents.starts(with: $0.pathComponents) }).min(by: { $0.pathComponents.count < $1.pathComponents.count }) else { return [folder] }
        var result = [root]
        for component in folder.pathComponents.dropFirst(root.pathComponents.count) { result.append(result.last!.appendingPathComponent(component)) }
        return result
    }
    private func bytes(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "Unknown" }
    private func relative(_ url: URL, to root: URL) -> String { url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/") }
}

/// Shared bounded inspector surface: the host chooses a side pane or compact panel.
struct ExplorerInspector<Content: View>: View {
    let name: String
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                HStack { Text(name).font(StillDesign.TypeStyle.section).lineLimit(2); Spacer(); Button("Close inspector", systemImage: "xmark", action: close).labelStyle(.iconOnly) }
                ScrollView {
                    VStack(alignment: .leading, spacing: StillDesign.Space.sm) { content() }
                        // Selectable native text extends its accessibility frame beyond
                        // its glyph origin; keep that frame inside the scroll viewport.
                        .padding(.horizontal, StillDesign.Space.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("inspectorEvidenceScroll")
            }
        }.accessibilityIdentifier("explorerInspector")
    }
}

/// Native viewport restoration is navigation-only; checkbox updates never scroll the list.
private struct ExplorerViewport: NSViewRepresentable {
    let context: StorageExplorerContext
    func makeNSView(context: Context) -> ViewportView { ViewportView() }
    func updateNSView(_ view: ViewportView, context: Context) { view.configure(self.context) }
    @MainActor final class ViewportView: NSView {
        private weak var clip: NSClipView?
        private weak var browsing: StorageExplorerContext?
        private var navigationID: UUID?
        func configure(_ browsing: StorageExplorerContext) {
            self.browsing = browsing
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        private func attach() {
            guard let browsing, let scroll = enclosingScrollView else { return }
            if clip !== scroll.contentView {
                NotificationCenter.default.removeObserver(self)
                clip = scroll.contentView; clip?.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: clip)
            }
            if navigationID != browsing.navigationID {
                navigationID = browsing.navigationID
                clip?.scroll(to: browsing.position.offset); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        @objc private func boundsChanged() {
            guard let browsing, navigationID == browsing.navigationID else { return }
            browsing.position.offset = clip?.bounds.origin ?? .zero
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

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
    func inspect(_ item: FileObservation) {
        position.inspectedID = item.id; position.inspectedResource = item.resourceID
    }
    func clearInspector() { position.inspectedID = nil; position.inspectedResource = nil }
}

/// Browses observed metadata only. The workspace supplies its fixed sibling action strip.
struct StorageExplorerView: View {
    @Bindable var model: FolderInspection
    @Bindable var selection: SessionPlan
    @Bindable var context: StorageExplorerContext
    let backTitle: String
    let back: () -> Void
    private struct Entry: Identifiable {
        let item: FileObservation
        let scan: ScanResult
        var id: String { item.id + "|" + item.resourceID }
    }
    private var scans: [ScanResult] {
        var latest = selection.scans
        for report in model.scopeReports {
            let scan = report.current
            if latest[scan.scope].map({ $0.observedAt < scan.observedAt }) ?? true { latest[scan.scope] = scan }
        }
        let downloadsScopes = Set(selection.overviewDownloadRows.map { $0.scan.scope.standardizedFileURL })
        let configured = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL
        return latest.values.filter { scan in
            (context.allowedScopes?.contains(scan.scope.standardizedFileURL) ?? true) && (!context.downloadsOnly || context.downloadsScopes?.contains(scan.scope.standardizedFileURL) == true || downloadsScopes.contains(scan.scope.standardizedFileURL)
                || configured.map { scan.scope.standardizedFileURL.pathComponents.starts(with: $0.pathComponents) } == true)
        }.sorted { $0.scope.path < $1.scope.path }
    }
    private var entries: [Entry] {
        var seen = Set<String>()
        return scans.sorted { $0.observedAt > $1.observedAt }.flatMap { scan in
            scan.observations.compactMap { item -> Entry? in
                let key = item.id + "|" + item.resourceID
                return seen.insert(key).inserted ? Entry(item: item, scan: scan) : nil
            }
        }.sorted { left, right in
            if (left.item.kind == .folder) != (right.item.kind == .folder) { return left.item.kind == .folder }
            return left.item.url.path.localizedStandardCompare(right.item.url.path) == .orderedAscending
        }
    }
    private var visible: [Entry] {
        guard let folder = context.position.folder else { return [] }
        let descendants = entries.filter { $0.item.url != folder && $0.item.url.pathComponents.starts(with: folder.pathComponents) }
        if context.position.query.isEmpty { return descendants.filter { $0.item.url.deletingLastPathComponent().standardizedFileURL == folder } }
        return descendants.filter { relative($0.item.url, to: folder).localizedCaseInsensitiveContains(context.position.query) }
    }
    private var inspected: Entry? {
        guard context.position.query.isEmpty || !visible.isEmpty else { return nil }
        return entries.first { $0.item.id == context.position.inspectedID && $0.item.resourceID == context.position.inspectedResource }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 880
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
                if let folder = context.position.folder {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    ForEach(breadcrumbs(for: folder), id: \.self) { ancestor in
                        Button(ancestor.lastPathComponent) { if ancestor != folder { context.enter(ancestor) } }
                            .lineLimit(1).help(ancestor.path)
                        if ancestor != folder { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if let folder = context.position.folder {
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
                            if scans.contains(where: { $0.scope != scan.scope && ($0.scope.pathComponents.starts(with: scan.scope.pathComponents) || scan.scope.pathComponents.starts(with: $0.scope.pathComponents)) }) {
                                Text("Overlaps another selected location · totals are not additive").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(StillDesign.Space.md)
                        Divider()
                    }
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
            .background(inspected?.id == entry.id ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
    }
    private func inspector(_ entry: Entry) -> some View {
        ExplorerInspector(name: entry.item.url.lastPathComponent, close: { context.clearInspector() }) {
            Text(entry.item.url.path).font(.caption).textSelection(.enabled)
            Text("On disk: " + (entry.item.kind == .folder ? folderAllocation(entry.item.url) : bytes(entry.item.allocatedBytes)))
            Text("Logical size: " + (entry.item.kind == .folder ? folderSubtotal(entry.item.url, logical: true) : bytes(entry.item.logicalBytes)))
            if entry.item.isDuplicateResource { Text("Shared resource · allocation counts once within a total.") }
            if entry.item.kind == .package || entry.item.kind == .symbolicLink { Text("Protected boundary · contents not inspected.") }
            if entry.item.previewAvailability != .local { Text("Local contents are " + entry.item.previewAvailability.rawValue + ". Preview will not request a download.") }
            HStack {
                Button("Quick Look") { model.showObserved(entry.scan); model.preview(entry.item) }.disabled(entry.item.kind != .file || entry.item.previewAvailability != .local || model.isScanning)
                Button("Reveal in Finder") { model.reveal(entry.item) }
            }
        }
    }
    private func folderAllocation(_ folder: URL) -> String { folderSubtotal(folder, logical: false) }
    private func folderSubtotal(_ folder: URL, logical: Bool) -> String {
        let children = entries.filter { $0.item.url != folder && $0.item.url.pathComponents.starts(with: folder.pathComponents) }
        var seen = Set<String>(); var total: Int64 = 0; var unknown = false
        for entry in children where entry.item.kind != .folder && seen.insert(entry.item.resourceID).inserted {
            guard entry.item.kind == .file, let size = (logical ? entry.item.logicalBytes : entry.item.allocatedBytes) else { unknown = true; continue }
            let sum = total.addingReportingOverflow(size)
            if sum.overflow { unknown = true } else { total = sum.partialValue }
        }
        let partial = scans.contains { scan in scan.issues.contains { $0.url.pathComponents.starts(with: folder.pathComponents) } }
        return bytes(total) + (unknown || partial ? " observed · remaining unknown" : " observed")
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
            ScrollView {
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    HStack { Text(name).font(StillDesign.TypeStyle.section); Spacer(); Button("Close inspector", systemImage: "xmark", action: close).labelStyle(.iconOnly) }
                    content()
                }.frame(maxWidth: .infinity, alignment: .leading)
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

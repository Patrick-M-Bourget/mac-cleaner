import AppKit
import Observation
import QuickLook
import CacheDropCore
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
    /// Lists the large and old files offered from picked folders instead of the folder's contents.
    var showsLargeAndOld = false
    enum FileOrder: String, CaseIterable, Identifiable { case size = "Largest first", lastUsed = "Oldest first"; var id: Self { self } }
    var fileOrder = FileOrder.size
    var position = Position()
    private var history: [Position] = []
    var canGoBack: Bool { !history.isEmpty }
    /// Where back leads inside the explorer: the previous folder, or the list of locations; nil when back leaves it.
    var backDestination: String? {
        guard let previous = history.last else { return nil }
        return previous.folder?.lastPathComponent ?? (downloadsOnly ? "Scanned Downloads locations" : "Selected locations")
    }
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
    /// The page the explorer was opened from, which back returns to.
    let caller: String
    let back: () -> Void
    private typealias Entry = StorageExplorerObservations.Entry
    private var observations: StorageExplorerObservations {
        StorageExplorerObservations(scans: selection.scans, reports: model.scopeReports.map(\.current),
            allowedScopes: context.allowedScopes, downloadsOnly: context.downloadsOnly,
            downloadsScopes: context.downloadsScopes,
            observedDownloadsScopes: [],
            configuredDownloads: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL,
            eligible: { _, _ in false })
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
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    BackButton(destination: context.backDestination ?? caller) {
                        if !context.backWithinExplorer() { back() }
                    }.accessibilityIdentifier("explorerBack")
                    PageHeader(title: context.downloadsOnly ? "Explore Downloads" : "Explore storage", subtitle: "Inspect local allocations within your selected folders.")
                }
                ScanHistoryRecordingNotice()
                breadcrumbs
                HStack(alignment: .top, spacing: CacheDropDesign.Space.lg) {
                    list.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide, let entry = inspected { inspector(entry).frame(width: 280) }
                }.frame(maxHeight: .infinity)
                if !wide, let entry = inspected {
                    inspector(entry).frame(maxHeight: min(220, geometry.size.height * 0.35))
                }
            }.padding(CacheDropDesign.Space.page)
        }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.previewURL) { _, value in if value == nil { model.closePreviewAccess() } }
        .onChange(of: entries.map(\.id)) { _, _ in
            if context.position.inspectedID != nil && inspected == nil { context.clearInspector() }
        }
        .onDisappear { model.previewURL = nil; model.closePreviewAccess() }
    }
    private var breadcrumbs: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            HStack {
                Button(context.downloadsOnly ? "Scanned Downloads locations" : "Selected locations") { context.returnToRoot() }
                if folderAvailable, let folder = context.position.folder {
                    Image(systemName: "chevron.right").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    ForEach(breadcrumbs(for: folder), id: \.self) { ancestor in
                        Button(ancestor.lastPathComponent) { if ancestor != folder { context.enter(ancestor) } }
                            .lineLimit(1).help(ancestor.path)
                        if ancestor != folder { Image(systemName: "chevron.right").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if folderAvailable, let folder = context.position.folder {
                TextField("Search this folder", text: $context.position.query).help(folder.path)
                    .accessibilityIdentifier("explorerSearch")
            }
            if !selection.catalog.pickedByResource.isEmpty && !context.downloadsOnly {
                HStack {
                    Picker("Show", selection: $context.showsLargeAndOld) {
                        Text("Folders").tag(false)
                        Text("Large and old files").tag(true)
                    }.pickerStyle(.segmented).fixedSize().accessibilityIdentifier("explorerMode")
                    if context.showsLargeAndOld {
                        Picker("Sort", selection: $context.fileOrder) {
                            ForEach(StorageExplorerContext.FileOrder.allCases) { Text($0.rawValue).tag($0) }
                        }.fixedSize().accessibilityIdentifier("explorerFileOrder")
                    }
                }
            }
        }
    }
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ExplorerViewport(context: context).frame(height: 0)
                if showsLargeAndOld {
                    largeAndOldFiles
                } else if context.position.folder == nil {
                    if scans.isEmpty { EmptyState(title: "No scanned folders", detail: "Use Scan a folder on Overview to choose one. Browsing never starts a scan.", symbol: "folder") }
                    ForEach(scans, id: \.scope) { scan in
                        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                            Button(scan.scope.lastPathComponent, systemImage: "folder") { context.enter(scan.scope) }
                                .accessibilityLabel("Open folder " + scan.scope.lastPathComponent).help(scan.scope.path)
                            // One short line: the size, then only the caveats that apply.
                            Text(([scan.totalAllocatedBytes.map { bytes($0) + " on disk" } ?? "At least " + bytes(scan.allocatedBytes) + " on disk",
                                   scan.isComplete ? nil : "Partial coverage",
                                   observations.overlaps(scan.scope) ? "Overlaps another location" : nil] as [String?]).compactMap { $0 }.joined(separator: " · "))
                                .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        }.padding(CacheDropDesign.Space.md)
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
        return HStack(spacing: CacheDropDesign.Space.md) {
            if let offered = offered(item) { planToggle(offered) }
            Image(systemName: item.kind == .folder ? "folder" : "doc").foregroundStyle(.secondary).frame(width: 20).accessibilityLabel(offered(item) == nil ? "Browse only" : "Large or old file")
            Button {
                if item.kind == .folder { context.enter(item.url) } else { context.inspect(item) }
            } label: {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                    Text(item.url.lastPathComponent).foregroundStyle(.primary)
                    if context.position.folder != nil, !context.position.query.isEmpty { Text(PathDisplay.shortLocation(of: item.url.path)).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel((item.kind == .folder ? "Open folder " : "Inspect ") + item.url.lastPathComponent)
            Text(item.kind == .folder ? folderAllocation(item.url) : bytes(item.allocatedBytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
            if item.kind == .folder {
                Button { context.inspect(item) } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).accessibilityLabel("Inspect " + item.url.lastPathComponent)
            }
        }.padding(CacheDropDesign.Space.md)
            .background(context.position.inspectedID == item.id && context.position.inspectedResource == item.resourceID ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row))
    }
    private func inspector(_ entry: Entry) -> some View {
        ExplorerInspector(name: entry.item.url.lastPathComponent, close: { context.clearInspector() }) {
            inspectorField("Location", entry.item.url.path)
            inspectorField("Observed scope", entry.scan.scope.path)
            inspectorField("Observed", entry.scan.observedAt.formatted(date: .abbreviated, time: .shortened))
            let offered = offered(entry.item)
            inspectorField("Why listed", offered.map(whyListed) ?? "Observed during your manual scan of this location. Browsing uses saved metadata only.")
            Text("On disk: " + (entry.item.kind == .folder ? folderAllocation(entry.item.url) : bytes(entry.item.allocatedBytes)))
            Text("Logical size: " + (entry.item.kind == .folder ? folderSubtotal(entry.item.url, logical: true) : bytes(entry.item.logicalBytes)))
            if let offered {
                inspectorField("Cleanup action", UserFiles.rule.consequence)
                Toggle("Add to cleanup plan", isOn: Binding(get: { selection.catalog.isSelected(offered) }, set: { selection.catalog.setSelected(offered, $0) }))
                    .toggleStyle(.checkbox).disabled(!selection.catalog.canEdit).accessibilityIdentifier("explorerInspectorChoose")
            } else {
                inspectorField("Cleanup action", "Inspection only. Large and old files, and Downloads installers, can be added to the cleanup plan.")
            }
            Text("Observed allocation is not reclaimable space. Trash may retain storage until emptied.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            if entry.item.isDuplicateResource { Text("Shared resource · allocation counts once within a total.") }
            if entry.item.kind == .package || entry.item.kind == .symbolicLink { Text("Protected boundary · contents not inspected.") }
            if entry.item.previewAvailability != .local { Text("Local contents are " + entry.item.previewAvailability.rawValue + ". Preview will not request a download.") }
            HStack {
                Button("Quick Look") { model.showObserved(entry.scan); model.preview(entry.item) }.disabled(entry.item.kind != .file || entry.item.previewAvailability != .local || model.isScanning)
                Button("Reveal in Finder") { model.reveal(entry.item) }
            }
        }
    }
    /// The large or old file the explorer offers for this observation, if any.
    private func offered(_ item: FileObservation) -> Candidate? {
        item.kind == .file ? selection.catalog.pickedByResource[item.resourceID] : nil
    }
    private var showsLargeAndOld: Bool { context.showsLargeAndOld && !context.downloadsOnly && !selection.catalog.pickedByResource.isEmpty }
    /// Files offered from picked folders, under the current folder, in the chosen order. Nothing is preselected.
    /// Only files observed in the explorer's selected locations are listed, each with its observation.
    private var offeredHere: [(file: Candidate, entry: Entry)] {
        let observed = Dictionary(entries.map { ($0.item.resourceID, $0) }, uniquingKeysWith: { first, _ in first })
        let all = selection.catalog.pickedCandidates.compactMap { file -> (file: Candidate, entry: Entry)? in
            guard let entry = observed[file.resourceID] else { return nil }
            if let folder = context.position.folder, !entry.item.url.pathComponents.starts(with: folder.pathComponents) { return nil }
            return (file, entry)
        }
        switch context.fileOrder {
        case .size: return all
        case .lastUsed: return all.sorted { ($0.file.lastUsed ?? .distantFuture) < ($1.file.lastUsed ?? .distantFuture) }
        }
    }
    private var largeAndOldFiles: some View {
        let files = offeredHere
        return VStack(alignment: .leading, spacing: 0) {
            Text("Files of 500 MB or more, or not opened in 90 days.")
                .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.bottom, CacheDropDesign.Space.sm)
            if files.isEmpty { EmptyState(title: "No large or old files here", detail: "Nothing in this folder is 500 MB or more or unopened for 90 days. Protected files and git checkouts are never listed.", symbol: "doc") }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files, id: \.file.id) { file, entry in
                    InspectableItemRow(name: file.displayName, detail: fileDetail(file), size: catalogBytes(file.estimatedBytes), symbol: "doc",
                                       inspected: context.position.inspectedID == entry.item.id,
                                       inspect: { context.inspect(entry.item) }) { planToggle(file) }
                        .help(file.url.path)
                    Divider()
                }
            }
            if files.count == UserFiles.listLimit { Text("Showing the \(UserFiles.listLimit) largest. Pick a smaller folder to see more.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("explorerLargeAndOld")
    }
    private func planToggle(_ file: Candidate) -> some View {
        Toggle("Select " + file.displayName, isOn: Binding(get: { selection.catalog.isSelected(file) }, set: { selection.catalog.setSelected(file, $0) }))
            .labelsHidden().toggleStyle(.checkbox).disabled(!selection.catalog.canEdit).accessibilityIdentifier("explorerChoose-" + file.displayName)
    }
    /// A short location and when it was last used; the full path is the row's tooltip and in the inspector.
    private func fileDetail(_ file: Candidate) -> String {
        let folder = PathDisplay.shortLocation(of: file.url.path)
        return file.lastUsed.map { folder + " · Last used " + $0.formatted(date: .abbreviated, time: .omitted) } ?? folder
    }
    private func whyListed(_ file: Candidate) -> String {
        let large = file.logicalBytes >= UserFiles.largeBytes ? "500 MB or more" : nil
        let old = file.lastUsed.flatMap { $0 < Date().addingTimeInterval(-Double(UserFiles.unusedDays) * 86_400) ? "not opened since " + $0.formatted(date: .abbreviated, time: .omitted) : nil }
        return ([large, old].compactMap { $0 }.joined(separator: " and ") + ".").capitalizedFirst + " Age and size don’t mean it’s unwanted; you decide."
    }
    private func relative(_ url: URL, to root: URL) -> String { url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/") }
    private func inspectorField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            Text(title).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
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
}

/// Shared bounded inspector surface: the host chooses a side pane or compact panel.
struct ExplorerInspector<Content: View>: View {
    let name: String
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                HStack { Text(name).font(CacheDropDesign.TypeStyle.section).lineLimit(2); Spacer(); Button("Close inspector", systemImage: "xmark", action: close).labelStyle(.iconOnly) }
                ScrollView {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) { content() }
                        // Selectable native text extends its accessibility frame beyond
                        // its glyph origin; keep that frame inside the scroll viewport.
                        .padding(.horizontal, CacheDropDesign.Space.xs)
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

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

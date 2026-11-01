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
    /// The scans' index, built off the main thread when they change (#346); nil until the first one is ready. A rebuild
    /// keeps the last one on screen, and `indexRevision` moves when a new one lands.
    private(set) var index: StorageExplorerIndex?
    private(set) var indexRevision = 0
    private var indexInputs: IndexInputs?
    /// What the index is built from: each scan's location, time and observation count, the gone locations and the allowed ones.
    struct IndexInputs: Hashable {
        struct Stamp: Hashable { let scope: URL; let observedAt: Date; let observationCount: Int }
        let scans: [Stamp], reports: [Stamp], gone: [URL], allowed: Set<URL>?
        init(scans: [ScanResult], reports: [ScanResult], gone: [URL], allowed: Set<URL>?) {
            let stamp = { (scan: ScanResult) in Stamp(scope: scan.scope, observedAt: scan.observedAt, observationCount: scan.observations.count) }
            let ordered = { (stamps: [Stamp]) in stamps.sorted { ($0.scope.path, $0.observedAt) < ($1.scope.path, $1.observedAt) } }
            self.scans = ordered(scans.map(stamp)); self.reports = ordered(reports.map(stamp)); self.gone = gone.sorted { $0.path < $1.path }; self.allowed = allowed
        }
    }
    /// Rebuilds the index when what it is built from changed; the build never runs on the main thread.
    func updateIndex(scans: [ScanResult], reports: [ScanResult], gone: [URL]) async {
        let inputs = IndexInputs(scans: scans, reports: reports, gone: gone, allowed: allowedScopes)
        guard inputs != indexInputs else { return }
        indexInputs = inputs
        let allowed = allowedScopes
        let built = await Task.detached(priority: .userInitiated) {
            StorageExplorerIndex(scans: scans, reports: reports, gone: gone, allowedScopes: allowed) { _, _ in false }
        }.value
        guard inputs == indexInputs else { return }
        index = built; indexRevision &+= 1
    }
    /// The last listing, a folder's contents or a search's matches in the chosen order, so redraws while typing don't
    /// filter or sort every entry again (#346, #373).
    @ObservationIgnored private var lastListing: (revision: Int, folder: URL, query: String, sort: ListSort, entries: [StorageExplorerIndex.Entry])?
    /// What `folder` lists: its children, or with a search every match below it, in the column header's order.
    func listing(in folder: URL, query: String) -> [StorageExplorerIndex.Entry] {
        if let last = lastListing, last.revision == indexRevision, last.folder == folder, last.query == query, last.sort == sort { return last.entries }
        guard let index else { return [] }
        let entries = index.ordered(query.isEmpty ? index.children(of: folder) : index.matches(in: folder, query: query), by: sort)
        lastListing = (indexRevision, folder, query, sort, entries)
        return entries
    }
    /// Lists the large and old files offered from picked folders instead of the folder's contents.
    var showsLargeAndOld = false
    /// The column header's sort for every list here (#373): On disk, largest first, until changed; kept until CacheDrop quits.
    var sort = ListSort()
    var position = Position()
    private var history: [Position] = []
    /// The explorer's own title, which a page opened from it names when it goes back (#228).
    var title: String { "Explore storage" }
    /// The list of locations the explorer starts at.
    var rootName: String { "Scanned folders" }
    /// Where back leads inside the explorer: the previous folder, or the list of locations; nil when back leaves it.
    var backDestination: String? {
        guard let previous = history.last else { return nil }
        return previous.folder?.lastPathComponent ?? rootName
    }
    var navigationID = UUID()
    func openLocations() { reset(folder: nil) }
    func openLocation(_ url: URL) { reset(folder: url.standardizedFileURL) }
    private func reset(folder: URL?) {
        position = Position(folder: folder); history = []; navigationID = UUID()
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

/// An included location a recheck couldn't reach, and how to fix it: Overview's Choose again… (#223, #249).
struct ExplorerUnavailableLocation {
    let scope: URL
    let reason: String
    /// "Choose again…", or "Check again" for built-in Downloads, which is never picked (#388).
    var actionTitle = "Choose again…"
    let chooseAgain: () -> Void
    /// When the folder was last observed, as the explorer and Overview both show it (#249, #254).
    static func format(_ lastObserved: Date) -> String { lastObserved.formatted(date: .abbreviated, time: .shortened) }
}

/// Browses observed metadata only. The workspace supplies its fixed sibling action strip.
struct StorageExplorerView: View {
    @Bindable var model: ExploreStorage
    @Bindable var selection: CleanupPlan
    @Bindable var context: StorageExplorerContext
    /// The page the explorer was opened from, which back returns to.
    let caller: String
    let back: () -> Void
    /// Included locations a recheck couldn't reach, from Overview's recovery rows (#249).
    var unavailable: [ExplorerUnavailableLocation] = []
    private typealias Entry = StorageExplorerIndex.Entry
    /// Built once per change in the scans, off the main thread (#346); every lookup below is then cheap.
    private var index: StorageExplorerIndex? { context.index }
    private var scans: [ScanResult] { index?.scans ?? [] }
    /// While the first index is built, a folder counts as there, so nothing says it's gone.
    private var folderAvailable: Bool {
        guard let folder = context.position.folder, let index else { return true }
        return index.contains(folder: folder)
    }
    private var visible: [Entry] {
        guard folderAvailable, let folder = context.position.folder, index != nil else { return [] }
        return context.listing(in: folder, query: context.position.query)
    }
    private var inspected: Entry? {
        guard let id = context.position.inspectedID, let resource = context.position.inspectedResource,
              folderAvailable, context.position.query.isEmpty || !visible.isEmpty,
              !showsLargeAndOld || listsInspected(id: id, resource: resource) else { return nil }
        return index?.entry(id: id, resource: resource)
    }
    /// Whether the list on show has the inspected item; switching lists closes the inspector when it doesn't (#544).
    private func listsInspected(id: String, resource: String) -> Bool {
        showsLargeAndOld ? offeredHere.contains { $0.entry.item.id == id && $0.entry.item.resourceID == resource }
            : visible.contains { $0.item.id == id && $0.item.resourceID == resource }
    }
    /// What the explorer's index is built from, gathered once per redraw (#346).
    private var indexSource: (scans: [ScanResult], reports: [ScanResult], gone: [URL]) {
        (Array(selection.scans.values), model.scopeReports.map(\.current), unavailable.map(\.scope))
    }
    /// Inside a folder that is no longer in the observations.
    private var folderGone: Bool { context.position.folder != nil && !folderAvailable }
    /// Gone locations this explorer shows: each was observed before, so it has a last observation to date (#249).
    private var goneLocations: [(location: ExplorerUnavailableLocation, lastObserved: Date)] {
        let observed = Array(selection.scans.values) + model.scopeReports.map(\.current)
        return unavailable.compactMap { location in
            guard let date = UnavailableScannedFolder.lastObserved(location.scope, in: observed) else { return nil }
            return (location, date)
        }.sorted { $0.location.scope.path < $1.location.scope.path }
    }
    /// Overview's orange row and Choose again…, with when a deleted or moved folder was last observed (#249, #257).
    private func recoveryRow(_ location: ExplorerUnavailableLocation, lastObserved: Date) -> some View {
        StatusRow(text: UnavailableScannedFolder.text(reason: location.reason, lastObserved: ExplorerUnavailableLocation.format(lastObserved)),
                  symbol: "info.circle", role: .caution, identifier: "explorerLocationRecovery",
                  action: StatusAction(title: location.actionTitle, identifier: "explorerChooseAgain", action: location.chooseAgain))
            .disabled(model.isScanning || selection.workspaceRunning)
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= CacheDropDesign.Size.explorerWide
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
                // A folder that is no longer observed leads back only to the list of locations (#227).
                PageHeader(title: context.title,
                           back: BackButton(destination: folderGone ? context.rootName : context.backDestination ?? caller, identifier: "explorerBack") {
                               if folderGone { context.discardUnavailableFolder() } else if !context.backWithinExplorer() { back() }
                           })
                ScanHistoryRecordingNotice()
                breadcrumbs
                // The screen's one explanation (Decision 25).
                Text(showsLargeAndOld ? "Files of 500 MB or more, or not opened in 90 days." : "Click a name to open or inspect it.")
                    .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("explorerHint")
                // The inspector shows one path, only for a picked item or a folder on show (#320, #371).
                HStack(alignment: .top, spacing: CacheDropDesign.Space.lg) {
                    list.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide && showsInspector { inspector.frame(width: CacheDropDesign.Size.inspector) }
                }.frame(maxHeight: .infinity)
                if !wide && showsInspector { inspector.frame(maxHeight: min(CacheDropDesign.Size.inspectorStacked, geometry.size.height * CacheDropDesign.Size.inspectorStackedShare)) }
            }.padding(CacheDropDesign.Space.page)
        }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.previewURL) { _, value in if value == nil { model.closePreviewAccess() } }
        // The index is rebuilt off the main thread whenever the scans change (#346).
        .task(id: StorageExplorerContext.IndexInputs(scans: indexSource.scans, reports: indexSource.reports, gone: indexSource.gone, allowed: context.allowedScopes)) {
            let source = indexSource
            await context.updateIndex(scans: source.scans, reports: source.reports, gone: source.gone)
        }
        .onChange(of: context.indexRevision) { _, _ in
            if context.position.inspectedID != nil && inspected == nil { context.clearInspector() }
        }
        .onChange(of: showsLargeAndOld) { _, _ in
            if let id = context.position.inspectedID, let resource = context.position.inspectedResource,
               !listsInspected(id: id, resource: resource) { context.clearInspector() }
        }
        .onDisappear { model.previewURL = nil; model.closePreviewAccess() }
    }
    /// Text-link breadcrumbs (Decision 47's back button is the only back control), with the quiet Large and old files toggle.
    private var breadcrumbs: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            HStack(spacing: CacheDropDesign.Space.sm) {
                if context.position.folder == nil {
                    Text(context.rootName).foregroundStyle(.secondary)
                } else {
                    Button(context.rootName) { context.returnToRoot() }.buttonStyle(.link)
                }
                if folderAvailable, let folder = context.position.folder {
                    ForEach(breadcrumbs(for: folder), id: \.self) { ancestor in
                        Image(systemName: "chevron.right").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        if ancestor == folder {
                            Text(ancestor.lastPathComponent).lineLimit(1).help(ancestor.path)
                        } else {
                            Button(ancestor.lastPathComponent) { context.enter(ancestor) }.buttonStyle(.link).lineLimit(1).help(ancestor.path)
                        }
                    }
                }
                Spacer(minLength: CacheDropDesign.Space.md)
                if !selection.catalog.pickedByResource.isEmpty {
                    Button(context.showsLargeAndOld ? "All files" : "Large and old files") { context.showsLargeAndOld.toggle() }
                        .buttonStyle(.link).accessibilityIdentifier("explorerMode")
                }
            }.font(CacheDropDesign.TypeStyle.note)
            if folderAvailable, let folder = context.position.folder {
                PageSearchField(label: "Search this folder", prompt: "Search this folder", text: $context.position.query, identifier: "explorerSearch")
                    .help(folder.path)
            }
        }
    }
    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnHeader(nameTitle: "Name", sizeTitle: "On disk", sort: $context.sort, identifier: "explorerSort")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ExplorerViewport(context: context).frame(height: 0)
                    if index == nil && !(selection.scans.isEmpty && model.scopeReports.isEmpty) {
                        // The scans are being indexed, off the main thread (#346): no list, large and old ones included, says empty yet.
                        SkeletonRows(.line, count: 6, identifier: "explorerSkeleton")
                    } else if showsLargeAndOld {
                        largeAndOldFiles
                    } else if context.position.folder == nil {
                        if scans.isEmpty && goneLocations.isEmpty { EmptyState(title: "No scanned folders", detail: "Add a folder in Locations to explore it.", symbol: "folder") }
                        ForEach(context.sort.ordered(scans, name: \.scope.lastPathComponent, bytes: { $0.allocatedBytes ?? 0 }), id: \.scope) { scan in
                            // The size, then only the caveats that apply.
                            InspectableItemRow(name: scan.scope.lastPathComponent,
                                               detail: ([scan.isComplete ? nil : "Partly scanned", (index?.overlaps(scan.scope) ?? false) ? "Overlaps another location" : nil] as [String?]).compactMap { $0 }.joined(separator: " · "),
                                               size: SizeFormatter.text(scan.totalAllocatedBytes ?? scan.allocatedBytes, complete: scan.totalAllocatedBytes != nil), symbol: "folder",
                                               inspected: false, inspect: { context.enter(scan.scope) }, actionLabel: "Open folder " + scan.scope.lastPathComponent) { EmptyView() }
                                .help(scan.scope.path)
                            Divider()
                        }
                        ForEach(goneLocations, id: \.location.scope) { gone in
                            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                                Label(gone.location.scope.lastPathComponent, systemImage: "folder").foregroundStyle(.secondary).help(gone.location.scope.path)
                                recoveryRow(gone.location, lastObserved: gone.lastObserved)
                            }.padding(CacheDropDesign.Space.md)
                            Divider()
                        }
                    } else if !folderAvailable {
                        if let folder = context.position.folder, let scope = UnavailableScannedFolder.location(holding: folder, among: goneLocations.map(\.location.scope)),
                           let gone = goneLocations.first(where: { $0.location.scope == scope }) {
                            recoveryRow(gone.location, lastObserved: gone.lastObserved).padding(CacheDropDesign.Space.md)
                        } else {
                            EmptyState(title: "This folder is no longer there", detail: "It was moved or deleted since the last scan.", symbol: "folder.badge.questionmark")
                        }
                    } else if visible.isEmpty {
                        // Back leaves an empty folder; a search that matches nothing offers Clear search (#321).
                        if context.position.query.isEmpty {
                            EmptyState(title: "Nothing here", detail: "This folder was empty when it was scanned.", symbol: "folder", identifier: "explorerEmpty")
                        } else {
                            EmptyState(title: "No matches", detail: "Nothing in this folder matches your search.", symbol: "magnifyingglass",
                                       action: EmptyStateAction("Clear search") { context.position.query = "" }, identifier: "explorerNoMatches")
                        }
                    } else {
                        // Only on-screen rows are built (#365); the outer stack stays eager so ExplorerViewport is never recycled.
                        LazyVStack(alignment: .leading, spacing: 0) { ForEach(visible) { entry in row(entry); Divider() } }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("explorerList")
        }
    }
    /// A plain row: the checkbox when the file can go in the plan, the name, and its size on disk.
    private func row(_ entry: Entry) -> some View {
        let item = entry.item
        let folder = item.kind == .folder
        return InspectableItemRow(name: item.url.lastPathComponent,
                                  detail: !context.position.query.isEmpty ? PathDisplay.shortLocation(of: item.url.path) : "",
                                  size: folder ? folderAllocation(item.url) : SizeFormatter.text(item.allocatedBytes), symbol: folder ? "folder" : "doc",
                                  inspected: context.position.inspectedID == item.id && context.position.inspectedResource == item.resourceID,
                                  inspect: { if folder { context.enter(item.url) } else { context.inspect(item) } },
                                  detailLineLimit: 1, actionLabel: (folder ? "Open folder " : "Inspect ") + item.url.lastPathComponent) {
            if let offered = offered(item) { planToggle(offered) }
        }.help(item.url.path)
    }
    /// At the list of locations, with nothing picked, there is no inspector and the list takes the width (#371).
    private var showsInspector: Bool { inspected != nil || (folderAvailable && context.position.folder != nil) }
    /// The inspected item, or else the folder on show.
    @ViewBuilder private var inspector: some View {
        if let entry = inspected {
            ExplorerInspector(name: entry.item.url.lastPathComponent) {
                inspectorField("Location", entry.item.url.path)
                inspectorField("On disk", entry.item.kind == .folder ? folderAllocation(entry.item.url) : SizeFormatter.text(entry.item.allocatedBytes))
                if let offered = offered(entry.item) {
                    inspectorField("Why it’s listed", whyListed(offered))
                    inspectorField("Action", "Move to Trash")
                    Toggle("Add to cleanup plan", isOn: Binding(get: { selection.catalog.isSelected(offered) }, set: { selection.catalog.setSelected(offered, $0) }))
                        .toggleStyle(.checkbox).disabled(!selection.catalog.canEdit).accessibilityIdentifier("explorerInspectorChoose")
                }
                if entry.item.isDuplicateResource { Text("Shared with another item, so it counts once.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                if entry.item.kind == .package || entry.item.kind == .symbolicLink { Text("CacheDrop doesn’t look inside it.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                if entry.item.previewAvailability != .local { Text("Not downloaded. Quick Look won’t download it.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Quick Look") { model.showObserved(entry.scan); model.preview(entry.item) }.disabled(entry.item.kind != .file || entry.item.previewAvailability != .local || model.isScanning)
                    Button("Reveal in Finder") { model.reveal(entry.item) }
                }
            }
        } else if folderAvailable, let folder = context.position.folder {
            ExplorerInspector(name: folder.lastPathComponent) {
                inspectorField("Location", folder.path)
                inspectorField("On disk", folderAllocation(folder))
            }
        }
    }
    /// The large or old file the explorer offers for this observation, if any.
    private func offered(_ item: FileObservation) -> Candidate? {
        item.kind == .file ? selection.catalog.pickedByResource[item.resourceID] : nil
    }
    private var showsLargeAndOld: Bool { context.showsLargeAndOld && !selection.catalog.pickedByResource.isEmpty }
    /// Files offered from picked folders, under the current folder, in the column header's order (#373). Nothing is preselected.
    /// Only files observed in the explorer's selected locations are listed, each with its observation.
    private var offeredHere: [(file: Candidate, entry: Entry)] {
        let all = selection.catalog.pickedCandidates.compactMap { file -> (file: Candidate, entry: Entry)? in
            guard let entry = index?.entry(resource: file.resourceID) else { return nil }
            if let folder = context.position.folder, !entry.item.url.pathComponents.starts(with: folder.pathComponents) { return nil }
            return (file, entry)
        }
        return context.sort.ordered(all, name: \.file.displayName, bytes: \.file.estimatedBytes)
    }
    private var largeAndOldFiles: some View {
        let files = offeredHere
        return VStack(alignment: .leading, spacing: 0) {
            if files.isEmpty { EmptyState(title: "No large or old files here", detail: "Nothing here is 500 MB or more, or unopened for 90 days.", symbol: "doc") }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files, id: \.file.id) { file, entry in
                    InspectableItemRow(name: file.displayName, detail: fileDetail(file), size: SizeFormatter.text(file.estimatedBytes), symbol: "doc",
                                       inspected: context.position.inspectedID == entry.item.id,
                                       inspect: { context.inspect(entry.item) }) { planToggle(file) }
                        .help(file.url.path)
                    Divider()
                }
            }
            if files.count == UserFiles.listLimit { Text("Showing the \(UserFiles.listLimit) largest. Pick a smaller folder to see more.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.top, CacheDropDesign.Space.sm) }
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
        let large = file.estimatedBytes >= UserFiles.largeBytes ? "500 MB or more" : nil // On disk, as the list judged it (#394).
        let old = file.lastUsed.flatMap { $0 < Date().addingTimeInterval(-Double(UserFiles.unusedDays) * .secondsPerDay) ? "not opened since " + $0.formatted(date: .abbreviated, time: .omitted) : nil }
        return ([large, old].compactMap { $0 }.joined(separator: " and ") + ".").capitalizedFirst + " Age and size don’t mean it’s unwanted; you decide."
    }
    private func relative(_ url: URL, to root: URL) -> String { url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/") }
    private func inspectorField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
            Text(title).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            Text(value).font(CacheDropDesign.TypeStyle.note).textSelection(.enabled)
        }
    }
    /// A folder's size on disk; "At least" when part of it couldn't be measured.
    private func folderAllocation(_ folder: URL) -> String {
        guard let subtotal = index?.allocatedSubtotal(in: folder) else { return CacheDropDesign.noValue }
        return SizeFormatter.text(subtotal.bytes, complete: !subtotal.hasUnknownRemainder)
    }

    private func breadcrumbs(for folder: URL) -> [URL] {
        guard let root = scans.map(\.scope).filter({ folder.pathComponents.starts(with: $0.pathComponents) }).min(by: { $0.pathComponents.count < $1.pathComponents.count }) else { return [folder] }
        var result = [root]
        for component in folder.pathComponents.dropFirst(root.pathComponents.count) { result.append(result.last!.appendingPathComponent(component)) }
        return result
    }
}

/// Shared bounded inspector surface: the host chooses a side pane or compact panel. Without `close` it stays open.
/// It is as tall as its content, and scrolls only when the host's space is too short for it (#371).
struct ExplorerInspector<Content: View>: View {
    let name: String
    var close: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                HStack {
                    Text(name).font(CacheDropDesign.TypeStyle.section).lineLimit(2); Spacer()
                    if let close { CloseButton(label: "Close inspector", action: close) }
                }
                ViewThatFits(in: .vertical) {
                    evidence
                    ScrollView { evidence }.accessibilityIdentifier("inspectorEvidenceScroll")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("explorerInspector")
    }
    private var evidence: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) { content() }
            // Selectable native text extends its accessibility frame beyond
            // its glyph origin; keep that frame inside the scroll viewport.
            .padding(.horizontal, CacheDropDesign.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                // Lazy rows (#365): lay out first so the saved offset isn't clamped to a stale document height.
                scroll.layoutSubtreeIfNeeded()
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

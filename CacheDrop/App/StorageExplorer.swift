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
    /// Lists the large and old files offered from picked folders instead of the folder's contents.
    var showsLargeAndOld = false
    enum FileOrder: String, CaseIterable, Identifiable { case size = "Largest first", lastUsed = "Oldest first"; var id: Self { self } }
    var fileOrder = FileOrder.size
    var position = Position()
    private var history: [Position] = []
    var canGoBack: Bool { !history.isEmpty }
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
    init(scans selected: [URL: ScanResult], reports: [ScanResult], gone: [URL] = [], allowedScopes: Set<URL>?,
         eligible: (FileObservation, ScanResult) -> Bool) {
        // A location a recheck couldn't reach keeps no current observation (#249).
        var latest = Dictionary(UnavailableScannedFolder.current(Array(selected.values), gone: gone).map { ($0.scope, $0) }, uniquingKeysWith: { first, _ in first })
        for scan in UnavailableScannedFolder.current(reports, gone: gone) {
            if latest[scan.scope].map({ $0.observedAt < scan.observedAt }) ?? true { latest[scan.scope] = scan }
        }
        scans = latest.values.filter { scan in
            allowedScopes?.contains(scan.scope.standardizedFileURL) ?? true
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

/// An included location a recheck couldn't reach, and how to fix it: Overview's Choose again… (#223, #249).
struct ExplorerUnavailableLocation {
    let scope: URL
    let reason: String
    let chooseAgain: () -> Void
    /// When the folder was last observed, as the explorer and Overview both show it (#249, #254).
    static func format(_ lastObserved: Date) -> String { lastObserved.formatted(date: .abbreviated, time: .shortened) }
}

/// Browses observed metadata only. The workspace supplies its fixed sibling action strip.
struct StorageExplorerView: View {
    @Bindable var model: FolderInspection
    @Bindable var selection: SessionPlan
    @Bindable var context: StorageExplorerContext
    /// The page the explorer was opened from, which back returns to.
    let caller: String
    let back: () -> Void
    /// Included locations a recheck couldn't reach, from Overview's recovery rows (#249).
    var unavailable: [ExplorerUnavailableLocation] = []
    private typealias Entry = StorageExplorerObservations.Entry
    private var observations: StorageExplorerObservations {
        StorageExplorerObservations(scans: selection.scans, reports: model.scopeReports.map(\.current), gone: unavailable.map(\.scope),
            allowedScopes: context.allowedScopes,
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
                  action: StatusAction(title: "Choose again…", identifier: "explorerChooseAgain", action: location.chooseAgain))
            .disabled(model.isScanning || selection.workspaceRunning)
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 800
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
                // A folder that is no longer observed leads back only to the list of locations (#227).
                PageHeader(title: context.title,
                           back: BackButton(destination: folderGone ? context.rootName : context.backDestination ?? caller, identifier: "explorerBack") {
                               if folderGone { context.discardUnavailableFolder() } else if !context.backWithinExplorer() { back() }
                           })
                ScanHistoryRecordingNotice()
                breadcrumbs
                // The screen's one explanation (Decision 25).
                Text(showsLargeAndOld ? "Files of 500 MB or more, or not opened in 90 days." : "Click a name to open or inspect it. Tick a file to add it to your cleanup plan.")
                    .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("explorerHint")
                // The inspector is always there, showing one path (#320).
                HStack(alignment: .top, spacing: CacheDropDesign.Space.lg) {
                    list.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide { inspector.frame(width: 280) }
                }.frame(maxHeight: .infinity)
                if !wide { inspector.frame(maxHeight: min(220, geometry.size.height * 0.35)) }
            }.padding(CacheDropDesign.Space.page)
        }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.previewURL) { _, value in if value == nil { model.closePreviewAccess() } }
        .onChange(of: entries.map(\.id)) { _, _ in
            if context.position.inspectedID != nil && inspected == nil { context.clearInspector() }
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
                    if context.showsLargeAndOld {
                        Picker("Sort", selection: $context.fileOrder) {
                            ForEach(StorageExplorerContext.FileOrder.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().fixedSize().accessibilityIdentifier("explorerFileOrder")
                    }
                    Button(context.showsLargeAndOld ? "All files" : "Large and old files") { context.showsLargeAndOld.toggle() }
                        .buttonStyle(.link).accessibilityIdentifier("explorerMode")
                }
            }.font(.callout)
            if folderAvailable, let folder = context.position.folder {
                TextField("Search this folder", text: $context.position.query).help(folder.path)
                    .accessibilityIdentifier("explorerSearch")
            }
        }
    }
    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Name"); Spacer(); Text("On disk")
            }.font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                .padding(.horizontal, CacheDropDesign.Space.md).padding(.bottom, CacheDropDesign.Space.sm)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ExplorerViewport(context: context).frame(height: 0)
                    if showsLargeAndOld {
                        largeAndOldFiles
                    } else if context.position.folder == nil {
                        if scans.isEmpty && goneLocations.isEmpty { EmptyState(title: "No scanned folders", detail: "Add a folder in Locations & access to explore it.", symbol: "folder") }
                        ForEach(scans, id: \.scope) { scan in
                            // The size, then only the caveats that apply.
                            InspectableItemRow(name: scan.scope.lastPathComponent,
                                               detail: ([scan.isComplete ? nil : "Partly scanned", observations.overlaps(scan.scope) ? "Overlaps another location" : nil] as [String?]).compactMap { $0 }.joined(separator: " · "),
                                               size: scan.totalAllocatedBytes.map { bytes($0) } ?? "At least " + bytes(scan.allocatedBytes), symbol: "folder",
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
                        ForEach(visible) { entry in row(entry); Divider() }
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
                                  size: folder ? folderAllocation(item.url) : bytes(item.allocatedBytes), symbol: folder ? "folder" : "doc",
                                  inspected: context.position.inspectedID == item.id && context.position.inspectedResource == item.resourceID,
                                  inspect: { if folder { context.enter(item.url) } else { context.inspect(item) } },
                                  detailLineLimit: 1, actionLabel: (folder ? "Open folder " : "Inspect ") + item.url.lastPathComponent) {
            if let offered = offered(item) { planToggle(offered) }
        }.help(item.url.path)
    }
    /// The inspected item, or else the folder on show, or else the list of locations.
    @ViewBuilder private var inspector: some View {
        if let entry = inspected {
            ExplorerInspector(name: entry.item.url.lastPathComponent) {
                inspectorField("Location", entry.item.url.path)
                inspectorField("On disk", entry.item.kind == .folder ? folderAllocation(entry.item.url) : bytes(entry.item.allocatedBytes))
                if let offered = offered(entry.item) {
                    inspectorField("Why it’s listed", whyListed(offered))
                    inspectorField("Action", "Move to Trash. The space stays used until you empty the Trash.")
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
        } else {
            ExplorerInspector(name: context.rootName) {
                Text(scans.count == 1 ? "1 scanned folder" : "\(scans.count) scanned folders").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    /// The large or old file the explorer offers for this observation, if any.
    private func offered(_ item: FileObservation) -> Candidate? {
        item.kind == .file ? selection.catalog.pickedByResource[item.resourceID] : nil
    }
    private var showsLargeAndOld: Bool { context.showsLargeAndOld && !selection.catalog.pickedByResource.isEmpty }
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
            if files.isEmpty { EmptyState(title: "No large or old files here", detail: "Nothing here is 500 MB or more, or unopened for 90 days.", symbol: "doc") }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files, id: \.file.id) { file, entry in
                    InspectableItemRow(name: file.displayName, detail: fileDetail(file), size: catalogBytes(file.estimatedBytes), symbol: "doc",
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
    /// A folder's size on disk; "At least" when part of it couldn't be measured.
    private func folderAllocation(_ folder: URL) -> String {
        let subtotal = observations.subtotal(in: folder, logical: false)
        return (subtotal.hasUnknownRemainder ? "At least " : "") + bytes(subtotal.bytes)
    }

    private func breadcrumbs(for folder: URL) -> [URL] {
        guard let root = scans.map(\.scope).filter({ folder.pathComponents.starts(with: $0.pathComponents) }).min(by: { $0.pathComponents.count < $1.pathComponents.count }) else { return [folder] }
        var result = [root]
        for component in folder.pathComponents.dropFirst(root.pathComponents.count) { result.append(result.last!.appendingPathComponent(component)) }
        return result
    }
    private func bytes(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "Unknown" }
}

/// Shared bounded inspector surface: the host chooses a side pane or compact panel. Without `close` it stays open.
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

import AppKit
import CacheDropCore
import SwiftUI

/// The apps and plug-in products the Applications page lists (Decision 51), read after each catalog scan. Read-only: this
/// slice removes nothing here. Where it reads is injected: apps from `appPresence`, plug-ins from `home` and `systemRoot`.
@MainActor @Observable final class ApplicationsModel {
    /// The app's model, reading what the catalog reads (test runs inject a fixture home there).
    static let shared = ApplicationsModel(home: CatalogCleanupModel.home, appPresence: CatalogCleanupModel.appPresence, systemRoot: CatalogCleanupModel.systemRoot)
    /// The home folder plug-ins are read in; nil (a debug test run without a fixture home) lists nothing.
    let home: URL?
    private let appPresence: any AppPresence
    private let systemRoot: URL
    init(home: URL?, appPresence: any AppPresence, systemRoot: URL) {
        self.home = home; self.appPresence = appPresence; self.systemRoot = systemRoot
    }
    private(set) var apps: [InventoryEntry] = []
    private(set) var plugIns: [InventoryEntry] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    /// What a debug test run would have revealed or opened.
    private(set) var status: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        guard let home else { apps = []; plugIns = []; return }
        let presence = appPresence, system = systemRoot, own = Bundle.main.bundleIdentifier
        (apps, plugIns) = await Task.detached(priority: .userInitiated) {
            (ApplicationsInventory.apps(presence.installedApps() ?? [], excluding: own),
             ApplicationsInventory.plugIns(PlugInInventory.scan(home: home, systemRoot: system)))
        }.value
    }
    /// The maker's own tool, when it is installed (Decision 50).
    func vendorTool(for entry: InventoryEntry) -> InventoryEntry? { ApplicationsInventory.vendorTool(for: entry, among: apps) }
    /// Shows the entry's files selected in Finder. A debug test run reveals nothing.
    func reveal(_ name: String, _ urls: [URL]) {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { status = "Test run: would reveal \(name)."; return }
        #endif
        Finder.reveal(urls)
    }
    /// Opens the vendor's tool. A debug test run opens nothing.
    func open(_ tool: InventoryEntry) {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { status = "Test run: would open \(tool.name)."; return }
        #endif
        if let url = tool.parts.first?.url { Finder.open(url) }
    }
}

/// Applications (Decision 51): apps, plug-in products and leftovers of removed apps on one page. Apps and plug-ins are
/// read-only for now; leftovers are chosen and cleaned through the plan's rows, review sheet and run.
struct ApplicationsView: View {
    let selection: SessionPlan
    let model: ApplicationsModel
    var viewHistory: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    @State private var expanded: Set<String> = []
    @State private var leftoversExpanded = false
    @State private var review: WorkspaceCleanupReview?
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    private var catalog: CatalogCleanupModel { selection.catalog }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if selection.showsRun(for: .applications) { CleanupRunSection(selection: selection) } else { page }
            }.background(CacheDropDesign.reading)
            if selection.showsRun(for: .applications) && selection.workspaceRunning {
                CleanupStopStrip(selection: selection)
            } else if selection.showsRun(for: .applications) {
                ActionStrip(message: selection.requiresRecoveryReview ? "Review unresolved records before cleaning again." : nil) {
                    if let viewHistory { Button("View history", action: viewHistory) }
                    if selection.requiresRecoveryReview, let reviewRecovery { Button("Review recovery", action: reviewRecovery) }
                    Button("Done") { selection.dismissResult() }.buttonStyle(.borderedProminent)
                }
            } else {
                ActionStrip(message: nil) {
                    ReviewCleanupButton(enabled: selection.canReviewApplications, focusRequest: reviewFocusRequest) { Task { await openReview() } }.fixedSize()
                }
            }
        }
        .sheet(item: $review, onDismiss: { reviewFocusRequest += 1 }) { snapshot in
            WorkspaceCleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                review = nil
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = "Your choices changed. Review the latest items before cleaning." } }
            }
        }
        .onChange(of: catalog.selectionRevision) { _, _ in if review != nil { review = nil } }
        .task { await catalog.scanIfNeeded() }
        // Read again after each catalog scan, so Scan again refreshes the lists too.
        .task(id: catalog.isScanning) { if !catalog.isScanning { await model.load() } }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            PageHeader(title: "Applications", subtitle: "Apps, plug-ins and files that removed apps left behind.")
                .accessibilityElement(children: .combine).accessibilityIdentifier("applicationsHeader")
                .padding(.bottom, CacheDropDesign.Space.sm)
            if let approvalError { StatusRow(text: approvalError, symbol: "exclamationmark.circle", role: .caution) }
            if let status = model.status { StatusRow(text: status, identifier: "applicationsStatus") }
            section("Apps", id: "apps", entries: model.apps, category: .apps, identifier: "applicationsApp-",
                    empty: ("No apps to list", "Only Apple’s apps are in the Applications folders."))
            section("Plug-ins", id: "plugIns", entries: model.plugIns, category: .audioPlugIns, identifier: "applicationsPlugIn-",
                    empty: ("No plug-ins to list", "No audio plug-ins other than Apple’s were found."))
            Text("Leftovers").font(CacheDropDesign.TypeStyle.section)
            if let row = catalog.leftoversRow {
                PlanCategoryRow(model: catalog, row: row, expanded: $leftoversExpanded)
            } else if catalog.hasScanned && !catalog.isScanning {
                state("No leftovers", "Apps you removed left nothing behind that CacheDrop can tie to them.", symbol: "checkmark.circle", id: "applicationsEmpty-leftovers")
            } else {
                loading("leftovers")
            }
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A section's lists come after the catalog scan; until then, and while they are read, it says it is looking (#270).
    private var listsLoading: Bool { !model.hasLoaded || model.isLoading || catalog.isScanning }

    @ViewBuilder private func section(_ title: String, id: String, entries: [InventoryEntry], category: StorageCategory, identifier: String,
                                      empty: (title: String, detail: String)) -> some View {
        Text(title).font(CacheDropDesign.TypeStyle.section)
        if entries.isEmpty {
            if listsLoading { loading(id) } else { state(empty.title, empty.detail, symbol: "tray", id: "applicationsEmpty-" + id) }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    row(entry, category: category, identifier: identifier + entry.id)
                    Divider().padding(.vertical, CacheDropDesign.Space.md)
                }
            }
        }
    }

    private func loading(_ id: String) -> some View {
        state("Looking…", "This fills in when the scan finishes.", symbol: "hourglass", id: "applicationsLoading-" + id)
    }
    private func state(_ title: String, _ detail: String, symbol: String, id: String) -> some View {
        EmptyState(title: title, detail: detail, symbol: symbol).accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }

    /// A row with no checkbox, since nothing here is removed yet; one that needs a password says so (Decision 50). Its
    /// identifiers carry the entry's path, never its name, so same-named apps on two volumes stay apart (#271).
    private func row(_ entry: InventoryEntry, category: StorageCategory, identifier: String) -> some View {
        let isExpanded = Binding(get: { expanded.contains(entry.id) }, set: { if $0 { expanded.insert(entry.id) } else { expanded.remove(entry.id) } })
        return CategoryRow(category: category, state: nil, title: entry.name, detail: [entry.maker, entry.volume].compactMap { $0 }.joined(separator: " · "),
                           size: entry.size.text, enabled: true, identifier: identifier,
                           // An app alone is its only item: no "Choose items · 1" (#270).
                           itemCount: entry.parts.count > 1 ? entry.parts.count : nil, expanded: isExpanded, toggle: {}) {
            if entry.needsPassword { passwordLine(entry) }
        } items: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entry.parts, id: \.url) { part in
                    InspectableItemRow(name: part.name, detail: PathDisplay.shortLocation(of: part.url, home: model.home ?? FileManager.default.homeDirectoryForCurrentUser), size: part.size.text,
                                       symbol: category.symbol, inspected: false, inspect: { model.reveal(part.name, [part.url]) },
                                       detailLineLimit: 1, actionLabel: "Reveal \(part.name) in Finder") { EmptyView() }
                        .help(part.url.path)
                }
            }
        }
    }

    /// "Needs your password to remove · Reveal in Finder", or "Needs <tool> or your password · Open <tool>" when the vendor's tool is installed.
    private func passwordLine(_ entry: InventoryEntry) -> some View {
        let tool = model.vendorTool(for: entry)
        let action = tool.map { tool in StatusAction(title: "Open " + tool.name, identifier: "applicationsOpen-" + entry.id) { model.open(tool) } }
            ?? StatusAction(title: "Reveal in Finder", identifier: "applicationsReveal-" + entry.id) { model.reveal(entry.name, entry.parts.map(\.url)) }
        return StatusRow(text: tool.map { "Needs \($0.name) or your password" } ?? "Needs your password to remove", symbol: "lock",
                         identifier: "applicationsPassword-" + entry.id, action: action)
    }

    private func openReview() async {
        do { review = try await selection.prepareApplicationsReview(); approvalError = nil }
        catch { approvalError = "Your choices changed. Review the latest items and try again." }
    }
}

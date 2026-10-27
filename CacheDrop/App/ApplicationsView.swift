import AppKit
import CacheDropCore
import SwiftUI

/// The apps and plug-in products the Applications page lists (Decision 51), read after each catalog scan. Apps are uninstalled
/// and plug-in products through the catalog's items (#177, #176). Where it reads is injected: apps from `appPresence`, plug-ins from `home` and `systemRoot`.
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

    /// `plugIns` is what the catalog scan read (#176), so the page lists the products it offers; nil reads them here.
    func load(plugIns read: PlugInInventory? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        guard let home else { apps = []; plugIns = []; return }
        let presence = appPresence, system = systemRoot, own = Bundle.main.bundleIdentifier
        (apps, plugIns) = await Task.detached(priority: .userInitiated) {
            (ApplicationsInventory.apps(presence.installedApps() ?? [], excluding: own),
             ApplicationsInventory.plugIns(read ?? PlugInInventory.scan(home: home, systemRoot: system)))
        }.value
    }
    /// The app's own uninstaller or the maker's tool, when it is installed (Decisions 41, 50).
    func uninstaller(for entry: InventoryEntry) -> InventoryEntry? { ApplicationsInventory.uninstaller(for: entry, among: apps) }
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

/// Applications (Decision 51): apps, plug-in products and leftovers of removed apps on one page. Apps (#177),
/// leftovers and plug-in products (#176) are chosen and cleaned through the plan's selection, review sheet and run.
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
            CleanupActionBar(selection: selection, source: .applications, viewHistory: viewHistory, reviewRecovery: reviewRecovery) {
                Button("Done") { selection.dismissResult() }.buttonStyle(.borderedProminent)
            } idle: {
                ReviewCleanupButton(enabled: selection.canReviewApplications, focusRequest: reviewFocusRequest) { Task { await openReview() } }.fixedSize()
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
        .task(id: catalog.isScanning) { if !catalog.isScanning { await model.load(plugIns: catalog.plugInInventory) } }
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

    /// A row; an app CacheDrop can uninstall (#177) has a checkbox for the app and its files, the rest have none. One that
    /// needs a password says so (Decision 50). Its identifiers carry the entry's path, never its name, so same-named apps on
    /// two volumes stay apart (#271).
    private func row(_ entry: InventoryEntry, category: StorageCategory, identifier: String) -> some View {
        let isExpanded = Binding(get: { expanded.contains(entry.id) }, set: { if $0 { expanded.insert(entry.id) } else { expanded.remove(entry.id) } })
        let uninstall = catalog.uninstallItems(of: entry.id)
        // A partly removable product also lists what stays (#176).
        let staying = uninstall.isEmpty || category == .apps ? [] : entry.parts.filter { !$0.removable }
        let count = uninstall.isEmpty ? entry.parts.count : uninstall.count + staying.count
        return CategoryRow(category: category, state: uninstall.isEmpty ? nil : catalog.selectionState(ofApp: entry.id), title: entry.name,
                           detail: [entry.maker, entry.volume].compactMap { $0 }.joined(separator: " · "),
                           size: uninstall.isEmpty ? entry.size.text : SizeEstimate(sum: uninstall.map(SizeEstimate.init)).text,
                           enabled: uninstall.isEmpty || catalog.canEdit, identifier: identifier,
                           // An app alone is its only item: no "Choose items · 1" (#270).
                           itemCount: count > 1 ? count : nil, expanded: isExpanded,
                           toggle: { if catalog.toggleApp(entry.id) { expanded.insert(entry.id) } }) {
            if entry.needsPassword { passwordLine(entry) }
            else if !uninstall.isEmpty {
                // Its own uninstaller comes first (Decision 41); a later scan's Leftovers shows what it left.
                if let tool = model.uninstaller(for: entry) {
                    StatusRow(text: category == .apps ? "Has its own uninstaller" : "\(tool.name) can uninstall it", symbol: "shippingbox", identifier: "applicationsUninstaller-" + entry.id,
                              action: StatusAction(title: "Open " + tool.name, identifier: "applicationsOpen-" + entry.id) { model.open(tool) })
                }
                // The app, or a plug-in product's own app and its hosts (#176), each with "Quit <App>".
                if let rule = (AppUninstall.rules + PlugInUninstall.rules).first(where: { rule in uninstall.contains { $0.ruleID == rule.id } }) {
                    PlanRunningOwners(model: catalog, rule: rule, only: Set(uninstall.compactMap(\.uninstall).flatMap { [$0.owner.name] + $0.hosts.map(\.name) }))
                }
            } else if catalog.hasScanned, !catalog.isScanning {
                // A removable app the scan didn't offer says why, rather than showing a bare row (#281).
                StatusRow(text: "Not offered: excluded in Settings, or changed since the scan", identifier: "applicationsNotOffered-" + entry.id)
            }
        } items: {
            if !uninstall.isEmpty {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    ForEach((AppUninstall.rules + PlugInUninstall.rules).filter { rule in uninstall.contains { $0.ruleID == rule.id } }) { rule in
                        Text(rule.title).font(CacheDropDesign.TypeStyle.caption.weight(.medium))
                        CatalogItemRows(model: catalog, rule: rule, app: entry.id)
                    }
                    // A partly removable product lists what stays, with no checkbox (Decision 50).
                    ForEach(staying, id: \.url) { part in
                        StatusRow(text: "\(part.name): " + (model.uninstaller(for: entry).map { "Needs \($0.name) or your password" } ?? "Needs your password"), symbol: "lock",
                                  identifier: "applicationsPartPassword-" + part.url.path,
                                  action: StatusAction(title: "Reveal in Finder", identifier: "applicationsPartReveal-" + part.url.path) { model.reveal(part.name, [part.url]) })
                    }
                }
            } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entry.parts, id: \.url) { part in
                    InspectableItemRow(name: part.name, detail: PathDisplay.shortLocation(of: part.url, home: CatalogCleanupModel.checkHome), size: part.size.text,
                                       symbol: category.symbol, inspected: false, inspect: { model.reveal(part.name, [part.url]) },
                                       detailLineLimit: 1, actionLabel: "Reveal \(part.name) in Finder") { EmptyView() }
                        .help(part.url.path)
                }
            }
            }
        }
    }

    /// "Needs your password to remove · Reveal in Finder", or "Needs <tool> or your password · Open <tool>" when the vendor's tool is installed.
    private func passwordLine(_ entry: InventoryEntry) -> some View {
        let tool = model.uninstaller(for: entry)
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

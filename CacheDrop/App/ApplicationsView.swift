import AppKit
import CacheDropCore
import SwiftUI

/// The page's sections (Decision 153); the raw value ends their accessibility identifiers.
enum ApplicationsSection: String { case apps, audio, leftovers }
/// Audio software's groups and makers (Decision 151); `key` ends their accessibility identifiers.
enum AudioGroup: Hashable {
    case apps, plugIns, sounds, drivers, maker(String?)
    var key: String {
        switch self {
        case .apps: "apps"
        case .plugIns: "plug-ins"
        case .sounds: "sounds"
        case .drivers: "drivers"
        case .maker(let name): "maker:" + (name ?? "")
        }
    }
}

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
    /// DAWs, vendor managers and plug-ins' own apps: Audio software's, never Apps' (Decision 151).
    private(set) var audioApps: [InventoryEntry] = []
    /// Reason's additional devices, listed with the plug-ins; audio and MIDI drivers; and sounds and samples (Decision 151).
    private(set) var reasonDevices: [InventoryEntry] = []
    private(set) var drivers: [InventoryEntry] = []
    private(set) var sounds: [InventoryEntry] = []
    /// The page's Sort and search (#295): kept while CacheDrop runs, never across launches.
    var listing = ApplicationsListing()
    /// The sections open on the page (Decision 151): all closed at first, kept open or closed until CacheDrop quits.
    var openSections: Set<ApplicationsSection> = []
    /// Audio software's groups and makers that are open, kept the same way.
    var openGroups: Set<AudioGroup> = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    /// The list of apps couldn't be read (Spotlight didn't answer): unknown, never "no apps" (#310).
    private(set) var appsUnreadable = false
    /// What a debug test run would have revealed or opened.
    private(set) var status: String?

    /// `plugIns` is what the catalog scan read (#176), so the page lists the products it offers; nil reads them here.
    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    /// The catalog scan whose lists are read (`CatalogCleanupModel.applicationsScan`).
    private(set) var loadedScan: UUID?
    func load(plugIns read: PlugInInventory? = nil, scanID: UUID?) async {
        while let loadingTask { await loadingTask.value }
        if let scanID, loadedScan == scanID, hasLoaded { return }
        let task = Task {
            await readInventory(plugIns: read)
            loadedScan = scanID
            loadingTask = nil
        }
        loadingTask = task
        await task.value
    }
    private func readInventory(plugIns read: PlugInInventory?) async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        guard let home else { apps = []; plugIns = []; audioApps = []; reasonDevices = []; drivers = []; sounds = []; return }
        #if DEBUG
        if LocalStateLocation.isDisposableTest,
           let raw = LocalStateLocation.fixtureEnvironment["CACHEDROP_TEST_INVENTORY_PAUSE"], let seconds = Double(raw), seconds > 0 {
            try? await Task.sleep(for: .seconds(min(seconds, 5)))
        }
        #endif
        let presence = appPresence, system = systemRoot, own = Bundle.main.bundleIdentifier
        let (devices, audioDrivers, audioSounds) = await Task.detached(priority: .userInitiated) {
            (AudioSoftware.optionalDevices(home: home), AudioSoftware.drivers(home: home, systemRoot: system), AudioSoftware.sounds(home: home, systemRoot: system))
        }.value
        reasonDevices = devices; drivers = audioDrivers; sounds = audioSounds
        let (listed, products, audio) = await Task.detached(priority: .userInitiated) {
            let inventory = read ?? PlugInInventory.scan(home: home, systemRoot: system, receipts: ReceiptListings.read(under: system))
            let listed = presence.installedApps().map { ApplicationsInventory.apps($0, excluding: own, home: home) }
            let split = AudioSoftware.split(listed ?? [], plugIns: inventory)
            return (listed.map { _ in split.apps }, ApplicationsInventory.plugIns(inventory), split.audio)
        }.value
        apps = listed ?? []; plugIns = products; audioApps = audio; appsUnreadable = listed == nil
    }
    /// The app's own uninstaller or the maker's tool, when it is installed (Decisions 41, 50).
    func uninstaller(for entry: InventoryEntry) -> InventoryEntry? { ApplicationsInventory.uninstaller(for: entry, among: apps + audioApps) }
    /// The vendor's manager that can remove or move a sound library, when it is installed (Decision 157).
    func manager(of sound: InventoryEntry) -> InventoryEntry? { AudioSoftware.manager(of: sound, among: apps + audioApps) }
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

/// Applications (Decision 51): apps, plug-in products and files from deleted apps on one page. Apps (#177),
/// files from deleted apps and plug-in products (#176) are chosen and cleaned through the plan's selection, review sheet and run.
struct ApplicationsView: View {
    let selection: CleanupPlan
    let model: ApplicationsModel
    var viewHistory: (() -> Void)? = nil
    var reviewRecovery: (() -> Void)? = nil
    /// Opens the Cleanup plan with these categories revealed, for the review's "Clean in the Cleanup plan" (#354).
    var openPlan: (([CatalogCategory]) -> Void)? = nil
    @State private var expanded: Set<String> = []
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    private var catalog: CatalogCleanupModel { selection.catalog }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if selection.showsRun(for: .applications) { CleanupRunSection(selection: selection, reveal: proxy.revealRow) } else { page }
                }.background(CacheDropDesign.reading)
            }
            // Every ticked item is counted, those the search hides too (#295).
            CleanupActionBar(selection: selection, source: .applications, viewHistory: viewHistory, reviewRecovery: reviewRecovery,
                             idleNote: catalog.applicationsSelected.isEmpty ? nil : CacheDropDesign.items(catalog.applicationsSelected.count) + " selected") {
                Button("Done") { selection.dismissResult() }.buttonStyle(.borderedProminent)
            } idle: {
                BusyAction(busy: selection.isCheckingReview) {
                    ReviewCleanupButton(enabled: selection.canReviewApplications && !selection.isCheckingReview, focusRequest: reviewFocusRequest,
                                        tooltip: catalog.isScanning && !selection.canReviewApplications ? CacheDropDesign.waitForScanHelp : nil) { Task { await openReview() } }.fixedSize()
                }
            }
        }
        .sheet(isPresented: selection.reviewSheet(for: .applications), onDismiss: { reviewFocusRequest += 1 }) {
            ReviewSheet(selection: selection, follow: { link in follow(link) }) { snapshot in
                Task { do { try await selection.executeWorkspace(snapshot) } catch { approvalError = PlanReviewError.changedMessage } }
            }
        }
        // The sheet closes only when the choices it was built from changed, and the page says so (#307).
        .onChange(of: catalog.selectionRevision(for: .applications)) { _, _ in if selection.reviewChoicesChanged(.applications) { approvalError = PlanReviewError.changedMessage } }
        // Read again after each catalog scan that could change them, so Scan again refreshes the lists too; a rescan after a
        // run that changed none of them keeps them, and they can be read during it (Decision 123).
        .task(id: catalog.isScanning) {
            if !appsWaitForScan { await model.load(plugIns: catalog.plugInInventory, scanID: catalog.applicationsScan) }
        }
        // A search opens every section with a match in it (Decision 151), also when the match arrives after the search was
        // typed (a list still loading); one closed during the search stays closed until its matches change.
        .onChange(of: sectionsWithMatches) { _, matching in model.openSections.formUnion(matching) }
        .onChange(of: groupsWithMatches) { _, matching in model.openGroups.formUnion(matching) }
    }

    /// A staying line's link (#354): the plan closes the review and opens there; Finder shows the files over it.
    private func follow(_ link: AppUninstall.Staying.Link) {
        switch link {
        case .cleanupPlan(let ruleIDs):
            var categories: [CatalogCategory] = []
            for id in ruleIDs { if let category = catalog.catalog.rule(id)?.category, catalog.plans(category), !categories.contains(category) { categories.append(category) } }
            selection.closeReview()
            openPlan?(categories)
        case .finder(let paths):
            model.reveal(paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "), paths.map { URL(fileURLWithPath: $0) })
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            header
            // Nothing on the page can be ticked: no card reading "—" and "0 items selected" (#575, Decision 130).
            if listsLoading || hasTickable || !catalog.applicationsSelected.isEmpty { summary }
            SettingsUnreadableNotice(model: catalog)
            if let approvalError { StatusRow(text: approvalError, symbol: "exclamationmark.circle", role: .caution) }
            if let status = model.status { StatusRow(text: status, identifier: "applicationsStatus") }
            if nothingMatches {
                // One empty state for the whole page, with its one way forward (Decision 63, #468).
                EmptyState(title: "No matches", detail: "Nothing here has “\(searchText)” in its name or maker.", symbol: "magnifyingglass",
                           action: EmptyStateAction("Clear search") { model.listing.search = "" }, identifier: "applicationsNoMatches")
            } else {
            // Nothing listed yet: no Name and Size over empty states (#427).
            if !(model.apps + model.audioApps + model.plugIns + model.reasonDevices + model.drivers + model.sounds).isEmpty || catalog.leftoversRow != nil { columnHeader }
            section("Apps", id: .apps, detail: "Apps in your Applications folders", noun: "apps", entries: listed(model.apps), category: .apps,
                    identifier: "applicationsApp-", empty: ("No apps to list", "Only Apple’s apps are in the Applications folders."))
            audioSection
            leftovers
            }
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Files from deleted apps: the plan's category row (Decision 51), its "Choose items" the section's open state (Decision 153),
    /// or its heading and why nothing is listed.
    @ViewBuilder private var leftovers: some View {
        if let row = catalog.leftoversRow, !model.listing.isSearching || leftoversMatch {
            PlanCategoryRow(model: catalog, row: row, expanded: sectionOpen(.leftovers), listing: model.listing).waitingForScan(catalog.isScanning)
        } else {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                sectionHeading(.leftovers, category: .leftovers, title: CatalogCategory.leftovers.overviewTitle,
                               detail: CatalogCategory.leftovers.overviewDetail)
                leftoversEmpty
            }
        }
    }
    /// Why Files from deleted apps lists nothing.
    @ViewBuilder private var leftoversEmpty: some View {
        if catalog.leftoversRow != nil {
            noMatches("leftovers")
        } else if catalog.settingsUnreadable {
            EmptyView() // The notice above says why nothing was read (#310).
        } else if catalog.hasScanned && !catalog.isScanning && model.listing.isSearching {
            noMatches("leftovers")
        } else if catalog.hasScanned && !catalog.isScanning {
            state("No files from deleted apps", "Apps you removed left nothing behind that CacheDrop can tie to them.", symbol: "checkmark.circle", id: "applicationsEmpty-leftovers")
        } else {
            loading("leftovers")
        }
    }
    /// Whether the search matches a file from deleted apps; during a rescan, one from the last scan (its row stays, dimmed).
    private var leftoversMatch: Bool {
        catalog.leftoversRow.map { $0.rules.flatMap(catalog.candidates(for:)).contains(where: model.listing.matches) } ?? false
    }
    /// Whether a section is open, kept by the page's model.
    private func sectionOpen(_ id: ApplicationsSection) -> Binding<Bool> {
        Binding(get: { model.openSections.contains(id) }, set: { if $0 { model.openSections.insert(id) } else { model.openSections.remove(id) } })
    }
    /// The sections a search has a match in.
    private var sectionsWithMatches: Set<ApplicationsSection> {
        guard model.listing.isSearching else { return [] }
        var ids = Set<ApplicationsSection>()
        if model.apps.contains(where: { model.listing.matches(name: $0.name, maker: $0.maker) }) { ids.insert(.apps) }
        if (model.audioApps + model.plugIns + model.reasonDevices + model.drivers + model.sounds).contains(where: { model.listing.matches(name: $0.name, maker: $0.maker) }) { ids.insert(.audio) }
        if leftoversMatch { ids.insert(.leftovers) }
        return ids
    }

    /// The title and description, with the one search for Apps, Audio software and Files from deleted apps on their right (#295, #352),
    /// by name or maker: one header band, one left edge.
    private var header: some View {
        PageHeader(title: "Applications", subtitle: "Apps, audio software and files from deleted apps",
                   search: PageSearchField(label: "Search apps, audio software and files from deleted apps", prompt: "Name or maker",
                                           text: Bindable(model).listing.search, identifier: "applicationsSearch"))
            // A container, not one combined element: the search inside stays its own field.
            .accessibilityElement(children: .contain).accessibilityIdentifier("applicationsHeader")
            .padding(.bottom, CacheDropDesign.Space.sm)
    }
    /// Whether any section lists something with a checkbox: an app or plug-in CacheDrop can uninstall, or files from deleted apps.
    private var hasTickable: Bool {
        catalog.leftoversRow != nil || (model.apps + model.audioApps + model.plugIns + model.reasonDevices + model.drivers).contains { !catalog.uninstallItems(ofRow: $0.id).isEmpty }
    }
    /// The same selected candidates as the footer and review, including choices hidden by search (#525).
    private var summary: some View {
        let items = catalog.applicationsSelected
        let value = items.isEmpty ? CacheDropDesign.noValue : catalog.sizeText(of: items) + " to Trash"
        return SelectionSummary(value: value, detail: CacheDropDesign.items(items.count) + " selected",
                                identifier: "applicationsSummary", title: "Ready to clean")
            // Ticked files from deleted apps wait for the scan, so a total that counts them does too (Decision 123).
            .waitingForScan(catalog.isScanning && !catalog.canChoose(items))
    }

    /// The list's quiet table header, one sort for every section (#295, #352): "Name" over the names, "Size" over the sizes.
    private var columnHeader: some View {
        ColumnHeader(nameTitle: "Name", sizeTitle: "Size", sort: Bindable(model).listing.sort, identifier: "applicationsSort",
                     insets: EdgeInsets(top: 0, leading: CacheDropDesign.Size.categoryContentIndent, bottom: 0, trailing: 0))
    }
    private var searchText: String { model.listing.search.trimmingCharacters(in: .whitespaces) }
    /// A search that matches nothing in any section, once the lists are read (#468).
    private var nothingMatches: Bool {
        guard model.listing.isSearching, !listsLoading, !model.appsUnreadable, !catalog.settingsUnreadable else { return false }
        return sectionsWithMatches.isEmpty
    }
    private func noMatches(_ id: String) -> some View {
        state("No matches", "Nothing here has “\(searchText)” in its name or maker.", symbol: "magnifyingglass",
              id: "applicationsNoMatches-" + id)
    }

    /// The entries still listed: not one whose app or product the last run left nothing of (Decision 134).
    private func listed(_ entries: [InventoryEntry]) -> [InventoryEntry] {
        entries.filter { !catalog.applicationsHides($0.id, loaded: model.loadedScan) }
    }
    /// A section's lists come after the catalog scan; until then, and while they are read, it shows skeleton rows (#270, #308).
    private var listsLoading: Bool { !model.hasLoaded || model.isLoading || appsWaitForScan }
    /// Apps and Audio software wait for a running scan, except the rescan after a run that changed none of them; Files from deleted
    /// apps always does (Decision 123).
    private var appsWaitForScan: Bool { catalog.applicationsWaitForScan }

    @ViewBuilder private func section(_ title: String, id section: ApplicationsSection, detail: String, noun: String, entries: [InventoryEntry], category: StorageCategory, identifier: String,
                                      empty: (title: String, detail: String)) -> some View {
        let shown = model.listing.arranged(entries, name: \.name, maker: \.maker, bytes: { size(of: $0).sortBytes })
        if shown.isEmpty {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                sectionHeading(section, category: category, title: title, detail: detail)
                sectionBody(id: section, entries: entries, shown: shown, category: category, identifier: identifier, empty: empty)
            }
        } else {
            // A category row like the plan's (Decision 153), with no checkbox: a section is never ticked whole (Decision 51). During
            // a rescan it keeps its rows and its open state, dimmed (#308).
            CategoryRow(category: category, state: nil, title: title, detail: detail, size: SizeEstimate(sum: shown.map(size(of:))).text, enabled: true,
                        identifier: "applicationsSection-" + section.rawValue, itemCount: shown.count, chooseNoun: noun,
                        expanded: sectionOpen(section), toggle: {}) { EmptyView() } items: {
                sectionBody(id: section, entries: entries, shown: shown, category: category, identifier: identifier, empty: empty)
            }
        }
    }
    /// A section's category row while it lists nothing: no size and no "Choose"; why follows it.
    private func sectionHeading(_ section: ApplicationsSection, category: StorageCategory, title: String, detail: String) -> some View {
        CategoryRow(category: category, state: nil, title: title, detail: detail, size: "", enabled: true, identifier: "applicationsSection-" + section.rawValue,
                    itemCount: nil, expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
    }
    @ViewBuilder private func sectionBody(id section: ApplicationsSection, entries: [InventoryEntry], shown: [InventoryEntry], category: StorageCategory, identifier: String,
                                          empty: (title: String, detail: String)) -> some View {
        let id = section.rawValue
        if entries.isEmpty {
            if listsLoading { loading(id) }
            else if model.listing.isSearching, !(section == .apps && model.appsUnreadable) { noMatches(id) }
            else if section == .apps, model.appsUnreadable {
                // Spotlight didn't answer: unknown, never "Only Apple’s apps" (#310), as the one empty state (#321). Scan again
                // scans again, so uninstalls are read too.
                EmptyState(title: "CacheDrop couldn’t read the list of apps", detail: "Spotlight didn’t answer.", symbol: "exclamationmark.triangle",
                           action: EmptyStateAction("Scan again") { Task { await catalog.rescan() } }, identifier: "applicationsUnreadable")
            } else { state(empty.title, empty.detail, symbol: "tray", id: "applicationsEmpty-" + id) }
        } else if shown.isEmpty {
            noMatches(id)
        } else {
            rows(shown, category: category, identifier: identifier)
        }
    }
    /// Rows from the last scan stay, dimmed, until the rescan says what can go with each (#303, #308); after a run, only
    /// the rows it reads again (Decision 134).
    private func rows(_ shown: [InventoryEntry], category: StorageCategory, identifier: String, revealsPlace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { entry in
                row(entry, category: category, identifier: identifier + entry.id, revealsPlace: revealsPlace)
                    .waitingForScan(!listsLoading && catalog.applicationsRowWaits(entry.id))
                Divider().padding(.vertical, CacheDropDesign.Space.md)
            }
        }.waitingForScan(listsLoading)
    }

    /// Audio software (Decisions 151, 153): DAWs and apps, plug-ins by maker (Reason's additional devices among them), sounds and
    /// samples, and drivers, each group a category row with no checkbox.
    @ViewBuilder private var audioSection: some View {
        let apps = arranged(listed(model.audioApps)), plugIns = arranged(listed(model.plugIns + model.reasonDevices))
        let sounds = arranged(model.sounds), drivers = arranged(listed(model.drivers)), all = apps + plugIns + sounds + drivers
        let detail = "DAWs and apps, plug-ins, sounds and drivers"
        if all.isEmpty {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                sectionHeading(.audio, category: .audioSoftware, title: "Audio software", detail: detail)
                appsUnreadableNote
                sectionBody(id: .audio, entries: listed(model.audioApps + model.plugIns + model.reasonDevices + model.drivers) + model.sounds, shown: [],
                            category: .audioSoftware, identifier: "",
                            empty: ("No audio software to list", "No DAWs, plug-ins, sounds or drivers other than Apple’s were found."))
            }
        } else {
            // Opening it shows its groups straight away, behind "Show groups · N" (Decision 175).
            let groups = [apps, plugIns, sounds, drivers].filter { !$0.isEmpty }.count
            CategoryRow(category: .audioSoftware, state: nil, title: "Audio software", detail: detail, size: total(all), enabled: true,
                        identifier: "applicationsSection-audio", itemCount: groups, chooseVerb: "Show", chooseNoun: "groups",
                        expanded: sectionOpen(.audio), toggle: {}) { appsUnreadableNote } items: {
                VStack(alignment: .leading, spacing: 0) {
                    if !apps.isEmpty {
                        group("DAWs and apps", .apps, noun: "apps", entries: apps) { rows(apps, category: .apps, identifier: "applicationsApp-") }
                    }
                    if !plugIns.isEmpty {
                        group("Plug-ins", .plugIns, noun: "plug-ins", entries: plugIns) { makers(plugIns) }
                    }
                    if !sounds.isEmpty {
                        // Read-only (#705 decides removing them): "Show", never "Choose" (Decision 154).
                        group("Sounds and samples", .sounds, verb: "Show", noun: "sounds", entries: sounds) { soundRows(sounds) }
                    }
                    if !drivers.isEmpty {
                        let tickable = drivers.contains { !catalog.uninstallItems(ofRow: $0.id).isEmpty }
                        group("Drivers", .drivers, verb: tickable ? "Choose" : "Show", noun: "drivers", entries: drivers) {
                            rows(drivers, category: .audioSoftware, identifier: "applicationsDriver-", revealsPlace: true)
                        }
                    }
                }
            }
        }
    }
    /// Sounds and samples: each with who it is from and its size, revealed in Finder, never chosen (Decision 151); one its
    /// vendor's installed manager can remove or move offers Open <tool> (Decision 157).
    private func soundRows(_ sounds: [InventoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sounds) { sound in
                // Its manager's line under its name, as a plug-in's "<tool> can uninstall it" line.
                let manager = model.manager(of: sound).map { tool in
                    StatusRow(text: "\(tool.name) can remove or move it", symbol: "shippingbox", identifier: "applicationsSoundManager-" + sound.id,
                              action: StatusAction(title: "Open " + tool.name, identifier: "applicationsSoundOpen-" + sound.id) { model.open(tool) })
                }
                InspectableItemRow(name: sound.name, detail: [sound.maker, sound.volume.map { "On \($0), not connected" }].compactMap { $0 }.joined(separator: " · "),
                                   size: sound.size.text, symbol: "waveform", inspected: false, inspect: nil,
                                   reveal: { model.reveal(sound.name, sound.parts.map(\.url)) }, revealIdentifier: "applicationsSoundReveal-" + sound.id,
                                   status: manager) { EmptyView() }
                    .help(sound.id)
            }
        }.padding(.bottom, CacheDropDesign.Space.md)
    }
    /// When the list of apps couldn't be read, DAWs and audio apps aren't known either: said, never shown as none (#310).
    @ViewBuilder private var appsUnreadableNote: some View {
        if model.appsUnreadable {
            StatusRow(text: "DAWs and audio apps aren’t listed: CacheDrop couldn’t read the list of apps.", identifier: "applicationsAudioAppsUnreadable")
        }
    }
    /// Plug-ins by maker (Decision 151): a maker with one product shows it directly; Other makers come last, always as a group.
    private func makers(_ plugIns: [InventoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AudioSoftware.byMaker(plugIns, sort: model.listing.sort, bytes: { size(of: $0).sortBytes }), id: \.maker) { maker in
                if maker.products.count == 1, maker.maker != nil {
                    rows(maker.products, category: .audioSoftware, identifier: "applicationsPlugIn-")
                } else {
                    group(maker.maker ?? "Other makers", .maker(maker.maker), noun: "plug-ins", entries: maker.products) {
                        rows(maker.products, category: .audioSoftware, identifier: "applicationsPlugIn-")
                    }
                }
            }
        }
    }
    /// One of Audio software's groups, or a maker: a category row with no checkbox, its rows behind "Choose <noun> · N". The
    /// section shows the badge once: a group's place for it stays empty, so its title keeps the rows' text column (Decision 175).
    private func group<Rows: View>(_ title: String, _ group: AudioGroup, verb: String = "Choose", noun: String, entries: [InventoryEntry],
                                   @ViewBuilder rows: @escaping () -> Rows) -> some View {
        let open = Binding(get: { model.openGroups.contains(group) }, set: { if $0 { model.openGroups.insert(group) } else { model.openGroups.remove(group) } })
        return VStack(alignment: .leading, spacing: 0) {
            CategoryRow(category: .audioSoftware, state: nil, title: title, detail: "", size: total(entries), enabled: true,
                        identifier: "applicationsGroup-" + group.key, itemCount: entries.count, chooseVerb: verb, chooseNoun: noun, showsBadge: false,
                        expanded: open, toggle: {}) { EmptyView() } items: { rows() }
            // Open, its last row's divider ends it.
            if !open.wrappedValue { Divider().padding(.vertical, CacheDropDesign.Space.md) }
        }
    }
    /// Audio software's groups and makers a search has a match in.
    private var groupsWithMatches: Set<AudioGroup> {
        guard model.listing.isSearching else { return [] }
        let apps = listed(model.audioApps).filter { model.listing.matches(name: $0.name, maker: $0.maker) }
        let plugIns = listed(model.plugIns + model.reasonDevices).filter { model.listing.matches(name: $0.name, maker: $0.maker) }
        var groups = Set(plugIns.map { AudioGroup.maker($0.maker) })
        if !apps.isEmpty { groups.insert(.apps) }
        if !plugIns.isEmpty { groups.insert(.plugIns) }
        if model.sounds.contains(where: { model.listing.matches(name: $0.name, maker: $0.maker) }) { groups.insert(.sounds) }
        if listed(model.drivers).contains(where: { model.listing.matches(name: $0.name, maker: $0.maker) }) { groups.insert(.drivers) }
        return groups
    }
    /// The entries the search matches, in the list's sort.
    private func arranged(_ entries: [InventoryEntry]) -> [InventoryEntry] {
        model.listing.arranged(entries, name: \.name, maker: \.maker, bytes: { size(of: $0).sortBytes })
    }
    /// Entries' size, each shared item counted once (`size(of:)`).
    private func total(_ entries: [InventoryEntry]) -> String { SizeEstimate(sum: entries.map(size(of:))).text }

    private func loading(_ id: String) -> some View { SkeletonRows(.category, count: 2, identifier: "applicationsLoading-" + id) }
    private func state(_ title: String, _ detail: String, symbol: String, id: String) -> some View {
        EmptyState(title: title, detail: detail, symbol: symbol, identifier: id, inList: true)
    }

    /// The size a row shows, and Size sorts by: shared items count on no product's row, so the page counts them once
    /// (#288, Decisions 51 and 52).
    private func size(of entry: InventoryEntry) -> SizeEstimate {
        let uninstall = catalog.uninstallItems(ofRow: entry.id)
        return uninstall.isEmpty ? entry.size : SizeEstimate(sum: uninstall.filter(\.sharedBy.isEmpty).map(SizeEstimate.init))
    }

    /// A row; an app CacheDrop can uninstall (#177) has a checkbox for the app and its files, the rest have none. One that
    /// needs a password says so (Decision 50). Its identifiers carry the entry's path, never its name, so same-named apps on
    /// two volumes stay apart (#271). `revealsPlace` gives a row with no password line its place and Reveal in Finder (a driver, #715).
    private func row(_ entry: InventoryEntry, category: StorageCategory, identifier: String, revealsPlace: Bool = false) -> some View {
        let isExpanded = Binding(get: { expanded.contains(entry.id) }, set: { if $0 { expanded.insert(entry.id) } else { expanded.remove(entry.id) } })
        let uninstall = catalog.uninstallItems(ofRow: entry.id)
        // A partly removable product also lists what stays (#176, #288): formats and support files that need a password, and AUv3s.
        let target = uninstall.lazy.compactMap(\.uninstall).first { $0.path == entry.id }
        // Its password paths hold its formats too (#354); each is listed once.
        let listed = Set(entry.parts.map(\.url.standardizedFileURL.path))
        let locked = (entry.parts.filter { !$0.removable && $0.name != PlugInFormat.auv3.rawValue }
            + (target?.passwordPaths ?? []).filter { !listed.contains(URL(fileURLWithPath: $0).standardizedFileURL.path) }.map { InventoryEntry.Part(name: URL(fileURLWithPath: $0).lastPathComponent, url: URL(fileURLWithPath: $0), size: .unknown, removable: false) })
        let auv3 = category == .apps ? [] : entry.parts.filter { $0.name == PlugInFormat.auv3.rawValue }
        let staying = uninstall.isEmpty || category == .apps ? [] : locked + auv3
        // "Choose items" counts what can be chosen, and says how many listed parts stay (#290).
        let count = uninstall.isEmpty ? entry.parts.count : uninstall.count
        return CategoryRow(category: category, state: uninstall.isEmpty ? nil : catalog.selectionState(ofRow: entry.id), title: entry.name,
                           detail: [entry.maker, entry.volume].compactMap { $0 }.joined(separator: " · "),
                           size: size(of: entry).text,
                           enabled: uninstall.isEmpty || catalog.canChoose(uninstall), identifier: identifier,
                           // An app alone is its only item: no "Choose items · 1" (#270).
                           itemCount: count > 1 || !staying.isEmpty ? count : nil, staying: staying.count,
                           icon: category == .apps ? AppIcon.of(entry.id) : nil, expanded: isExpanded,
                           toggle: { if catalog.toggleRow(entry.id) { expanded.insert(entry.id) } }) {
            if entry.needsPassword { passwordLine(entry) }
            else if !uninstall.isEmpty {
                // Its own uninstaller comes first (Decision 41); a later scan's Files from deleted apps shows what it left.
                if let tool = model.uninstaller(for: entry) {
                    StatusRow(text: category == .apps ? "Has its own uninstaller" : "\(tool.name) can uninstall it", symbol: "shippingbox", identifier: "applicationsUninstaller-" + entry.id,
                              action: StatusAction(title: "Open " + tool.name, identifier: "applicationsOpen-" + entry.id) { model.open(tool) })
                }
                // Unread is never "lists nothing" (#291).
                if target?.receiptsUnread == true {
                    StatusRow(text: "Support files stay: couldn’t read every installer receipt", symbol: "info.circle", identifier: "applicationsReceiptsUnread-" + entry.id)
                }
                // Only files of kinds known to be safe go with it (#291, Decision 53).
                if let count = target?.unrecognised, count > 0 {
                    StatusRow(text: "Holds files CacheDrop doesn’t recognize: " + (count == 1 ? "1 stays" : "\(count) stay"), symbol: "info.circle",
                              identifier: "applicationsUnrecognised-" + entry.id)
                }
                // The app, or a plug-in product's own app and its hosts (#176), each with "Quit <App>".
                if let rule = AppRuleFamily.uninstallRules.first(where: { rule in uninstall.contains { $0.ruleID == rule.id } }) {
                    PlanRunningOwners(model: catalog, rule: rule, only: Set(uninstall.compactMap(\.uninstall).flatMap { [$0.owner.name] + ($0.plugIn?.hosts ?? []).map(\.name) }))
                }
            } else if !auv3.isEmpty, auv3.count == entry.parts.count {
                // An AUv3 is part of its app: removing the app removes it (#288).
                StatusRow(text: "Goes with " + Self.app(of: auv3[0]), identifier: "applicationsInsideApp-" + entry.id)
            } else if catalog.hasScanned, !appsWaitForScan {
                // A removable app the scan didn't offer says why, rather than showing a bare row (#281).
                StatusRow(text: "Not offered: in Protected items, or changed since the scan", identifier: "applicationsNotOffered-" + entry.id)
            }
            // Where it lives, before it's ticked; a locked one's password line already reveals it (Decisions 151, 158).
            if revealsPlace, !entry.needsPassword {
                StatusRow(text: PathDisplay.shortLocation(of: URL(fileURLWithPath: entry.id), home: CatalogCleanupModel.checkHome), symbol: "folder",
                          identifier: "applicationsPlace-" + entry.id,
                          action: StatusAction(title: "Reveal in Finder", identifier: "applicationsReveal-" + entry.id) { model.reveal(entry.name, entry.parts.map(\.url)) })
            }
            // Until the scan says what can go with it, the row is dimmed rather than looking final (#303, #308).
        } items: {
            if !uninstall.isEmpty {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    ForEach(AppRuleFamily.uninstallRules.filter { rule in uninstall.contains { $0.ruleID == rule.id } }) { rule in
                        Text(rule.title).font(CacheDropDesign.TypeStyle.caption.weight(.medium))
                        CatalogItemRows(model: catalog, rule: rule, app: entry.id)
                    }
                    // A partly removable product lists what stays, with no checkbox (Decision 50).
                    ForEach(locked, id: \.url) { part in passwordLine(entry, part: part) }
                    ForEach(auv3, id: \.url) { part in
                        StatusRow(text: "\(part.name): Goes with " + Self.app(of: part), identifier: "applicationsInsideApp-" + part.url.path)
                    }
                }
            } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entry.parts, id: \.url) { part in
                    InspectableItemRow(name: part.name, detail: PathDisplay.shortLocation(of: part.url, home: CatalogCleanupModel.checkHome), size: part.size.text,
                                       // Nothing here is chosen: an inert row with its own Reveal link (#367, Decision 72).
                                       symbol: category.symbol, inspected: false, inspect: nil, detailLineLimit: 1,
                                       reveal: { model.reveal(part.name, [part.url]) }, revealIdentifier: "applicationsPartReveal-" + part.url.path) { EmptyView() }
                        .help(part.url.path)
                }
            }
            }
        }
    }

    /// "Needs your password to remove · Reveal in Finder", or "Needs <tool> or your password to remove · Open <tool>" when the
    /// vendor's tool is installed (Decision 50); for one `part` of a partly removable product, prefixed with its name (#288).
    private func passwordLine(_ entry: InventoryEntry, part: InventoryEntry.Part? = nil) -> some View {
        let tool = model.uninstaller(for: entry), id = part?.url.path ?? entry.id
        // A part's line reveals it: the row's own line already offers "Open <tool>", once (#290).
        let action = tool.flatMap { tool in part == nil ? StatusAction(title: "Open " + tool.name, identifier: "applicationsOpen-" + id) { model.open(tool) } : nil }
            ?? StatusAction(title: "Reveal in Finder", identifier: "applicationsReveal-" + id) { model.reveal(part?.name ?? entry.name, part.map { [$0.url] } ?? entry.parts.map(\.url)) }
        let text = tool.map { "Needs \($0.name) or your password to remove" } ?? "Needs your password to remove"
        return StatusRow(text: part.map { "\($0.name): " + text } ?? text, symbol: "lock", identifier: "applicationsPassword-" + id, action: action)
    }
    /// The app an AUv3 is in: "Pad" for `Pad.app/Contents/PlugIns/Pad.appex`.
    static func app(of part: InventoryEntry.Part) -> String {
        part.url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingPathExtension().lastPathComponent
    }

    private func openReview() async {
        do {
            guard try await selection.openReview(.applications, checks: selection.prepareApplicationsReview) else { return }
            approvalError = nil
        } catch { approvalError = PlanReviewError.message(for: error) }
    }
}

/// An app's own icon, as Finder shows it, read once per app: rows are drawn again on every change, and the icon never changes
/// while the page is open.
@MainActor enum AppIcon {
    private static let cache = NSCache<NSString, NSImage>()
    static func of(_ path: String) -> NSImage {
        if let icon = cache.object(forKey: path as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

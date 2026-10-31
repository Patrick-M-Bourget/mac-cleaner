import SwiftUI
import Observation
import CacheDropCore

@main
struct CacheDropApp: App {
    @NSApplicationDelegateAdaptor(CacheDropApplicationDelegate.self) private var delegate
    @StateObject private var lifecycle = AppLifecycleController.shared
    @StateObject private var alerts = AppLifecycleController.shared.alerts
    @AppStorage(PreferenceKeys.showsMenuBarItem) private var showsMenuBarItem = true
    /// Runs before AppKit finishes launching, so saved window state is ignored before it can be restored.
    /// Still's state is copied first, before anything reads CacheDrop's (#149).
    /// The first-run welcome is decided from what was there before (#158).
    init() {
        let stateExisted = LocalStateLocation.stateFolderExists
        WelcomeModel.shared.decideAtLaunch(migration: LocalStateLocation.migrateFromOldNames(), stateExisted: stateExisted)
        AppLaunchPolicy.registerDefaults()
        #if DEBUG
        try? FixtureAppPresence.prepareQuitJourney()
        #endif
    }
    var body: some Scene {
        Window("CacheDrop", id: "workspace") {
            WorkspaceView(alerts: lifecycle.alerts)
                .frame(minWidth: CacheDropDesign.Size.minimumWindow.width).background { NativeWindowContract() }
                .cacheDropButtonRule()
        }
        .defaultSize(width: CacheDropDesign.Size.defaultWindow.width, height: CacheDropDesign.Size.defaultWindow.height)
        .commands {
            #if DEBUG
            DebugGalleryCommands()
            #endif
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { lifecycle.manualUpdater.checkForUpdates() }
                    .accessibilityIdentifier("checkForUpdatesMenu")
            }
            CommandGroup(after: .windowArrangement) {
                Button("Show CacheDrop") { lifecycle.openWorkspace?() }
            }
            CommandGroup(after: .toolbar) {
                ScanAgainCommand(lifecycle: lifecycle)
            }
            CommandGroup(after: .help) {
                Button("Welcome to CacheDrop") { lifecycle.openWorkspace?(); WelcomeModel.shared.isShowing = true }
            }
        }
        #if DEBUG
        Window("Design gallery", id: "design-gallery") { DesignGallery() }
            .defaultSize(width: CacheDropDesign.Size.defaultWindow.width, height: CacheDropDesign.Size.defaultWindow.height)
        #endif
        Settings { CacheDropSettingsView() }
        // #131: free space in the menu bar, shown unless turned off in Settings.
        // The binding ignores no-op writes: MenuBarExtra writes it back on every update, and an unconditional
        // UserDefaults write re-renders the App, which loops.
        MenuBarExtra(isInserted: Binding(get: { showsMenuBarItem }, set: { if $0 != showsMenuBarItem { showsMenuBarItem = $0 } })) {
            CacheDropMenuBarMenu(lifecycle: lifecycle)
        } label: { CacheDropMenuBarLabel(capacity: lifecycle.capacity) }
    }
}

#if DEBUG
/// Developer-only access to synthetic examples, separate from product navigation.
private struct DebugGalleryCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Design gallery") { openWindow(id: "design-gallery") }
                .accessibilityIdentifier("openDesignGallery")
        }
    }
}
#endif

/// ⌘R: disabled while a scan or cleanup runs, with the reason as its tooltip (#310).
private struct ScanAgainCommand: View {
    let lifecycle: AppLifecycleController
    var body: some View {
        Button("Scan again") { lifecycle.scanAgain?() }.keyboardShortcut("r")
            .disabled(lifecycle.scanAgainBlockedReason != nil).help(lifecycle.scanAgainBlockedReason ?? "")
    }
}

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", smartClean = "Smart clean", plan = "Cleanup plan", applications = "Applications", growth = "Storage trends", history = "History", locations = "Locations & access"
    var id: String { rawValue }
    /// ⌘1–⌘7 follow the sidebar order (#127, #141), Applications above Storage trends (#525). Low-space alerts live in the Settings window (#131).
    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .smartClean: "2"
        case .plan: "3"
        case .growth: "5"
        case .applications: "4"
        case .history: "6"
        case .locations: "7"
        }
    }
    var symbol: String {
        switch self {
        case .growth: "chart.line.uptrend.xyaxis"
        case .overview: "internaldrive"
        case .smartClean: "sparkles"
        case .plan: "checklist"
        case .history: "clock"
        case .locations: "folder.badge.gearshape"
        case .applications: "square.grid.2x2"
        }
    }
}

/// Window restoration within this process never restores cleanup authority after Quit.
@MainActor @Observable final class WorkspaceNavigation {
    var destination = Destination.overview
    var explorerVisible = false
    var explorerCaller = Destination.overview
    var planReturnsToExplorer = false
    var scanOrigin = Destination.overview
    var recoveryVisible = false
    var recoveryCaller = Destination.overview
    let historyModel = CleanupHistoryModel()
    var historyExpandedRuns: Set<UUID> = []
    /// Each page's scroll position, written on every scroll frame and read back only when the page is shown again. Not
    /// observed: a write must never re-render the workspace, which made Overview, its heaviest page, lag while scrolling.
    @ObservationIgnored var historyOffset: CGPoint?
    @ObservationIgnored var growthOffset: CGPoint?
    var planReturnsToGrowth = false
    @ObservationIgnored var overviewOffset: CGPoint?
    @ObservationIgnored var locationsOffset: CGPoint?
    var savedDataVisible = false
    var savedDataCaller = Destination.history
    @ObservationIgnored var savedDataOffset: CGPoint?
    /// Overview's App-managed storage page (Decision 25).
    var appManagedVisible = false
}

private struct WorkspaceView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var alerts: StorageAlertsController
    @State private var navigationState = AppLifecycleController.shared.workspaceNavigation
    private var destination: Destination { get { navigationState.destination } nonmutating set { navigationState.destination = newValue } }
    @State private var appearance = AppLifecycleController.shared.appearance
    @State private var expanded = false
    @State private var explorer = AppLifecycleController.shared.inspection
    @State private var selection = AppLifecycleController.shared.selection
    @State private var recovery = AppLifecycleController.shared.recovery
    private var recoveryVisible: Bool { get { navigationState.recoveryVisible } nonmutating set { navigationState.recoveryVisible = newValue } }
    private var explorerVisible: Bool { get { navigationState.explorerVisible } nonmutating set { navigationState.explorerVisible = newValue } }
    @State private var protectedItemsVisible = false
    /// Where the page on show keeps its scroll position; nil for a page that keeps none. Out of the view builder, where
    /// the if-chain timed out CI's type checker (#264).
    private var scrollOffset: Binding<CGPoint?>? {
        if recoveryVisible { return nil }
        if navigationState.savedDataVisible { return $navigationState.savedDataOffset }
        if protectedItemsVisible || navigationState.appManagedVisible { return nil }
        switch destination {
        case .history: return $navigationState.historyOffset
        case .growth: return $navigationState.growthOffset
        case .overview: return $navigationState.overviewOffset
        case .locations: return $navigationState.locationsOffset
        case .plan, .smartClean, .applications: return nil
        }
    }
    /// Which page the scroll view shows, so each keeps its own scroll position. Out of the view builder, where the
    /// chained ternary timed out CI's type checker (#264).
    private var scrollIdentity: String {
        if recoveryVisible { return "recovery" }
        if navigationState.savedDataVisible { return "local-records" }
        if protectedItemsVisible { return "exclusions" }
        if navigationState.appManagedVisible { return "app-managed" }
        return destination.rawValue
    }
    @State private var overviewCloudExpanded = false
    @State private var overviewShowsAllCategories = false
    @State private var locationsModel = AppLifecycleController.shared.locations
    private var explorerContext: StorageExplorerContext { AppLifecycleController.shared.locationsExplorer }
    @State private var planPresentation = AppLifecycleController.shared.planPresentation
    @State private var smartCleanPresentation = AppLifecycleController.shared.smartCleanPresentation
    private var explorerCaller: Destination { get { navigationState.explorerCaller } nonmutating set { navigationState.explorerCaller = newValue } }
    private var planReturnsToExplorer: Bool { get { navigationState.planReturnsToExplorer } nonmutating set { navigationState.planReturnsToExplorer = newValue } }
    private var scanOrigin: Destination { get { navigationState.scanOrigin } nonmutating set { navigationState.scanOrigin = newValue } }
    @State private var locationToForget: RememberedScope?
    /// Work running in the background, earliest first, for every screen's bottom bar (Decision 46).
    @State private var backgroundWork = BackgroundWork()
    /// The bar's line; a new folder's scan carries its phase and count, the explorer's recheck only "Checking for changes…";
    /// every folder scan has the Stop scan x, and Return to scan away from its screen (#235, #364).
    private var backgroundWorkStatus: BackgroundWorkStatus? {
        guard let line = backgroundWork.line(catalogProgress: selection.catalog.scanProgressText,
                                             folderPhase: explorer.isScanning ? explorer.progress?.phase ?? .enumerating : nil,
                                             inspectedEntries: explorer.progress?.visitedEntries) else { return nil }
        guard line.runsFolderScan else { return BackgroundWorkStatus(line: line) }
        return BackgroundWorkStatus(line: line, stop: { explorer.cancel() }, returnToScan: scanReturnAction)
    }
    /// What runs now, each labelled by what it is (#230): a recheck, or a new folder's scan.
    private var runningTasks: Set<BackgroundJob> {
        var tasks: Set<BackgroundJob> = []
        if selection.catalog.isScanning { tasks.insert(.catalogScan) }
        if explorer.isRechecking { tasks.insert(.folderRecheck) }
        else if explorer.isScanning { tasks.insert(.folderScan(folder: explorer.scope?.lastPathComponent ?? "folder")) }
        return tasks
    }
    @State private var capacity = AppLifecycleController.shared.capacity
    @Bindable private var welcome = WelcomeModel.shared
    private var startupCapacity: StartupCapacityReading? { capacity.reading }
    /// The destination's own page shows: no records, recovery, inspection, exclusions or app-managed page covers it.
    private func showsOwnPage(_ page: Destination, evenUnderAppManaged: Bool = false) -> Bool {
        destination == page && !navigationState.savedDataVisible && !recoveryVisible && !explorerVisible && !protectedItemsVisible
            && (evenUnderAppManaged || !navigationState.appManagedVisible)
    }
    private var showsSmartClean: Bool { showsOwnPage(.smartClean) }
    private var showsApplications: Bool { showsOwnPage(.applications) }
    /// The plan is the one page app-managed storage never covers: Explore storage's Review plan and Start a new plan switch
    /// to it directly, without `navigate(_:)`, so `appManagedVisible` may still be set then, and the plan must show anyway.
    private var showsPlan: Bool { showsOwnPage(.plan, evenUnderAppManaged: true) }
    /// The toolbar's note, which only reports state (Decision 25: no toolbar subtitles). A screen returns nil to show none.
    private var contextLabel: String? {
        if selection.workspaceRunning { return "Cleaning up…" }
        if navigationState.savedDataVisible && !recoveryVisible { return "" }
        if recoveryVisible { return "Review interrupted cleanup" }
        if selection.hasWorkspaceResult && showsPlan { return nil }
        if explorerVisible { return nil }
        if protectedItemsVisible { return nil }
        if navigationState.appManagedVisible { return nil }
        switch destination {
        case .overview: return nil
        case .smartClean, .plan, .applications: return nil
        case .history, .locations: return "" // Decision 25: no toolbar subtitles
        case .growth: return ""
        }
    }

    /// The sidebar, the divider and the page; `body` adds the modifiers, so neither expression grows too large to type-check (Xcode 26).
    private var workspace: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            page
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            AppBrand().padding(.horizontal, CacheDropDesign.Space.sm).padding(.bottom, CacheDropDesign.Space.xl)
            Text("Storage").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.horizontal, CacheDropDesign.Space.sm)
            ForEach(Destination.allCases.filter { $0 != .locations }) { navigation($0) }
            Text("Settings").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.horizontal, CacheDropDesign.Space.sm).padding(.top, CacheDropDesign.Space.xl)
            navigation(.locations)
            Spacer()
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                Label("This Mac", systemImage: "laptopcomputer").font(CacheDropDesign.TypeStyle.note)
                CapacityMeter(available: startupCapacity?.available, total: startupCapacity?.total, compact: true,
                              breakdown: selection.catalog.breakdown(available: startupCapacity?.available, total: startupCapacity?.total, trash: TrashModel.shared.contents))
                Text(capacity.sidebarObservationText).font(CacheDropDesign.TypeStyle.sidebarNote).foregroundStyle(.secondary)
                    .lineLimit(1).frame(height: CacheDropDesign.Size.sidebarCaptionHeight, alignment: .leading)
                    .help(capacity.observationText).accessibilityLabel(capacity.observationText)
                    .accessibilityIdentifier("sidebarCapacityObservation")
                Text(capacity.statusText.isEmpty ? " " : capacity.statusText).font(CacheDropDesign.TypeStyle.sidebarNote).foregroundStyle(.secondary)
                    .frame(height: CacheDropDesign.Size.sidebarCaptionHeight, alignment: .leading)
            }.padding(.horizontal, CacheDropDesign.Space.sm)
        
        }
        .padding(.horizontal, CacheDropDesign.Space.md).padding(.vertical, CacheDropDesign.Space.lg)
        .frame(width: CacheDropDesign.Size.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background { ChromeSurface(role: .sidebar) }
    }

    /// The page on the right: the appearance notice, then the destination with its bar.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppearancePreferenceNotice(notice: appearance.notice, retry: { appearance.retrySaving() })
                .padding(.horizontal, CacheDropDesign.Space.page)
            if explorerVisible {
                explorerPage
            } else if showsPlan {
                planPage
            } else if showsSmartClean {
                smartCleanPage
            } else if showsApplications {
                applicationsPage
            } else {
            scrollingPage
            pageBar
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CacheDropDesign.reading)
    }

    var body: some View {
        workspace
        .environment(\.cacheDropBackgroundWork, backgroundWorkStatus)
        .onChange(of: runningTasks, initial: true) { _, tasks in backgroundWork.update(running: tasks) }
        .onChange(of: selection.catalog.selectionRevisions) { _, _ in AppLifecycleController.shared.hasPendingPlan = selection.hasPendingChoicesOnAnyPage }
        // Launch stays on Overview; its banner opens Recovery, which checks against disk (#309).
        .task { _ = await recovery.loadOnce() }
        // The launch scan, whichever page opens first; later scans start in the model when something changes (#306).
        .task { await selection.catalog.scanIfNeeded() }
        .task { locationsModel.load() }
        .onChange(of: locationsModel.scopes) { _, _ in
            explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        }
        .onAppear {
            AppLifecycleController.shared.openWorkspace = { openWindow(id: "workspace") }
            AppLifecycleController.shared.scanAgain = { if canScanAgain { scanAgain() } }
            AppLifecycleController.shared.openSmartClean = { navigate(.smartClean) }
            selection.catalog.scanRememberedFolders = { scanRememberedFolders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cacheDropAlertOpened)) { _ in destination = .overview; navigationState.savedDataVisible = false; navigationState.appManagedVisible = false; protectedItemsVisible = false; recoveryVisible = false; explorerVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await alerts.activated() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await selection.catalog.rescanIfFullDiskAccessGranted() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in Task { await alerts.activated() } }
        .toolbar { contextToolbar }
        .sheet(isPresented: $welcome.isShowing) { FirstRunWelcomeView(model: welcome, catalog: selection.catalog) }
    }

    @ToolbarContentBuilder private var contextToolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) { contextToolbarLabel }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { contextToolbarLabel }
        }
    }
    @ViewBuilder private var contextToolbarLabel: some View {
        // Only the context label: a scan's progress lives in the bottom bar, so nothing here changes when one starts (#235).
        if let contextLabel, !contextLabel.isEmpty { Text(contextLabel).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1) }
    }

    /// Return to scan, hidden on the screen the scan belongs to: where it started, and for the recheck of the selected
    /// locations also Explore storage, which shows them (#364).
    private var scanReturnAction: (() -> Void)? {
        let atOrigin = destination == scanOrigin && !navigationState.savedDataVisible && !navigationState.appManagedVisible && !explorerVisible && !protectedItemsVisible && !recoveryVisible
        if atOrigin || (explorer.isRechecking && explorerVisible) { return nil }
        return { returnToScanOrigin() }
    }

    private func returnToScanOrigin() {
        destination = scanOrigin
        navigationState.savedDataVisible = false; navigationState.appManagedVisible = false
        explorerVisible = false
        protectedItemsVisible = false; recoveryVisible = false
        planReturnsToExplorer = false
    }

    private func navigate(_ value: Destination) {
        navigationState.planReturnsToGrowth = false
        destination = value
        planReturnsToExplorer = false
        if value == .plan && selection.showsRun(for: .plan) { startNewPlan() }
        if value == .smartClean && selection.showsRun(for: .smartClean) { selection.dismissResult() }
        if value == .applications && selection.showsRun(for: .applications) { selection.dismissResult() }
        navigationState.savedDataVisible = false; navigationState.appManagedVisible = false
        protectedItemsVisible = false
        recoveryVisible = false; navigationState.recoveryCaller = .overview; explorerVisible = false
    }

    private func navigation(_ value: Destination) -> some View {
        CacheDropSidebarRow(title: value.rawValue, symbol: value.symbol, selected: destination == value,
                        accent: value == .growth ? CacheDropDesign.purple : value == .plan ? CacheDropDesign.teal : value == .history ? .secondary : CacheDropDesign.blue,
                        selectedCategories: value == .plan ? selection.actionableSelectedCategoryCount : nil) {
            navigate(value)
        }.keyboardShortcut(value.shortcut, modifiers: .command)
    }

    private func chooseFolderForScan() {
        if let url = ExploreStorage.chooseFolder() {
            alerts.dismissOpenedAlert()
            let isDownloads = isDownloadsLocation(url)
            if locationsModel.remember(url, downloads: isDownloads) {
                scanOrigin = destination
                explorer.scan(url)
            }
        }
    }

    private var overviewObservation: ScanResult? {
        explorer.overviewObservation(including: locationsModel.included.map { URL(fileURLWithPath: $0.path) }, observations: selection.scans, unavailable: selection.unavailableScopes)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Storage overview", subtitle: "A clearer picture of what’s on your Mac.")
            ScanHistoryRecordingNotice()
            if let context = alerts.openedAlertContext {
                SummarySurface {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                        StatusRow(text: context.observedAt.map { "Space was low at \($0.formatted(date: .omitted, time: .shortened))" } ?? "Space was low", symbol: "bell", identifier: "openedStorageAlert")
                        HStack {
                            Button("Scan again") { alerts.dismissOpenedAlert(); scanAgain() }.disabled(!canScanAgain).help(scanAgainHelp)
                            Button("Dismiss", action: alerts.dismissOpenedAlert)
                        }
                    }
                }
            }
            if recovery.requiresReview {
                SummarySurface {
                    HStack {
                        StatusRow(text: "Interrupted cleanup needs review", symbol: "exclamationmark.circle", role: .caution)
                        Button("Review interrupted cleanup") { openRecovery(caller: .overview) }
                    }
                }
            }
            StartupVolumeCard(catalog: selection.catalog, open: { openPlan($0.categories) })
            locationRecoveries
            SettingsUnreadableNotice(model: selection.catalog)
            overviewRecommendations
            scannedLocations
        }.task { await TrashModel.shared.refresh() }
    }

    private var overviewRecommendations: some View {
        let catalog = selection.catalog
        let summary = catalog.overview
        // The scanned folders' iCloud inventory stands in for an empty iCloud row (Decision 76).
        let inventory = overviewObservation?.cloudInventory
        let presentation = summary?.presentation(cloudInventory: inventory)
        let showsCloudInventory = presentation?.showsCloudInventory == true
        // Every category, empty ones last as "Empty" (#372).
        let rows = presentation?.rows ?? []
        let more = max(0, rows.count - CatalogOverview.leadingRowCount)
        let shown = overviewShowsAllCategories ? rows : Array(rows.prefix(CatalogOverview.leadingRowCount))
        return VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recommended for review").font(CacheDropDesign.TypeStyle.section)
                    Spacer(minLength: CacheDropDesign.Space.md)
                    // Nothing known yet: the size is "—" and the rows are skeletons (#308).
                    // What would go to the Trash isn't counted; the tooltip says so rather than a line under the list (#425).
                    Text(summary.map { recommendedText($0.recommended) } ?? CacheDropDesign.noValue)
                        .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("overviewRecommendedTotal")
                        .help(trashNotCounted(summary))
                    // The recommended plan lives on its own page (#141): one quiet link to it. Its size is on that page, so
                    // the header shows one figure (#425).
                    if summary != nil, !catalog.recommendedCandidates.isEmpty {
                        Button("Smart clean ›") { navigate(.smartClean) }
                            .buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption).accessibilityIdentifier("overviewSmartClean")
                    }
                }
                if catalog.settingsUnreadable {
                    EmptyView() // Nothing was read: the line above says why, never "nothing" (#310).
                } else if summary == nil {
                    SkeletonRows(.review, identifier: "overviewSkeleton")
                } else {
                    // Everything empty: one line above the list, which stays in place (#372).
                    if !showsCloudInventory, rows.allSatisfy(\.isEmpty), !catalog.isScanning {
                        NothingToCleanUp(identifier: "overviewEmpty", compact: true, action: EmptyStateAction("Explore storage") { exploreStorage(caller: .overview) })
                    }
                    if showsCloudInventory || !shown.isEmpty {
                        RecommendationGroup {
                            if showsCloudInventory {
                                overviewCloudRow
                                if overviewCloudExpanded, let report = overviewObservation?.cloudInventory { CloudInventoryView(report: report).padding(CacheDropDesign.Space.md) }
                            }
                            // Every catalog category, largest first and empty ones last; categories are data in CacheDropCore.
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                                if index > 0 || showsCloudInventory { Divider().padding(.horizontal, CacheDropDesign.Space.lg) }
                                catalogRow(row)
                            }
                            if more > 0 {
                                Divider().padding(.horizontal, CacheDropDesign.Space.lg)
                                Button(overviewShowsAllCategories ? "Show fewer" : "Show \(more) more") { overviewShowsAllCategories.toggle() }
                                    .buttonStyle(.link).font(CacheDropDesign.TypeStyle.note).padding(CacheDropDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("overviewShowMore")
                            }
                        }.waitingForScan(catalog.isScanning)
                    }
                }
                // Places macOS protects (Safari's cache) without Full Disk Access: one line, never a 0-byte row.
                if !catalog.notAccessibleRules.isEmpty {
                    FullDiskAccessNote(places: catalog.notAccessibleRules.map(\.title)).accessibilityIdentifier("overviewNotAccessible")
                }
                TrashNote()
                if !catalog.appManaged.isEmpty {
                    RecommendationGroup {
                        StorageReviewRow(category: .managed, title: "App-managed storage", detail: "", value: CacheDropDesign.items(catalog.appManaged.count),
                                         actionTitle: "Review app-managed storage", action: { navigationState.appManagedVisible = true },
                                         identifier: "overviewAppManaged", mutedValue: true)
                    }.waitingForScan(catalog.isScanning)
                }
            }
    }
    @ViewBuilder private func catalogRow(_ row: CatalogOverview.Row) -> some View {
        if row.isEmpty {
            // Found nothing: "Empty", muted, with no Review link (#372); "Needs access" when it couldn't be read (62); "—" while a
            // scan may still find something.
            StorageReviewRow(category: row.category.storageCategory, title: row.category.overviewTitle, detail: row.category.overviewDetail,
                             value: selection.catalog.isScanning ? CacheDropDesign.noValue : row.needsAccess ? "Needs access" : "Empty",
                             identifier: "overviewCategory-" + row.id, mutedValue: true)
        } else {
            foundCatalogRow(row)
        }
    }
    private func foundCatalogRow(_ row: CatalogOverview.Row) -> some View {
        let onApplications = CleanupSelections.Source.page(of: row) == .applications
        // "Selected" only once its ticks differ from the recommended default, on whichever page they were made (#349).
        let selected = selection.catalog.selectionDiffersFromRecommended(row.rules)
        return StorageReviewRow(category: row.category.storageCategory, title: row.category.overviewTitle, detail: row.category.overviewDetail,
            value: row.valueText,
            meaning: row.estimate == .unknown ? "Couldn’t be measured" : selected ? "Selected"
                : row.rules.allSatisfy { $0.action == .delete } ? "Rebuildable" : row.rules.allSatisfy { $0.action == .evict } ? "Local copies" : "Review files",
            actionTitle: "Review " + StorageTrendsPresentation.inSentence(row.category) + (onApplications ? " in Applications" : " in the Cleanup plan"),
            // Files from deleted apps are on the Applications page (Decision 51).
            action: { if onApplications { navigate(.applications) } else { navigate(.plan); planPresentation.expandedCategories.insert(row.category) } },
            identifier: "overviewCategory-" + row.id)
    }
    /// Opens the Cleanup plan from Smart clean's "Not included" note, with the category open when one is named.
    private func openPlan(_ category: CatalogCategory?) { openPlan(category.map { [$0] } ?? []) }
    /// Opens the Cleanup plan with these categories open, as a meter segment does (#164).
    private func openPlan(_ categories: [CatalogCategory]) {
        navigate(.plan)
        planPresentation.expandedCategories.formUnion(categories)
    }
    /// The recommended total's tooltip: what would go to the Trash isn't counted in it (#425).
    private func trashNotCounted(_ summary: CatalogOverview?) -> String {
        guard let trash = summary?.proposedForTrash, trash != .measured(0) else { return "" }
        return "Doesn’t include " + trash.text + " that would go to the Trash."
    }
    /// SPEC section 6: an estimate, and an upper bound because clones share blocks.
    private func recommendedText(_ estimate: SizeEstimate) -> String {
        let size = SizeFormatter.text(estimate, upperBound: true)
        if case .atLeast = estimate { return size + " · Some sizes unknown" }
        return size
    }

    private var overviewCloudRow: some View {
        let action: (() -> Void)? = overviewObservation == nil ? nil : { overviewCloudExpanded.toggle() }
        let value = overviewObservation.map { result in
            let report = result.cloudInventory
            return report.totalIsUnknown ? "Unknown" : SizeFormatter.text(report.localAllocatedBytes)
        } ?? "Not scanned"
        return StorageReviewRow(category: .cloud, title: "Downloaded iCloud files", detail: "Copies of iCloud files kept on this Mac", value: value, meaning: "On this Mac", actionTitle: overviewCloudExpanded ? "Hide iCloud files" : "Review iCloud files", action: action, identifier: "overviewCloudFinding")
    }
    private func scanKnownLocations() {
        scanLocations(locationsModel.included)
    }
    /// The same conditions that enable the Overview's Scan again button.
    private var canScanAgain: Bool { AppLifecycleController.shared.scanAgainBlockedReason == nil }
    /// "A scan is already running" while one runs (#310).
    private var scanAgainHelp: String { AppLifecycleController.shared.scanAgainBlockedReason ?? "" }
    /// Rechecks capacity, the catalog's known locations and any included folders. Read-only.
    private func scanAgain() {
        capacity.request(.manual)
        Task { await selection.catalog.scan() }
        Task { await TrashModel.shared.refresh() }
        if !locationsModel.included.isEmpty { scanKnownLocations() }
    }
    /// The remembered, included folders, scanned along with the catalog at launch and after a cleanup (#125).
    private func scanRememberedFolders() {
        locationsModel.load()
        if !locationsModel.included.isEmpty { scanKnownLocations() }
    }
    /// A location that can't be reached keeps its recovery row near the top, since it affects the results below it (#223, #231, #345).
    private var locationRecoveries: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            // One row per problem (#223, #231): each unavailable location names itself and carries the fix.
            ForEach(locationsModel.recoveries, id: \.scope.id) { scope, status in
                Group {
                if scope.isBuiltIn {
                    // Built-in Downloads is never picked (#342, #388): Full Disk Access is its fix, not Choose again….
                    HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.sm) {
                        StatusRow(text: recoveryText(scope, status: status), symbol: "info.circle", role: .caution, identifier: "overviewLocationRecovery").fixedSize()
                        FullDiskAccessLink(title: "Grant Full Disk Access")
                        Spacer(minLength: 0)
                    }
                } else {
                    StatusRow(text: recoveryText(scope, status: status), symbol: "info.circle", role: .caution,
                        identifier: "overviewLocationRecovery", action: StatusAction(title: "Choose again…", identifier: "overviewChooseAgain") {
                        renewAndScan(scope)
                    }).disabled(explorer.isScanning || selection.workspaceRunning)
                }
                }.help(locationsModel.bookmarkFailures[scope.id]?.summary ?? "") // Why its bookmark failed, to diagnose (#342, #387).
            }
            if let notice = locationsModel.notice { StatusRow(text: notice, symbol: "info.circle", role: .caution) }
            if let message = explorer.message, !recoveryRowCovers(explorer.unavailableScope) {
                StatusRow(text: message, symbol: "info.circle")
            }
        }
    }
    /// Scanned locations (#345), under the recommended categories: one row per location with its size and an Explore link, and
    /// its own reason when the scan couldn't read everything (#358).
    private var scannedLocations: some View {
        let locations = overviewLocations
        return VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.md) {
                Text("Scanned locations").font(CacheDropDesign.TypeStyle.section)
                Spacer(minLength: CacheDropDesign.Space.md)
                // Always there (#320): with no scanned folder it leads to Locations & access, where folders are added.
                Button("Explore storage") { exploreStorage(caller: .overview) }
                    .buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption).disabled(selection.workspaceRunning)
                // One clear action: pick a folder, remember it and scan it now (#125).
                Button("Scan a folder…", systemImage: "folder.badge.plus", action: chooseFolderForScan)
                    .buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption)
                    .disabled(explorer.isScanning || selection.workspaceRunning).accessibilityIdentifier("overviewScanFolder")
            }
            if locations.isEmpty {
                // A location in recovery is chosen: its row at the top says what's wrong (#388), so only say this when none is.
                if locationsModel.recoveries.isEmpty {
                    Text("No folders chosen yet").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("overviewNoLocations")
                }
            } else {
                RecommendationGroup {
                    ForEach(Array(locations.enumerated()), id: \.element.scope) { index, location in
                        if index > 0 { Divider().padding(.horizontal, CacheDropDesign.Space.lg) }
                        scannedLocationRow(location)
                    }
                }.waitingForScan(explorer.isScanning)
            }
        }
    }
    private func scannedLocationRow(_ location: ScannedLocation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Built-in Downloads says so (#342); it has no Remove anywhere.
            StorageReviewRow(category: location.isBuiltIn ? .downloads : .files, title: location.name,
                             detail: [location.isBuiltIn ? "Built in" : nil, location.notes].compactMap { $0 }.joined(separator: " · "), value: location.value,
                             actionTitle: "Explore " + location.name, action: location.bytes == nil ? nil : { openExplorer(caller: .overview, at: location.scope) },
                             identifier: "overviewLocation:" + location.scope.path, mutedValue: location.bytes == nil)
                .help(location.scope.path)
            if let problem = location.problem {
                // One caution line; Scan again is its own link, Full Disk Access opens its sheet beside it (#358).
                HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.sm) {
                    StatusRow(text: problem, symbol: "exclamationmark.circle", role: .caution, identifier: "overviewLocationProblem:" + location.scope.path,
                              action: location.action == .scanAgain ? StatusAction(title: "Scan again", identifier: "overviewLocationScanAgain", isDisabled: !canScanAgain, action: scanAgain) : nil)
                        .fixedSize(horizontal: location.action == .grantFullDiskAccess, vertical: false)
                    if location.action == .grantFullDiskAccess {
                        FullDiskAccessLink(title: "Grant Full Disk Access")
                        Spacer(minLength: 0)
                    }
                }.padding([.horizontal, .bottom], CacheDropDesign.Space.lg)
            }
        }
    }
    /// Included locations with their latest current scan; one with a recovery row is left to that row, so nothing shows twice.
    private var overviewLocations: [ScannedLocation] {
        let recovering = Set(locationsModel.recoveries.map(\.scope.id))
        return locationsModel.included.filter { !recovering.contains($0.id) }.map { scope in
            let url = URL(fileURLWithPath: scope.path).standardizedFileURL
            let current = selection.unavailableScopes.contains(url) ? nil
                // Scans are keyed by the URL each scan was given; compare standardized paths on both sides (#388).
                : selection.scans.first { $0.key.standardizedFileURL == url }?.value ?? explorer.scopeReports.first { $0.current.scope.standardizedFileURL == url }?.current
            return ScannedLocation(scope: url, scan: current, isBuiltIn: scope.isBuiltIn)
        }
    }
    /// Overview's recovery rows, for the explorer to mark those locations' last observations as gone (#249).
    private var explorerUnavailable: [ExplorerUnavailableLocation] {
        locationsModel.recoveries.map { scope, status in
            // Built-in Downloads is checked again rather than picked (#388).
            ExplorerUnavailableLocation(scope: URL(fileURLWithPath: scope.path).standardizedFileURL, reason: locationsModel.recoveryReasons[scope.id] ?? status.reason,
                                        actionTitle: scope.isBuiltIn ? "Check again" : "Choose again…") { if scope.isBuiltIn { scanLocations([scope]) } else { renewAndScan(scope) } }
        }
    }
    /// "Folder not found · last scanned <time>" for a deleted or moved folder, "Access unavailable" for an unreadable one (#254).
    private func recoveryText(_ scope: RememberedScope, status: RememberedLocations.AccessStatus) -> String {
        let observed = Array(selection.scans.values) + explorer.scopeReports.map(\.current)
        return UnavailableScannedFolder.overviewText(name: URL(fileURLWithPath: scope.path).lastPathComponent,
            reason: locationsModel.recoveryReasons[scope.id] ?? status.reason,
            lastObserved: UnavailableScannedFolder.lastObserved(URL(fileURLWithPath: scope.path), in: observed).map(ExplorerUnavailableLocation.format))
    }
    /// Choose again…, then scan the renewed location in place (#223).
    private func renewAndScan(_ scope: RememberedScope) {
        if chooseAgain(scope), let renewed = locationsModel.included.first(where: { $0.id == scope.id }) { scanLocations([renewed]) }
    }
    /// Whether an unavailable location already has its own recovery row, which says what the grey message would (#231).
    private func recoveryRowCovers(_ scope: URL?) -> Bool {
        guard let scope else { return false }
        return locationsModel.recoveries.contains { URL(fileURLWithPath: $0.scope.path).standardizedFileURL == scope }
    }
    /// Renews a remembered location's access: the user picks the same folder again. Shared by Locations & access and Overview (#223).
    @discardableResult private func chooseAgain(_ scope: RememberedScope) -> Bool {
        guard let url = ExploreStorage.chooseFolder(remembering: true) else { return false }
        if url.standardizedFileURL.path == scope.path { return locationsModel.remember(url, downloads: isDownloadsLocation(url)) }
        locationsModel.message = "Choose the same location to renew access. Use Add folder for a different location."
        return false
    }
    private func isDownloadsLocation(_ url: URL) -> Bool {
        guard let root = locationsModel.builtInDownloads else { return false }
        return url.standardizedFileURL.pathComponents.starts(with: URL(fileURLWithPath: root.path).standardizedFileURL.pathComponents)
    }
    private func scanLocations(_ scopes: [RememberedScope]) {
        guard !AppLifecycleController.shared.updateInstallation.blocksNewWork, !explorer.isScanning, !selection.workspaceRunning else { return }
        // Asked while History holds the maintenance lease: rechecked once it lets go, with access resolved then (#310).
        if AppLifecycleController.shared.maintenanceInProgress {
            AppLifecycleController.shared.afterMaintenance.waitFor(.folderRecheck) { scanLocations(scopes) }
            return
        }
        let leases = scopes.compactMap { locationsModel.resolve($0) }
        let resolved = Set(leases.map { $0.url.standardizedFileURL.path })
        for scope in scopes where !resolved.contains(scope.path) {
            let url = URL(fileURLWithPath: scope.path)
            selection.suspendScope(url); explorer.markUnavailable(url)
        }
        guard !scopes.isEmpty else { return }
        scanOrigin = destination
        let unavailable = scopes.filter { !resolved.contains($0.path) }.map { URL(fileURLWithPath: $0.path) }
        explorer.scanAgain(scopes: leases.map(\.url), leases: leases, unavailable: unavailable)
    }
    /// Opens Explore storage; from a location's Explore link (#320), at that folder.
    private func openExplorer(caller: Destination, at folder: URL? = nil) {
        explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        if let folder { explorerContext.openLocation(folder) }
        explorerCaller = caller; explorerVisible = true; planReturnsToExplorer = false
    }
    /// Explore storage with its bar: "N selected", then Add to cleanup plan once something is ticked (#320).
    @ViewBuilder private var explorerPage: some View {
        StorageExplorerView(model: explorer, selection: selection, context: explorerContext,
            caller: explorerCaller.rawValue, back: { explorerVisible = false; destination = explorerCaller }, unavailable: explorerUnavailable)
        ActionStrip(message: explorerSelectedMessage) {
            Button("Add to cleanup plan", action: addExplorerSelectionToPlan).buttonStyle(.borderedProminent).disabled(!canAddExplorerSelection)
        }
    }
    private var explorerSelectedMessage: String? { explorerSelectedCount > 0 ? "\(explorerSelectedCount) selected" : nil }
    private var canAddExplorerSelection: Bool { explorerSelectedCount > 0 && !selection.workspaceRunning }

    private var planPage: some View {
        let backDestination: String = navigationState.planReturnsToGrowth ? Destination.growth.rawValue : explorerContext.title
        return LiveCleanupPlanView(selection: selection,
            viewHistory: { destination = .history }, newPlan: startNewPlan,
            reviewRecovery: { openRecovery(caller: .plan) },
            backToExplorer: planBack,
            backToExplorerDestination: backDestination,
            presentation: planPresentation, exploreStorage: { exploreStorage(caller: .plan) },
            openApplications: { navigate(.applications) })
    }

    private var smartCleanPage: some View {
        SmartCleanView(selection: selection, openPlan: { openPlan($0) }, viewHistory: { navigate(.history) }, reviewRecovery: { openRecovery(caller: .smartClean) },
                       presentation: smartCleanPresentation, scanAgain: { if canScanAgain { scanAgain() } })
    }

    private var applicationsPage: some View {
        ApplicationsView(selection: selection, model: ApplicationsModel.shared, viewHistory: { navigate(.history) }, reviewRecovery: { openRecovery(caller: .applications) },
                         openPlan: { categories in openPlan(categories); if let first = categories.first { planPresentation.reveal(first) } })
    }

    /// The pages that scroll above the bar: Recovery, Local records, Protected items, App-managed storage and the sidebar destinations.
    @ViewBuilder private var scrollingPage: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            if recoveryVisible {
                CleanupRecoveryView(model: recovery, back: BackButton(destination: navigationState.savedDataVisible ? "Saved data" : navigationState.recoveryCaller.rawValue) {
                    recoveryVisible = false; destination = navigationState.recoveryCaller; navigationState.recoveryCaller = .overview
                }, viewHistory: { navigate(.history) })
            } else if navigationState.savedDataVisible {
                SavedDataView(model: navigationState.historyModel, showRecovery: { openRecovery(caller: navigationState.savedDataCaller) }, didReset: didResetSavedData,
                                 back: BackButton(destination: navigationState.savedDataCaller.rawValue) {
                                     navigationState.savedDataVisible = false
                                     destination = navigationState.savedDataCaller
                                 })
            } else if protectedItemsVisible {
                ProtectedItemsView(model: ProtectedItemsModel.shared, back: BackButton(destination: Destination.locations.rawValue, enabled: !ProtectedItemsModel.shared.editingBlocked) {
                    protectedItemsVisible = false; destination = .locations
                })
            } else if navigationState.appManagedVisible {
                AppManagedStorageView(model: selection.catalog) { navigationState.appManagedVisible = false }
            } else {
                switch destination {
                case .growth: StorageTrendsHistoryView(model: StorageTrendsHistoryModel.shared, catalog: selection.catalog, scanNow: { if canScanAgain { scanAgain() } },
                                                    reviewTitle: growthReview.title, review: growthReview.open)
                case .overview: overview
                case .plan, .smartClean, .applications: EmptyView()
                case .history: history
                case .locations: locations
                }
            }
        }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                if let offset = scrollOffset { DestinationViewport(offset: offset).frame(width: 0, height: 0) }
            }
    }.id(scrollIdentity)
    }

    /// The bottom bar under a scrolling page.
    @ViewBuilder private var pageBar: some View {
    Group {
        if protectedItemsVisible {
            ActionStrip(message: "Protecting an item never changes it.") {
                if ProtectedItemsModel.shared.preview != nil {
                    Button("Cancel") { ProtectedItemsModel.shared.preview = nil }.disabled(ProtectedItemsModel.shared.editingBlocked)
                    Button("Protect") { Task { await ProtectedItemsModel.shared.save() } }.buttonStyle(.borderedProminent).disabled(ProtectedItemsModel.shared.editingBlocked)
                } else {
                    Button("Choose file or folder…") { Task { await ProtectedItemsModel.shared.choose() } }.buttonStyle(.borderedProminent).disabled(ProtectedItemsModel.shared.editingBlocked).accessibilityIdentifier("chooseExclusion")
                }
            }
        } else if recoveryVisible {
            ActionStrip()
        } else if navigationState.savedDataVisible {
            ActionStrip()
        } else if destination == .overview && !navigationState.appManagedVisible {
            // Scan again sits in the bar, as on Storage trends (#311).
            ActionStrip(message: nil) {
                Button("Scan again", action: scanAgain).disabled(!canScanAgain).help(scanAgainHelp).accessibilityIdentifier("overviewScanAgain")
            }
        } else if destination == .growth {
            ActionStrip(message: nil) {
                Button("Scan again", action: scanAgain).disabled(!canScanAgain).help(scanAgainHelp)
                    .accessibilityIdentifier("growthScanAgain")
            }
        } else {
            ActionStrip()
        }
    }
    }

    /// Storage trends' Review link on its growth card (#351, #461): the category that grew most, opened and scrolled to where it
    /// can be cleaned (the plan, or Applications for files from deleted apps), named in its accessibility label and tooltip; the
    /// plan alone when that category offers nothing now.
    private var growthReview: (title: String, open: () -> Void) {
        let grew = StorageTrendsHistoryModel.shared.comparison?.mostGrowth?.category
        if let grew, let row = selection.catalog.leftoversRow, row.category == grew {
            return ("Review " + StorageTrendsPresentation.inSentence(grew) + " in Applications", { navigate(.applications) })
        }
        let returnHere = { navigationState.planReturnsToGrowth = true }
        guard let grew, selection.catalog.plans(grew) else {
            return ("Review plan", { navigate(.plan); returnHere() })
        }
        return ("Review " + StorageTrendsPresentation.inSentence(grew) + " in the Cleanup plan", { navigate(.plan); returnHere(); planPresentation.reveal(grew) })
    }
    /// The plan's back button: to Storage trends or Explore storage when the plan was opened from there, otherwise none.
    private var planBack: (() -> Void)? {
        if navigationState.planReturnsToGrowth { return { navigationState.planReturnsToGrowth = false; destination = .growth } }
        if planReturnsToExplorer { return { explorerVisible = true; planReturnsToExplorer = false } }
        return nil
    }

    /// Explore storage's "Add to cleanup plan" (#320): opens the plan on Large and old files, with a way back to the explorer.
    private func addExplorerSelectionToPlan() {
        explorerVisible = false
        planReturnsToExplorer = explorerCaller != .plan
        planPresentation.expandedCategories.insert(UserFiles.rule.category)
        destination = .plan
    }

    /// Opens Explore storage, or Locations & access when no included folder has been scanned (#320, #321).
    private func exploreStorage(caller: Destination) {
        if hasScannedFolder { openExplorer(caller: caller) } else { navigate(.locations) }
    }
    /// An included location that has been scanned, so Explore storage has something to show.
    private func isScanned(_ scope: RememberedScope) -> Bool {
        scope.isIncluded && (selection.scans[URL(fileURLWithPath: scope.path)] != nil || explorer.scopeReports.contains { $0.current.scope.path == scope.path })
    }
    private var hasScannedFolder: Bool { locationsModel.included.contains(where: isScanned) }
    /// Large and old files ticked for the plan, which the explorer's bar counts.
    private var explorerSelectedCount: Int { selection.catalog.pickedCandidates.filter { selection.catalog.isSelected($0) }.count }
    private func startNewPlan() {
        planPresentation.reset(); selection.startNewPlan(); planReturnsToExplorer = false; explorerVisible = false; destination = .plan
        Task { await explorer.resetSession() }
    }

    private func openRecovery(caller: Destination) {
        navigationState.recoveryCaller = caller
        destination = caller
        recoveryVisible = true
        Task { await recovery.refresh() }
    }

    private func openSavedData(caller: Destination) {
        navigationState.savedDataCaller = caller
        navigationState.savedDataOffset = nil
        navigationState.savedDataVisible = true
        recoveryVisible = false
        destination = caller
    }

    private func didResetSavedData() {
        explorerVisible = false
        protectedItemsVisible = false
    }

    private var history: some View {
        CleanupHistoryView(model: navigationState.historyModel, expandedRuns: $navigationState.historyExpandedRuns,
            showRecovery: { openRecovery(caller: .history) }, goOverview: { navigate(.overview) })
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Locations & access", subtitle: "Folders CacheDrop scans at launch and when you scan again.")
            ScanHistoryRecordingNotice()
            HStack {
                Button("Add folder…", action: chooseFolderForScan).disabled(explorer.isScanning || selection.workspaceRunning)
                Button("Scan selected locations") { scanLocations(locationsModel.included) }
                    .disabled(locationsModel.included.isEmpty || explorer.isScanning || selection.workspaceRunning)
            }
            if locationsModel.scopes.isEmpty { EmptyState(title: "No locations yet", detail: "Add a folder to scan it now and each time CacheDrop opens.", symbol: "folder.badge.plus") }
            ForEach(locationsModel.scopes) { scope in
                LocationScopeRow(name: URL(fileURLWithPath: scope.path).lastPathComponent, path: scope.path,
                    status: (scope.isBuiltIn ? "Built in · " : "") + locationStatus(scope), overlap: locationOverlap(scope), included: Binding(get: { scope.isIncluded }, set: { included in
                        if locationsModel.setIncluded(included, scope: scope) { selection.suspendScope(URL(fileURLWithPath: scope.path)) }
                    }), enabled: !explorer.isScanning && !selection.workspaceRunning, fixed: scope.isBuiltIn) {
                    HStack {
                        if isScanned(scope), locationsModel.statuses[scope.id]?.needsRecovery != true {
                            Button("Explore") { openExplorer(caller: .locations, at: URL(fileURLWithPath: scope.path)) }
                                .buttonStyle(.link).accessibilityIdentifier("locationExplore:" + scope.path)
                        }
                        if locationsModel.statuses[scope.id]?.needsRecovery == true {
                            // A row's actions are links (#311).
                            if scope.isBuiltIn { FullDiskAccessLink(title: "Grant Full Disk Access") } // Never picked (#388).
                            else { Button("Choose again…") { chooseAgain(scope) }.buttonStyle(.link) }
                            Button("Scan again") { scanLocations([scope]) }.buttonStyle(.link).disabled(!scope.isIncluded)
                        }
                        // Built-in Downloads can't be forgotten (#342).
                        if !scope.isBuiltIn {
                            Menu("More") {
                                Button("Forget location") { locationToForget = scope }
                            }.menuStyle(.borderlessButton).fixedSize().accessibilityIdentifier("locationActions:" + scope.path)
                        }
                    }
                }
                if locationsModel.statuses[scope.id]?.needsRecovery == true,
                   let previous = explorer.scopeReports.first(where: { $0.current.scope.path == scope.path })?.lastComplete {
                    Text("Last full scan: " + previous.observedAt.formatted() + " · May be out of date").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
            if let message = locationsModel.message { StatusRow(text: message, symbol: "info.circle") }
            FullDiskAccessSetting()
            ProtectedItemsEntry { protectedItemsVisible = true }
            SavedDataEntry { openSavedData(caller: .locations) }
        }.confirmationDialog("Forget location?", isPresented: Binding(get: { locationToForget != nil }, set: { if !$0 { locationToForget = nil } }), titleVisibility: .visible) {
            if let scope = locationToForget {
                Button("Forget location", role: .destructive) { if locationsModel.forget(scope) { selection.suspendScope(URL(fileURLWithPath: scope.path)) }; locationToForget = nil }
                Button("Cancel", role: .cancel) { locationToForget = nil }
            }
        } message: {
            if let scope = locationToForget {
                Text("Forget " + URL(fileURLWithPath: scope.path).lastPathComponent + "? CacheDrop stops scanning it. No files will be deleted.")
            }
        }
    }
    private func locationOverlap(_ scope: RememberedScope) -> String? {
        let components = URL(fileURLWithPath: scope.path).standardizedFileURL.pathComponents
        let overlaps = locationsModel.scopes.contains { other in
            guard other.id != scope.id else { return false }
            let candidate = URL(fileURLWithPath: other.path).standardizedFileURL.pathComponents
            return components.starts(with: candidate) || candidate.starts(with: components)
        }
        return overlaps ? "Overlaps another location · Files in both are counted once." : nil
    }
    private func locationStatus(_ scope: RememberedScope) -> String {
        if !scope.isIncluded { return "Left out of scans" }
        if let status = locationsModel.statuses[scope.id], status.needsRecovery { return status.text }
        if let scan = selection.scans[URL(fileURLWithPath: scope.path)] {
            if selection.unavailableScopes.contains(scan.scope.standardizedFileURL) { return "Scan again to update" }
            let scanned = "Scanned " + scan.observedAt.formatted(date: .omitted, time: .shortened)
            return scan.isComplete ? scanned : scanned + " · Not fully read"
        }
        return "Not scanned"
    }
}

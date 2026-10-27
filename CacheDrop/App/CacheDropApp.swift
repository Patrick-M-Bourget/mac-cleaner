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
    }
    var body: some Scene {
        Window("CacheDrop", id: "workspace") {
            WorkspaceView(alerts: lifecycle.alerts)
                .frame(minWidth: 900).background { NativeWindowContract() }
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show CacheDrop") { lifecycle.openWorkspace?() }
            }
            CommandGroup(after: .toolbar) {
                Button("Scan again") { lifecycle.scanAgain?() }.keyboardShortcut("r")
            }
            CommandGroup(after: .help) {
                Button("Welcome to CacheDrop") { lifecycle.openWorkspace?(); WelcomeModel.shared.isShowing = true }
            }
        }
        Settings { CacheDropSettingsView() }
        // #131: free space in the menu bar, shown unless turned off in Settings.
        // The binding ignores no-op writes: MenuBarExtra writes it back on every update, and an unconditional
        // UserDefaults write re-renders the App, which loops.
        MenuBarExtra(isInserted: Binding(get: { showsMenuBarItem }, set: { if $0 != showsMenuBarItem { showsMenuBarItem = $0 } })) {
            CacheDropMenuBarMenu(lifecycle: lifecycle)
        } label: { CacheDropMenuBarLabel(capacity: lifecycle.capacity) }
    }
}

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", smartClean = "Smart clean", plan = "Cleanup plan", growth = "Storage trends", history = "History", locations = "Locations & access"
    var id: String { rawValue }
    /// ⌘1–⌘6 follow the sidebar order (#127, #141). Low-space alerts live in the Settings window (#131).
    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .smartClean: "2"
        case .plan: "3"
        case .growth: "4"
        case .history: "5"
        case .locations: "6"
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
    var downloadsExplorerActive = true
    var recoveryVisible = false
    var recoveryCaller = Destination.overview
    let historyModel = CleanupHistoryModel()
    var historyExpandedRuns: Set<UUID> = []
    var historyOffset: CGPoint?
    var growthOffset: CGPoint?
    var planReturnsToGrowth = false
    var routeGeneration = UUID()
    var overviewOffset: CGPoint?
    var locationsOffset: CGPoint?
    var localRecordsVisible = false
    var localRecordsCaller = Destination.history
    var localRecordsOffset: CGPoint?
    var diagnosticsVisible = false
    var diagnosticsCaller = Destination.overview
    var diagnosticsOffset: CGPoint?
    var diagnosticsModel = DiagnosticsModel()
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
    @State private var folderInspection = AppLifecycleController.shared.inspection
    @State private var selection = AppLifecycleController.shared.selection
    @State private var recovery = AppLifecycleController.shared.recovery
    private var recoveryVisible: Bool { get { navigationState.recoveryVisible } nonmutating set { navigationState.recoveryVisible = newValue } }
    private var nativeInspectionVisible: Bool { get { navigationState.explorerVisible } nonmutating set { navigationState.explorerVisible = newValue } }
    @State private var exclusionsVisible = false
    private var diagnosticsVisible: Bool { get { navigationState.diagnosticsVisible } nonmutating set { navigationState.diagnosticsVisible = newValue } }
    /// Where the page on show keeps its scroll position; nil for a page that keeps none. Out of the view builder, where
    /// the if-chain timed out CI's type checker (#264).
    private var scrollOffset: Binding<CGPoint?>? {
        if recoveryVisible { return nil }
        if diagnosticsVisible { return $navigationState.diagnosticsOffset }
        if navigationState.localRecordsVisible { return $navigationState.localRecordsOffset }
        if exclusionsVisible || navigationState.appManagedVisible { return nil }
        switch destination {
        case .history: return $navigationState.historyOffset
        case .growth: return $navigationState.growthOffset
        case .overview: return $navigationState.overviewOffset
        case .locations: return $navigationState.locationsOffset
        case .plan, .smartClean: return nil
        }
    }
    /// Which page the scroll view shows, so each keeps its own scroll position. Out of the view builder, where the
    /// chained ternary timed out CI's type checker (#264).
    private var scrollIdentity: String {
        if recoveryVisible { return "recovery" }
        if diagnosticsVisible { return "diagnostics" }
        if navigationState.localRecordsVisible { return "local-records" }
        if navigationState.appManagedVisible { return "app-managed" }
        return destination.rawValue
    }
    @State private var overviewCloudExpanded = false
    @State private var overviewShowsAllCategories = false
    private var diagnostics: DiagnosticsModel { get { navigationState.diagnosticsModel } nonmutating set { navigationState.diagnosticsModel = newValue } }
    @State private var locationsModel = AppLifecycleController.shared.locations
    private var explorerContext: StorageExplorerContext { navigationState.downloadsExplorerActive ? AppLifecycleController.shared.downloadsExplorer : AppLifecycleController.shared.locationsExplorer }
    @State private var planPresentation = AppLifecycleController.shared.planPresentation
    @State private var smartCleanPresentation = AppLifecycleController.shared.smartCleanPresentation
    private var explorerCaller: Destination { get { navigationState.explorerCaller } nonmutating set { navigationState.explorerCaller = newValue } }
    private var planReturnsToExplorer: Bool { get { navigationState.planReturnsToExplorer } nonmutating set { navigationState.planReturnsToExplorer = newValue } }
    private var scanOrigin: Destination { get { navigationState.scanOrigin } nonmutating set { navigationState.scanOrigin = newValue } }
    @State private var locationToForget: RememberedScope?
    /// Work running in the background, earliest first, for every screen's bottom bar (Decision 46).
    @State private var backgroundWork = BackgroundWork()
    /// The bar's line; a folder scan's carries its phase and count, Stop scan, and Return to scan away from its screen (#235).
    private var backgroundWorkStatus: BackgroundWorkStatus? {
        guard let line = backgroundWork.line(catalogProgress: selection.catalog.scanProgressText,
                                             folderPhase: folderInspection.isScanning ? folderInspection.progress?.phase ?? .enumerating : nil,
                                             inspectedEntries: folderInspection.progress?.visitedEntries) else { return nil }
        guard line.runsFolderScan else { return BackgroundWorkStatus(line: line) }
        return BackgroundWorkStatus(line: line, stop: { folderInspection.cancel() }, returnToScan: scanReturnAction)
    }
    /// What runs now, each labelled by what it is (#230): a recheck, or a new folder's scan.
    private var runningTasks: Set<BackgroundJob> {
        var tasks: Set<BackgroundJob> = []
        if selection.catalog.isScanning { tasks.insert(.catalogScan) }
        if folderInspection.isRechecking { tasks.insert(.folderRecheck) }
        else if folderInspection.isScanning { tasks.insert(.folderScan(folder: folderInspection.scope?.lastPathComponent ?? "folder")) }
        return tasks
    }
    @State private var capacity = AppLifecycleController.shared.capacity
    @Bindable private var welcome = WelcomeModel.shared
    private var startupCapacity: StartupCapacityReading? { capacity.reading }
    private var showsSmartClean: Bool { destination == .smartClean && !navigationState.localRecordsVisible && !recoveryVisible && !nativeInspectionVisible && !diagnosticsVisible && !exclusionsVisible && !navigationState.appManagedVisible }
    private var showsPlan: Bool { destination == .plan && !navigationState.localRecordsVisible && !recoveryVisible && !nativeInspectionVisible && !diagnosticsVisible && !exclusionsVisible }
    /// The toolbar's note, which only reports state (Decision 25: no toolbar subtitles). A screen returns nil to show none.
    private var contextLabel: String? {
        if selection.workspaceRunning { return "Running approved cleanup" }
        if navigationState.localRecordsVisible && !recoveryVisible { return "" }
        if diagnosticsVisible { return "Redacted diagnostics · Explicit local Save" }
        if recoveryVisible { return "Recovery review · Recorded facts only" }
        if selection.hasWorkspaceResult && showsPlan { return nil }
        if nativeInspectionVisible { return nil }
        if exclusionsVisible { return "Custom scan exclusions" }
        if navigationState.appManagedVisible { return nil }
        switch destination {
        case .overview: return nil
        case .smartClean, .plan: return nil
        case .history, .locations: return "" // Decision 25: no toolbar subtitles
        case .growth: return ""
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                AppBrand().padding(.horizontal, CacheDropDesign.Space.sm).padding(.bottom, CacheDropDesign.Space.xl)
                Text("Storage").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.horizontal, CacheDropDesign.Space.sm)
                ForEach(Destination.allCases.filter { $0 != .locations }) { navigation($0) }
                Text("Settings").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.horizontal, CacheDropDesign.Space.sm).padding(.top, CacheDropDesign.Space.xl)
                navigation(.locations)
                Spacer()
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                    Label("This Mac", systemImage: "laptopcomputer").font(.callout)
                    CapacityMeter(available: startupCapacity?.available, total: startupCapacity?.total, compact: true,
                                  breakdown: selection.catalog.breakdown(available: startupCapacity?.available, total: startupCapacity?.total, trash: TrashModel.shared.contents))
                    Text(capacity.sidebarObservationText).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).frame(height: 14, alignment: .leading)
                        .help(capacity.observationText).accessibilityLabel(capacity.observationText)
                        .accessibilityIdentifier("sidebarCapacityObservation")
                    Text(capacity.statusText.isEmpty ? " " : capacity.statusText).font(.caption2).foregroundStyle(.secondary)
                        .frame(height: 14, alignment: .leading)
                }.padding(.horizontal, CacheDropDesign.Space.sm)

            }
            .padding(.horizontal, CacheDropDesign.Space.md).padding(.vertical, CacheDropDesign.Space.lg)
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background { ChromeSurface(role: .sidebar) }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                AppearancePreferenceNotice(notice: appearance.notice, retry: { appearance.retrySaving() })
                    .padding(.horizontal, CacheDropDesign.Space.page)
                if nativeInspectionVisible {
                    StorageExplorerView(model: folderInspection, selection: selection, context: explorerContext,
                        caller: explorerCaller.rawValue, back: { nativeInspectionVisible = false; destination = explorerCaller }, unavailable: explorerUnavailable)
                    ActionStrip(message: nil) {
                        Button("Review plan") {
                            nativeInspectionVisible = false
                            planReturnsToExplorer = explorerCaller != .plan
                            destination = .plan
                        }.buttonStyle(.borderedProminent)
                    }
                } else if showsPlan {
                    LiveCleanupPlanView(selection: selection,
                        viewHistory: { destination = .history }, newPlan: startNewPlan,
                        reviewRecovery: { openRecovery(caller: .plan) },
                        backToExplorer: navigationState.planReturnsToGrowth ? { navigationState.planReturnsToGrowth = false; destination = .growth } : planReturnsToExplorer ? { nativeInspectionVisible = true; planReturnsToExplorer = false } : nil,
                        backToExplorerDestination: navigationState.planReturnsToGrowth ? Destination.growth.rawValue : explorerContext.title,
                        presentation: planPresentation)
                } else if showsSmartClean {
                    SmartCleanView(selection: selection, openPlan: { openPlan($0) }, viewHistory: { navigate(.history) }, reviewRecovery: { openRecovery(caller: .smartClean) },
                                   presentation: smartCleanPresentation)
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
                        if recoveryVisible {
                            CleanupRecoveryView(model: recovery, back: BackButton(destination: navigationState.localRecordsVisible ? "Local records" : navigationState.recoveryCaller.rawValue) {
                                recoveryVisible = false; destination = navigationState.recoveryCaller; navigationState.recoveryCaller = .overview
                            })
                        } else if navigationState.localRecordsVisible {
                            LocalRecordsView(model: navigationState.historyModel, showRecovery: { openRecovery(caller: navigationState.localRecordsCaller) }, didReset: didResetLocalRecords, reviewDiagnostics: nil,
                                             back: BackButton(destination: navigationState.localRecordsCaller.rawValue) {
                                                 navigationState.localRecordsVisible = false
                                                 destination = navigationState.localRecordsCaller
                                             })
                        } else if exclusionsVisible {
                            ExclusionsView(model: ExclusionsModel.shared, back: BackButton(destination: Destination.locations.rawValue, enabled: !ExclusionsModel.shared.editingBlocked) {
                                exclusionsVisible = false; destination = .locations
                            })
                        } else if diagnosticsVisible {
                            DiagnosticsView(model: diagnostics, back: BackButton(destination: navigationState.diagnosticsCaller.rawValue, enabled: !diagnostics.isSaving) {
                                diagnosticsVisible = false; navigationState.localRecordsVisible = false
                                destination = navigationState.diagnosticsCaller
                            })
                        } else if navigationState.appManagedVisible {
                            AppManagedStorageView(model: selection.catalog) { navigationState.appManagedVisible = false }
                        } else {
                            switch destination {
                            case .growth: GrowthHistoryView(model: GrowthHistoryModel.shared, catalog: selection.catalog)
                            case .overview: overview
                            case .plan, .smartClean: EmptyView()
                            case .history: history
                            case .locations: locations
                            }
                        }
                    }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
                        .background(alignment: .topLeading) {
                            if let offset = scrollOffset { DestinationViewport(offset: offset).frame(width: 0, height: 0) }
                        }
                }.id(scrollIdentity)

                Group {
                    if exclusionsVisible {
                        ActionStrip(message: "Exclusions change scan coverage. Files stay unchanged.") {
                            if ExclusionsModel.shared.preview != nil {
                                Button("Cancel") { ExclusionsModel.shared.preview = nil }.disabled(ExclusionsModel.shared.editingBlocked)
                                Button("Save exclusion") { Task { await ExclusionsModel.shared.save() } }.buttonStyle(.borderedProminent).disabled(ExclusionsModel.shared.editingBlocked)
                            } else {
                                Button("Choose file or folder…") { Task { await ExclusionsModel.shared.choose() } }.buttonStyle(.borderedProminent).disabled(ExclusionsModel.shared.editingBlocked).accessibilityIdentifier("chooseExclusion")
                            }
                        }
                    } else if diagnosticsVisible {
                        ActionStrip(message: "It stays on this Mac unless you save it.") {
                            Button("Save diagnostics…") { Task { await diagnostics.save() } }.buttonStyle(.borderedProminent).disabled(diagnostics.export == nil || diagnostics.isSaving)
                        }
                    } else if recoveryVisible {
                        ActionStrip(message: "Records are kept. Nothing resumes automatically.") { EmptyView() }
                    } else if navigationState.localRecordsVisible {
                        ActionStrip()
                    } else if destination == .growth {
                        ActionStrip(message: nil) {
                            Button("Scan again", action: scanAgain).disabled(selection.catalog.isScanning || folderInspection.isScanning || selection.workspaceRunning || !selection.catalog.canEdit)
                                .accessibilityIdentifier("growthScanAgain")
                            Button("Review plan") { navigate(.plan); navigationState.planReturnsToGrowth = true }.buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("growthReviewOptions")
                        }
                    } else if showsPlan {
                        ActionStrip(message: nil) { Button("Review cleanup") {}.disabled(true) }
                    } else {
                        ActionStrip()
                    }
                }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CacheDropDesign.reading)
        }
        .environment(\.cacheDropBackgroundWork, backgroundWorkStatus)
        .onChange(of: runningTasks, initial: true) { _, tasks in backgroundWork.update(running: tasks) }
        .onChange(of: selection.catalog.selectionRevision) { _, _ in AppLifecycleController.shared.hasPendingPlan = selection.hasPendingChoices }
        .task { if await recovery.loadOnce() { openRecovery(caller: .overview, refresh: false) } }
        .task { locationsModel.load() }
        .onChange(of: locationsModel.scopes) { _, _ in
            explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
            explorerContext.downloadsScopes = Set(locationsModel.includedDownloads.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        }
        .onAppear {
            AppLifecycleController.shared.openWorkspace = { openWindow(id: "workspace") }
            AppLifecycleController.shared.scanAgain = { if canScanAgain { scanAgain() } }
            AppLifecycleController.shared.openSmartClean = { navigate(.smartClean) }
            selection.catalog.scanRememberedFolders = { scanRememberedFolders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cacheDropAlertOpened)) { _ in destination = .overview; navigationState.localRecordsVisible = false; navigationState.appManagedVisible = false; exclusionsVisible = false; diagnosticsVisible = false; recoveryVisible = false; nativeInspectionVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await alerts.activated() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await selection.catalog.rescanIfFullDiskAccessGranted() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in Task { await alerts.activated() } }
        .toolbar { contextToolbar }
        .sheet(isPresented: $welcome.isShowing) { FirstRunWelcomeView(model: welcome) { AppLifecycleController.shared.scanAgain?() } }
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

    private var scanReturnAction: (() -> Void)? {
        let atOrigin = destination == scanOrigin && !navigationState.localRecordsVisible && !navigationState.appManagedVisible && !nativeInspectionVisible && !diagnosticsVisible && !exclusionsVisible && !recoveryVisible
        if atOrigin { return nil }
        return { returnToScanOrigin() }
    }

    private func returnToScanOrigin() {
        destination = scanOrigin
        navigationState.localRecordsVisible = false; navigationState.appManagedVisible = false
        nativeInspectionVisible = false; diagnosticsVisible = false
        exclusionsVisible = false; recoveryVisible = false
        planReturnsToExplorer = false
    }

    private func navigate(_ value: Destination) {
        navigationState.routeGeneration = UUID()
        navigationState.planReturnsToGrowth = false
        destination = value
        planReturnsToExplorer = false
        if value == .plan && selection.showsRun(for: .plan) { startNewPlan() }
        if value == .smartClean && selection.showsRun(for: .smartClean) { selection.dismissResult() }
        navigationState.localRecordsVisible = false; navigationState.appManagedVisible = false
        diagnosticsVisible = false; exclusionsVisible = false
        recoveryVisible = false; navigationState.recoveryCaller = .overview; nativeInspectionVisible = false
    }

    private func navigation(_ value: Destination) -> some View {
        CacheDropSidebarRow(title: value.rawValue, symbol: value.symbol, selected: destination == value,
                        accent: value == .growth ? CacheDropDesign.purple : value == .plan ? CacheDropDesign.teal : value == .history ? .secondary : CacheDropDesign.blue,
                        selectedCategories: value == .plan ? selection.actionableSelectedCategoryCount : nil) {
            navigate(value)
        }.keyboardShortcut(value.shortcut, modifiers: .command)
    }

    private func chooseFolderForScan() {
        if let url = FolderInspection.chooseFolder() {
            alerts.dismissOpenedAlert()
            let isDownloads = isDownloadsLocation(url)
            if locationsModel.remember(url, downloads: isDownloads) {
                scanOrigin = destination
                folderInspection.scan(url)
            }
        }
    }

    private var overviewObservation: ScanResult? {
        folderInspection.overviewObservation(including: locationsModel.included.map { URL(fileURLWithPath: $0.path) }, observations: selection.scans, unavailable: selection.unavailableScopes)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            HStack(alignment: .top) {
                PageHeader(title: "Storage overview", subtitle: "A clearer picture of what’s on your Mac.")
                Spacer(minLength: CacheDropDesign.Space.md)
                Button("Scan again", action: scanAgain).disabled(!canScanAgain)
            }
            ScanHistoryRecordingNotice()
            if let context = alerts.openedAlertContext {
                SummarySurface {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                        StatusRow(text: context.observedAt.map { "Space was low at \($0.formatted(date: .omitted, time: .shortened))" } ?? "Space was low", symbol: "bell", identifier: "openedStorageAlert")
                        HStack {
                            Button("Scan again") { alerts.dismissOpenedAlert(); scanAgain() }.disabled(!canScanAgain)
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
            VolumeSummary(available: startupCapacity?.available, total: startupCapacity?.total,
                          observation: capacity.observationText, status: capacity.statusText,
                          refreshTitle: "Try again", refreshing: capacity.isRefreshing,
                          refresh: { capacity.request(.manual) },
                          breakdown: selection.catalog.breakdown(available: startupCapacity?.available, total: startupCapacity?.total, trash: TrashModel.shared.contents),
                          open: { openPlan($0.categories) })
            scannedLocations
            overviewRecommendations
        }.task { await selection.catalog.scanIfNeeded() }
            .task { await TrashModel.shared.refresh() }
    }

    private var overviewRecommendations: some View {
        let catalog = selection.catalog
        let summary = catalog.overview
        let rows = summary?.visibleRows ?? []
        let more = max(0, rows.count - CatalogOverview.leadingRowCount)
        let shown = overviewShowsAllCategories ? rows : Array(rows.prefix(CatalogOverview.leadingRowCount))
        // The scanned folders' iCloud inventory, when the catalog found no local copies of its own.
        // Hidden at 0 bytes, like any category; unknown is never 0.
        let showsCloudInventory = overviewObservation.map { $0.cloudInventory.localAllocatedBytes != 0 } == true && !rows.contains { $0.category == .icloud }
        return VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recommended for review").font(CacheDropDesign.TypeStyle.section)
                    Spacer(minLength: CacheDropDesign.Space.md)
                    Text(summary.map { recommendedText($0.recommended) } ?? (catalog.isScanning ? "Checking known locations…" : "Not measured yet"))
                        .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("overviewRecommendedTotal")
                    // The recommended plan lives on its own page (#141): one quiet link to it.
                    if summary != nil, !catalog.recommendedCandidates.isEmpty {
                        Button("Smart clean · " + catalog.recommendedSizeText + " ›") { navigate(.smartClean) }
                            .buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption).accessibilityIdentifier("overviewSmartClean")
                    }
                }
                if showsCloudInventory || !shown.isEmpty {
                    RecommendationGroup {
                        if showsCloudInventory {
                            overviewCloudRow
                            if overviewCloudExpanded, let report = overviewObservation?.cloudInventory { CloudInventoryView(report: report).padding(CacheDropDesign.Space.md) }
                        }
                        // The largest catalog categories that found something; categories are data in CacheDropCore.
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                            if index > 0 || showsCloudInventory { Divider().padding(.horizontal, CacheDropDesign.Space.lg) }
                            catalogRow(row)
                        }
                        if more > 0 {
                            Divider().padding(.horizontal, CacheDropDesign.Space.lg)
                            Button(overviewShowsAllCategories ? "Show fewer" : "Show \(more) more") { overviewShowsAllCategories.toggle() }
                                .buttonStyle(.link).font(.callout).padding(CacheDropDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("overviewShowMore")
                        }
                    }
                } else if summary != nil, !catalog.isScanning {
                    Text("Nothing to review in the known locations.").font(.callout).foregroundStyle(.secondary)
                }
                // Places macOS protects (Safari's cache) without Full Disk Access: one line, never a 0-byte row.
                if !catalog.notAccessibleRules.isEmpty {
                    FullDiskAccessNote(places: catalog.notAccessibleRules.map(\.title)).accessibilityIdentifier("overviewNotAccessible")
                }
                TrashNote()
                if let trash = summary?.proposedForTrash, trash != .measured(0) {
                    Text("Estimated release excludes " + trash.text + " proposed for Trash.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                }
                if !catalog.guidance.isEmpty {
                    RecommendationGroup {
                        StorageReviewRow(category: .managed, title: "App-managed storage", detail: "", value: CacheDropDesign.items(catalog.guidance.count),
                                         actionTitle: "Review app-managed storage", action: { navigationState.appManagedVisible = true },
                                         identifier: "overviewAppManaged", mutedValue: true)
                    }
                }
            }
    }
    private func catalogRow(_ row: CatalogOverview.Row) -> some View {
        let inPlan = row.rules.contains { selection.catalog.isSelected($0) }
        return StorageReviewRow(category: row.category.storageCategory, title: row.category.overviewTitle, detail: row.category.overviewDetail,
            value: row.valueText,
            meaning: row.estimate == .unknown ? "Couldn’t be measured" : inPlan ? "In cleanup plan"
                : row.rules.allSatisfy { $0.action == .delete } ? "Rebuildable" : row.rules.allSatisfy { $0.action == .evict } ? "Local copies" : "Review files",
            actionTitle: "Review \(row.category.overviewTitle) in the cleanup plan",
            action: { navigate(.plan); planPresentation.expandedCategories.insert(row.category) },
            identifier: "overviewCategory-" + row.id)
    }
    /// Opens the Cleanup plan from Smart clean's "Not included" note, with the category open when one is named.
    private func openPlan(_ category: CatalogCategory?) { openPlan(category.map { [$0] } ?? []) }
    /// Opens the Cleanup plan with these categories open, as a meter segment does (#164).
    private func openPlan(_ categories: [CatalogCategory]) {
        navigate(.plan)
        planPresentation.expandedCategories.formUnion(categories)
    }
    /// SPEC section 6: an estimate, and an upper bound because clones share blocks.
    private func recommendedText(_ estimate: SizeEstimate) -> String {
        switch estimate {
        case .measured(let bytes): "Up to " + catalogBytes(bytes) + " estimated"
        case .about(let bytes): "About " + catalogBytes(bytes) + " estimated"
        case .atLeast(let bytes): "At least " + catalogBytes(bytes) + " estimated · Some sizes unknown"
        case .unknown: "Size unknown"
        }
    }

    private var overviewCloudRow: some View {
        let action: (() -> Void)? = overviewObservation == nil ? nil : { overviewCloudExpanded.toggle() }
        let value = overviewObservation.map { result in
            let report = result.cloudInventory
            return report.unknownMembershipCount > 0 || report.unknownStateCount > 0 ? "Unknown" : overviewBytes(report.localAllocatedBytes)
        } ?? "Not inspected"
        return StorageReviewRow(category: .cloud, title: "Downloaded iCloud files", detail: "Local copies in this location · Cleanup unavailable.", value: value, meaning: "Local allocation · Unknown metadata stays unknown", actionTitle: overviewCloudExpanded ? "Hide iCloud inventory" : "Review iCloud inventory", action: action, identifier: "overviewCloudFinding")
    }
    private func overviewBytes(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "Unknown"
    }
    private func scanKnownLocations() {
        scanLocations(locationsModel.included)
    }
    /// Rechecks capacity, the catalog's known locations and any included folders. Read-only.
    /// The same conditions that enable the Overview's Scan again button.
    private var canScanAgain: Bool { !folderInspection.isScanning && !selection.workspaceRunning && selection.catalog.canEdit }
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
    private var scannedLocations: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.sm) {
                Text("Scanned locations").font(.caption.weight(.medium))
                Text(scannedSummary).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(overviewObservation?.scope.path ?? "").accessibilityIdentifier("overviewScopeCoverage")
                if overviewObservation != nil {
                    Button("Explore storage") { openExplorer(downloads: false, caller: .overview) }.buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption).disabled(selection.workspaceRunning)
                }
                Spacer(minLength: 0)
                // One clear action: pick a folder, remember it and scan it now (#125).
                Button("Scan a folder…", systemImage: "folder.badge.plus", action: chooseFolderForScan).controlSize(.small)
                    .disabled(folderInspection.isScanning || selection.workspaceRunning).accessibilityIdentifier("overviewScanFolder")
            }
            if selection.scans.values.contains(where: { !$0.isComplete }) || overviewObservation.map({ $0.excludedEntryCount > 0 || $0.hasUnmeasuredContents }) == true {
                StatusRow(text: "Some locations have partial coverage. Uninspected bytes remain unknown.", symbol: "exclamationmark.circle", role: .caution)
            }
            // One row per problem (#223, #231): each unavailable location names itself and carries the fix.
            ForEach(locationsModel.recoveries, id: \.scope.id) { scope, status in
                StatusRow(text: recoveryText(scope, status: status), symbol: "info.circle", role: .caution,
                    identifier: "overviewLocationRecovery", action: StatusAction(title: "Choose again…", identifier: "overviewChooseAgain") {
                    renewAndScan(scope)
                }).disabled(folderInspection.isScanning || selection.workspaceRunning)
            }
            if let notice = locationsModel.notice { StatusRow(text: notice, symbol: "info.circle", role: .caution) }
            if let message = folderInspection.message, !recoveryRowCovers(folderInspection.unavailableScope) {
                StatusRow(text: message, symbol: "info.circle")
            }
        }
    }
    /// Overview's recovery rows, for the explorer to mark those locations' last observations as gone (#249).
    private var explorerUnavailable: [ExplorerUnavailableLocation] {
        locationsModel.recoveries.map { scope, status in
            ExplorerUnavailableLocation(scope: URL(fileURLWithPath: scope.path).standardizedFileURL, reason: locationsModel.recoveryReasons[scope.id] ?? status.reason) { renewAndScan(scope) }
        }
    }
    /// "Folder not found · last observed <time>" for a deleted or moved folder, "Access unavailable" for an unreadable one (#254).
    private func recoveryText(_ scope: RememberedScope, status: RememberedLocations.AccessStatus) -> String {
        let observed = Array(selection.scans.values) + folderInspection.scopeReports.map(\.current)
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
    /// Folders the user picked plus the catalog's known locations; unknown coverage is left to the recovery row (#223).
    private var scannedSummary: String {
        let result = overviewObservation
        return ScannedLocationsSummary.text(folders: result.map { _ in selection.scans.count },
            observedSize: (result.map { $0.isComplete ? $0.totalLogicalBytes : $0.logicalBytes } ?? nil).map { overviewBytes($0) }, complete: result?.isComplete ?? false,
            knownCacheFolders: selection.catalog.overview?.rows.reduce(0) { $0 + $1.rules.count }, checking: selection.catalog.isScanning)
    }

    /// Renews a remembered location's access: the user picks the same folder again. Shared by Locations & access and Overview (#223).
    @discardableResult private func chooseAgain(_ scope: RememberedScope) -> Bool {
        guard let url = FolderInspection.chooseFolder(remembering: true) else { return false }
        if url.standardizedFileURL.path == scope.path { return locationsModel.remember(url, downloads: isDownloadsLocation(url)) }
        locationsModel.message = "Choose the same location to renew access. Use Add folder for a different location."
        return false
    }
    private func isDownloadsLocation(_ url: URL) -> Bool {
        guard let root = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return false }
        return url.standardizedFileURL.pathComponents.starts(with: root.standardizedFileURL.pathComponents)
    }
    private func scanLocations(_ scopes: [RememberedScope]) {
        guard !folderInspection.isScanning, !selection.workspaceRunning else { return }
        let leases = scopes.compactMap { locationsModel.resolve($0) }
        let resolved = Set(leases.map { $0.url.standardizedFileURL.path })
        for scope in scopes where !resolved.contains(scope.path) {
            let url = URL(fileURLWithPath: scope.path)
            selection.suspendScope(url); folderInspection.markUnavailable(url)
        }
        guard !scopes.isEmpty else { return }
        scanOrigin = destination
        let unavailable = scopes.filter { !resolved.contains($0.path) }.map { URL(fileURLWithPath: $0.path) }
        folderInspection.scanAgain(scopes: leases.map(\.url), leases: leases, unavailable: unavailable)
    }
    private func openExplorer(downloads: Bool, caller: Destination) {
        navigationState.downloadsExplorerActive = downloads
        if explorerContext.downloadsOnly != downloads { if downloads { explorerContext.openDownloads() } else { explorerContext.openLocations() } }
        explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        explorerContext.downloadsScopes = Set(locationsModel.includedDownloads.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        explorerCaller = caller; nativeInspectionVisible = true; planReturnsToExplorer = false
    }
    private func startNewPlan() {
        planPresentation.reset(); selection.startNewPlan(); planReturnsToExplorer = false; nativeInspectionVisible = false; destination = .plan
        Task { await folderInspection.resetSession() }
    }

    private func openRecovery(caller: Destination, refresh: Bool = true) {
        navigationState.recoveryCaller = caller
        destination = caller
        recoveryVisible = true
        if refresh { Task { await recovery.refresh() } }
    }

    private func openLocalRecords(caller: Destination) {
        navigationState.localRecordsCaller = caller
        navigationState.localRecordsOffset = nil
        navigationState.localRecordsVisible = true
        recoveryVisible = false
        destination = caller
    }

    private func didResetLocalRecords() {
        nativeInspectionVisible = false
        diagnosticsVisible = false; diagnostics = DiagnosticsModel(); exclusionsVisible = false
    }

    private var history: some View {
        CleanupHistoryView(model: navigationState.historyModel, expandedRuns: $navigationState.historyExpandedRuns,
            showRecovery: { openRecovery(caller: .history) }, goOverview: { navigate(.overview) }, viewPlan: { navigate(.plan) })
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Locations & access", subtitle: "Folders CacheDrop scans at launch and when you scan again.")
            ScanHistoryRecordingNotice()
            HStack {
                Button("Add folder…", action: chooseFolderForScan).disabled(folderInspection.isScanning || selection.workspaceRunning)
                Button("Scan selected locations") { scanLocations(locationsModel.included) }
                    .disabled(locationsModel.included.isEmpty || folderInspection.isScanning || selection.workspaceRunning)
            }
            if locationsModel.scopes.isEmpty { EmptyState(title: "No locations yet", detail: "Add a folder to scan it now and each time CacheDrop opens.", symbol: "folder.badge.plus") }
            ForEach(locationsModel.scopes) { scope in
                LocationScopeRow(name: URL(fileURLWithPath: scope.path).lastPathComponent, path: scope.path,
                    status: locationStatus(scope), overlap: locationOverlap(scope), included: Binding(get: { scope.isIncluded }, set: { included in
                        if locationsModel.setIncluded(included, scope: scope) { selection.suspendScope(URL(fileURLWithPath: scope.path)) }
                    }), enabled: !folderInspection.isScanning && !selection.workspaceRunning) {
                    HStack {
                        if locationsModel.statuses[scope.id]?.needsRecovery == true {
                            Button("Choose again…") { chooseAgain(scope) }
                            Button("Reconnect and recheck") { scanLocations([scope]) }.disabled(!scope.isIncluded)
                        }
                        Menu("More") {
                            Button("Forget location") { locationToForget = scope }
                        }.accessibilityIdentifier("locationActions:" + scope.path)
                    }
                }
                if locationsModel.statuses[scope.id]?.needsRecovery == true,
                   let previous = folderInspection.scopeReports.first(where: { $0.current.scope.path == scope.path })?.lastComplete {
                    Text("Last complete observation: " + previous.observedAt.formatted() + " · Historical, not current coverage").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
            if let message = locationsModel.message { StatusRow(text: message, symbol: "info.circle") }
            FullDiskAccessSetting()
            LocalRecordsEntry { openLocalRecords(caller: .locations) }
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
        return overlaps ? "Overlaps another remembered location · Shared contents are counted once." : nil
    }
    private func locationStatus(_ scope: RememberedScope) -> String {
        if !scope.isIncluded { return "Omitted from the next scan" }
        if let status = locationsModel.statuses[scope.id], status.needsRecovery { return status.text }
        if let scan = selection.scans[URL(fileURLWithPath: scope.path)] {
            if selection.unavailableScopes.contains(scan.scope.standardizedFileURL) { return "Refresh required" }
            return scan.isComplete ? "Observed · " + scan.observedAt.formatted(date: .omitted, time: .shortened) : "Partial coverage · Uninspected bytes unknown"
        }
        return "Not scanned"
    }
}

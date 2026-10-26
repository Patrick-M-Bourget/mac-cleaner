import SwiftUI
import Observation
import StillCore

@main
struct StillApp: App {
    @NSApplicationDelegateAdaptor(StillApplicationDelegate.self) private var delegate
    @StateObject private var lifecycle = AppLifecycleController.shared
    @StateObject private var alerts = AppLifecycleController.shared.alerts
    /// Runs before AppKit finishes launching, so saved window state is ignored before it can be restored.
    init() { AppLaunchPolicy.registerDefaults() }
    var body: some Scene {
        Window("Still", id: "workspace") {
            WorkspaceView(alerts: lifecycle.alerts)
                .frame(minWidth: 900).background { NativeWindowContract() }
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show Still") { lifecycle.openWorkspace?() }
            }
        }
    }
}

enum Destination: String, CaseIterable, Identifiable {
    case alerts = "Storage alerts"
    case overview = "Overview", growth = "What grew", plan = "Cleanup plan", history = "History", locations = "Locations & access"
    var id: String { rawValue }
    var shortcut: KeyEquivalent {
        switch self {
        case .growth: "6"
        case .alerts: "5"
        case .overview: "1"
        case .plan: "2"
        case .history: "3"
        case .locations: "4"
        }
    }
    var symbol: String {
        switch self {
        case .growth: "chart.line.uptrend.xyaxis"
        case .alerts: "bell"
        case .overview: "internaldrive"
        case .plan: "checklist"
        case .history: "clock"
        case .locations: "folder.badge.gearshape"
        }
    }
}

/// Window restoration within this process never restores cleanup authority after Quit.
@MainActor @Observable final class WorkspaceNavigation {
    var destination = Destination.overview
    var configureAlertsOnEntry = true
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
    var accessGuideExpanded = false
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
    @State private var homebrewVisible = false
    @State private var pipVisible = false
    @State private var exclusionsVisible = false
    private var diagnosticsVisible: Bool { get { navigationState.diagnosticsVisible } nonmutating set { navigationState.diagnosticsVisible = newValue } }
    @State private var overviewCloudExpanded = false
    @State private var overviewShowsAllCategories = false
    private var diagnostics: DiagnosticsModel { get { navigationState.diagnosticsModel } nonmutating set { navigationState.diagnosticsModel = newValue } }
    @State private var locationsModel = AppLifecycleController.shared.locations
    private var explorerContext: StorageExplorerContext { navigationState.downloadsExplorerActive ? AppLifecycleController.shared.downloadsExplorer : AppLifecycleController.shared.locationsExplorer }
    @State private var planPresentation = AppLifecycleController.shared.planPresentation
    private var explorerCaller: Destination { get { navigationState.explorerCaller } nonmutating set { navigationState.explorerCaller = newValue } }
    private var planReturnsToExplorer: Bool { get { navigationState.planReturnsToExplorer } nonmutating set { navigationState.planReturnsToExplorer = newValue } }
    private var scanOrigin: Destination { get { navigationState.scanOrigin } nonmutating set { navigationState.scanOrigin = newValue } }
    @State private var locationToForget: RememberedScope?
    @State private var capacity = AppLifecycleController.shared.capacity
    private var startupCapacity: StartupCapacityReading? { capacity.reading }
    private var showsPlan: Bool { destination == .plan && !navigationState.localRecordsVisible && !recoveryVisible && !nativeInspectionVisible && !homebrewVisible && !pipVisible && !diagnosticsVisible && !exclusionsVisible }
    /// The toolbar's note, which only reports state (Decision 25: no toolbar subtitles). A screen returns nil to show none.
    private var contextLabel: String? {
        if selection.workspaceRunning { return "Running approved cleanup" }
        if navigationState.localRecordsVisible && !recoveryVisible { return "Local records · Explicit maintenance only" }
        if diagnosticsVisible { return "Redacted diagnostics · Explicit local Save" }
        if recoveryVisible { return "Recovery review · Recorded facts only" }
        if selection.hasWorkspaceResult && showsPlan { return "Cleanup results · individual outcomes" }
        if nativeInspectionVisible { return nil }
        if homebrewVisible { return "Read-only Homebrew inventory" }
        if pipVisible { return "Read-only pip inventory" }
        if exclusionsVisible { return "Custom scan exclusions" }
        if navigationState.appManagedVisible { return nil }
        switch destination {
        case .overview: return nil
        case .plan: return "Choose files, then review"
        case .history: return "Recorded scan and cleanup activity"
        case .locations: return "Scan locations and access"
        case .alerts: return "Capacity checks only"
        case .growth: return "Observed storage changes"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                AppBrand().padding(.horizontal, StillDesign.Space.sm).padding(.bottom, StillDesign.Space.xl)
                Text("Storage").font(.caption).foregroundStyle(.secondary).padding(.horizontal, StillDesign.Space.sm)
                // Storage alerts stay unwired until after M1 (Decision 12); What grew is back (#119).
                ForEach(Destination.allCases.filter { $0 != .locations && $0 != .alerts }) { navigation($0) }
                Text("Settings").font(.caption).foregroundStyle(.secondary).padding(.horizontal, StillDesign.Space.sm).padding(.top, StillDesign.Space.xl)
                navigation(.locations)
                Spacer()
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    Label("This Mac", systemImage: "laptopcomputer").font(.callout)
                    CapacityMeter(available: startupCapacity?.available, total: startupCapacity?.total, compact: true)
                    Text(capacity.sidebarObservationText).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).frame(height: 14, alignment: .leading)
                        .help(capacity.observationText).accessibilityLabel(capacity.observationText)
                        .accessibilityIdentifier("sidebarCapacityObservation")
                    Text(capacity.statusText.isEmpty ? " " : capacity.statusText).font(.caption2).foregroundStyle(.secondary)
                        .frame(height: 14, alignment: .leading)
                }.padding(.horizontal, StillDesign.Space.sm)

            }
            .padding(.horizontal, StillDesign.Space.md).padding(.vertical, StillDesign.Space.lg)
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background { ChromeSurface(role: .sidebar) }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                AppearancePreferenceNotice(notice: appearance.notice, retry: { appearance.retrySaving() })
                    .padding(.horizontal, StillDesign.Space.page)
                if nativeInspectionVisible {
                    StorageExplorerView(model: folderInspection, selection: selection, context: explorerContext,
                        backTitle: "Back to " + explorerCaller.rawValue, back: { nativeInspectionVisible = false; destination = explorerCaller })
                    ActionStrip {
                        Button("View cleanup plan") {
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
                        backToExplorerTitle: navigationState.planReturnsToGrowth ? "Back to What grew" : "Back to Explorer",
                        presentation: planPresentation)
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                        if recoveryVisible {
                            CleanupRecoveryView(model: recovery)
                        } else if navigationState.localRecordsVisible {
                            LocalRecordsView(model: navigationState.historyModel, showRecovery: { openRecovery(caller: navigationState.localRecordsCaller) }, didReset: didResetLocalRecords, reviewDiagnostics: nil)
                        } else if exclusionsVisible {
                            ExclusionsView(model: ExclusionsModel.shared)
                        } else if diagnosticsVisible {
                            DiagnosticsView(model: diagnostics)
                        } else if navigationState.appManagedVisible {
                            AppManagedStorageView(model: selection.catalog) { navigationState.appManagedVisible = false }
                        } else if pipVisible {
                            PipInspectionView { pipVisible = false; destination = .overview }
                        } else if homebrewVisible {
                            HomebrewInspectionView { homebrewVisible = false; destination = .overview }
                        } else if nativeInspectionVisible {
                            FolderInspectionView(model: folderInspection, selection: selection, viewPlan: { nativeInspectionVisible = false; destination = .plan }) { nativeInspectionVisible = false; destination = .overview }
                        }
                        else {
                            switch destination {
                            case .alerts: StorageAlertsView(controller: alerts, capacity: capacity, configureOnEntry: navigationState.configureAlertsOnEntry)
                            case .growth: GrowthHistoryView(model: GrowthHistoryModel.shared, catalog: selection.catalog)
                            case .overview: overview
                            case .plan: EmptyView()
                            case .history: history
                            case .locations: locations
                            }
                        }
                    }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
                        .background(alignment: .topLeading) {
                            if diagnosticsVisible && !recoveryVisible {
                                DestinationViewport(offset: $navigationState.diagnosticsOffset).frame(width: 0, height: 0)
                            } else if navigationState.localRecordsVisible && !recoveryVisible {
                                DestinationViewport(offset: $navigationState.localRecordsOffset).frame(width: 0, height: 0)
                            } else if !recoveryVisible && !diagnosticsVisible && !exclusionsVisible && !pipVisible && !homebrewVisible && !navigationState.appManagedVisible {
                                if destination == .history {
                                    DestinationViewport(offset: $navigationState.historyOffset).frame(width: 0, height: 0)
                                } else if destination == .growth {
                                    DestinationViewport(offset: $navigationState.growthOffset).frame(width: 0, height: 0)
                                } else if destination == .overview {
                                    DestinationViewport(offset: $navigationState.overviewOffset).frame(width: 0, height: 0)
                                } else if destination == .locations {
                                    DestinationViewport(offset: $navigationState.locationsOffset).frame(width: 0, height: 0)
                                }
                            }
                        }
                }.id(recoveryVisible ? "recovery" : diagnosticsVisible ? "diagnostics" : navigationState.localRecordsVisible ? "local-records" : navigationState.appManagedVisible ? "app-managed" : destination.rawValue)

                Group {
                    if exclusionsVisible {
                        ActionStrip(message: "Custom rules change scan coverage; original files stay unchanged.") {
                            Button("Back to Locations & access") { exclusionsVisible = false; destination = .locations }.disabled(ExclusionsModel.shared.editingBlocked)
                            if ExclusionsModel.shared.preview != nil {
                                Button("Cancel") { ExclusionsModel.shared.preview = nil }.disabled(ExclusionsModel.shared.editingBlocked)
                                Button("Save exclusion") { Task { await ExclusionsModel.shared.save() } }.buttonStyle(.borderedProminent).disabled(ExclusionsModel.shared.editingBlocked)
                            } else {
                                Button("Choose file or folder…") { Task { await ExclusionsModel.shared.choose() } }.buttonStyle(.borderedProminent).disabled(ExclusionsModel.shared.editingBlocked).accessibilityIdentifier("chooseExclusion")
                            }
                        }
                    } else if diagnosticsVisible {
                        ActionStrip(message: "The reviewed payload stays on this Mac unless you explicitly save it.") {
                            Button("Back to " + navigationState.diagnosticsCaller.rawValue) {
                                diagnosticsVisible = false; navigationState.localRecordsVisible = false
                                destination = navigationState.diagnosticsCaller
                            }.disabled(diagnostics.isSaving)
                            Button("Save diagnostics…") { Task { await diagnostics.save() } }.buttonStyle(.borderedProminent).disabled(diagnostics.export == nil || diagnostics.isSaving)
                        }
                    } else if recoveryVisible {
                        ActionStrip(message: "Recovery records are retained. Nothing resumes automatically.") {
                            Button(navigationState.localRecordsVisible ? "Back to Local records" : navigationState.recoveryCaller == .overview ? "Return to Overview" : "Back to " + navigationState.recoveryCaller.rawValue) {
                                recoveryVisible = false; destination = navigationState.recoveryCaller; navigationState.recoveryCaller = .overview
                            }.buttonStyle(.borderedProminent)
                        }
                    } else if navigationState.localRecordsVisible {
                        ActionStrip(message: "These controls manage Still’s records, not your original files.") {
                            Button("Back to " + navigationState.localRecordsCaller.rawValue) {
                                navigationState.localRecordsVisible = false
                                destination = navigationState.localRecordsCaller
                            }.buttonStyle(.borderedProminent)
                        }
                    } else if nativeInspectionVisible && folderInspection.isScanning {
                        ActionStrip(message: "Preliminary observations · No cleanup is running") {
                            Button("Stop scan") { folderInspection.cancel() }.buttonStyle(.borderedProminent)
                        }
                    } else if nativeInspectionVisible {
                        ActionStrip(message: "Inspection only · \(StillDesign.items(selection.workspaceSelectedCount)) in the cleanup plan") {
                            Button("View cleanup plan") { nativeInspectionVisible = false; destination = .plan }.buttonStyle(.borderedProminent)
                        }
                    } else if destination == .growth {
                        ActionStrip(message: GrowthHistoryModel.shared.comparison?.state == .compared ? "Two completed scans · Coverage changes aren’t counted as growth. No continuous monitoring required." : "Each completed scan of the known locations is recorded. No continuous monitoring required.") {
                            Button("Scan again", action: scanAgain).disabled(selection.catalog.isScanning || folderInspection.isScanning || selection.workspaceRunning || !selection.catalog.canEdit)
                                .accessibilityIdentifier("growthScanAgain")
                            Button("Review options") { navigate(.plan); navigationState.planReturnsToGrowth = true }.buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("growthReviewOptions")
                        }
                    } else if showsPlan {
                        ActionStrip(message: "Nothing changes until you confirm the next step.") { Button("Review cleanup") {}.disabled(true) }
                    }
                }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StillDesign.reading)
        }
        .onChange(of: selection.catalog.selectionRevision) { _, _ in AppLifecycleController.shared.hasPendingPlan = selection.hasPendingChoices }
        .task { if await recovery.loadOnce() { openRecovery(caller: .overview, refresh: false) } }
        .task { locationsModel.load() }
        .onChange(of: locationsModel.scopes) { _, _ in
            explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
            explorerContext.downloadsScopes = Set(locationsModel.includedDownloads.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        }
        .onAppear { AppLifecycleController.shared.openWorkspace = { openWindow(id: "workspace") } }
        .onReceive(NotificationCenter.default.publisher(for: .stillAlertOpened)) { _ in destination = .overview; navigationState.localRecordsVisible = false; navigationState.appManagedVisible = false; exclusionsVisible = false; diagnosticsVisible = false; recoveryVisible = false; nativeInspectionVisible = false; homebrewVisible = false; pipVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await alerts.activated() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in Task { await alerts.activated() } }
        .toolbar {
            contextToolbar
            ToolbarItem(placement: .automatic) {
            AppearancePicker(choice: Binding(get: { appearance.choice }, set: { AppLifecycleController.shared.chooseAppearance($0) }))
            }
        }
    }

    @ToolbarContentBuilder private var contextToolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) { contextToolbarLabel }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { contextToolbarLabel }
        }
    }
    @ViewBuilder private var contextToolbarLabel: some View {
        if selection.workspaceRunning, let contextLabel {
            Text(contextLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else if folderInspection.isScanning {
            ToolbarScanStatus(location: folderInspection.scope?.lastPathComponent ?? "selected locations",
                phase: folderInspection.progress.map { $0.phase == .rechecking ? "Rechecking changed coverage (one attempt)…" : $0.phase == .checkingDirectories ? "Checking directory stability…" : "Reading file metadata…" } ?? "Preparing metadata scan…",
                inspectedEntries: folderInspection.progress?.visitedEntries,
                returnToScan: scanReturnAction,
                stop: { folderInspection.cancel() })
        } else if let contextLabel { Text(contextLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
    }

    private var scanReturnAction: (() -> Void)? {
        let atOrigin = destination == scanOrigin && !navigationState.localRecordsVisible && !navigationState.appManagedVisible && !nativeInspectionVisible && !diagnosticsVisible && !exclusionsVisible && !recoveryVisible && !homebrewVisible && !pipVisible
        if atOrigin { return nil }
        return { returnToScanOrigin() }
    }

    private func returnToScanOrigin() {
        destination = scanOrigin
        navigationState.localRecordsVisible = false; navigationState.appManagedVisible = false
        nativeInspectionVisible = false; diagnosticsVisible = false
        exclusionsVisible = false; recoveryVisible = false; homebrewVisible = false
        pipVisible = false
        planReturnsToExplorer = false
    }

    private func navigate(_ value: Destination, configureAlerts: Bool = true) {
        navigationState.routeGeneration = UUID()
        navigationState.planReturnsToGrowth = false
        navigationState.configureAlertsOnEntry = configureAlerts
        destination = value
        planReturnsToExplorer = false
        if value == .plan && selection.hasWorkspaceResult { startNewPlan() }
        navigationState.localRecordsVisible = false; navigationState.appManagedVisible = false
        diagnosticsVisible = false; exclusionsVisible = false
        recoveryVisible = false; navigationState.recoveryCaller = .overview; nativeInspectionVisible = false; homebrewVisible = false
        pipVisible = false
    }

    private func navigation(_ value: Destination) -> some View {
        StillSidebarRow(title: value.rawValue, symbol: value.symbol, selected: destination == value,
                        accent: value == .growth ? StillDesign.purple : value == .plan ? StillDesign.teal : value == .history ? .secondary : StillDesign.blue,
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
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            HStack(alignment: .top) {
                PageHeader(title: "Storage overview", subtitle: "A clearer picture of what’s on your Mac.")
                Spacer(minLength: StillDesign.Space.md)
                Button("Scan again", action: scanAgain).disabled(folderInspection.isScanning || selection.workspaceRunning || !selection.catalog.canEdit)
            }
            ScanHistoryRecordingNotice()
            if let context = alerts.openedAlertContext {
                SummarySurface {
                    VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                        StatusRow(text: context.observedAt.map { "Alert checked \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Alert check time unavailable", symbol: "bell", identifier: "openedStorageAlert")
                        Text("This alert is an earlier observation. Choose a folder for a fresh scan; nothing runs automatically.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Choose a folder to scan…", action: chooseFolderForScan)
                                .disabled(folderInspection.isScanning || selection.workspaceRunning)
                            Button("Dismiss alert", action: alerts.dismissOpenedAlert)
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
                          refresh: { capacity.request(.manual) })
            scannedLocations
            overviewRecommendations
        }.task { await selection.catalog.scanIfNeeded() }
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
        let checking = summary == nil && catalog.isScanning
        return VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recommended for review").font(StillDesign.TypeStyle.section)
                    Spacer(minLength: StillDesign.Space.md)
                    Text(summary.map { recommendedText($0.recommended) } ?? (catalog.isScanning ? "Checking known locations…" : "Not measured yet"))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("overviewRecommendedTotal")
                }
                if showsCloudInventory || checking || !shown.isEmpty {
                    RecommendationGroup {
                        if showsCloudInventory {
                            overviewCloudRow
                            if overviewCloudExpanded, let report = overviewObservation?.cloudInventory { CloudInventoryView(report: report).padding(StillDesign.Space.md) }
                        }
                        if checking {
                            if showsCloudInventory { Divider().padding(.horizontal, StillDesign.Space.lg) }
                            ProgressView("Checking known locations…").font(.caption).padding(StillDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // The largest catalog categories that found something; categories are data in StillCore.
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                            if index > 0 || showsCloudInventory { Divider().padding(.horizontal, StillDesign.Space.lg) }
                            catalogRow(row)
                        }
                        if more > 0 {
                            Divider().padding(.horizontal, StillDesign.Space.lg)
                            Button(overviewShowsAllCategories ? "Show fewer" : "Show \(more) more") { overviewShowsAllCategories.toggle() }
                                .buttonStyle(.link).font(.callout).padding(StillDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("overviewShowMore")
                        }
                    }
                } else if summary != nil {
                    Text("Nothing to review in the known locations.").font(.callout).foregroundStyle(.secondary)
                }
                // Places macOS protects (Safari's cache) without Full Disk Access: one line, never a 0-byte row.
                if !catalog.notAccessibleRules.isEmpty {
                    FullDiskAccessNote(places: catalog.notAccessibleRules.map(\.title)).accessibilityIdentifier("overviewNotAccessible")
                }
                if let trash = summary?.proposedForTrash, trash != .measured(0) {
                    Text("Estimated release excludes " + trash.text + " proposed for Trash.").font(.caption).foregroundStyle(.secondary)
                }
                if !catalog.guidance.isEmpty {
                    RecommendationGroup {
                        StorageReviewRow(category: .managed, title: "App-managed storage", detail: "", value: StillDesign.items(catalog.guidance.count),
                                         actionTitle: "Review app-managed storage", action: { navigationState.appManagedVisible = true },
                                         identifier: "overviewAppManaged", mutedValue: true)
                    }
                }
            }
    }
    private func catalogRow(_ row: CatalogOverview.Row) -> some View {
        let inPlan = row.rules.contains { selection.catalog.isSelected($0) }
        return StorageReviewRow(category: row.category.storageCategory, title: row.category.overviewTitle, detail: row.detail,
            value: row.valueText,
            meaning: row.estimate == .unknown ? "Couldn’t be measured" : inPlan ? "In cleanup plan"
                : row.rules.allSatisfy { $0.action == .delete } ? "Rebuildable" : row.rules.allSatisfy { $0.action == .evict } ? "Local copies" : "Review files",
            actionTitle: "Review \(row.category.overviewTitle) in the cleanup plan",
            action: { destination = .plan },
            identifier: "overviewCategory-" + row.id)
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
    private func scanAgain() {
        capacity.request(.manual)
        Task { await selection.catalog.scan() }
        if !locationsModel.included.isEmpty { scanKnownLocations() }
    }
    private var scannedLocations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.sm) {
                Text("Scanned locations").font(.caption.weight(.medium))
                Text(scannedSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(overviewObservation?.scope.path ?? "").accessibilityIdentifier("overviewScopeCoverage")
                if overviewObservation != nil {
                    Button("Explore storage") { openExplorer(downloads: false, caller: .overview) }.buttonStyle(.link).font(.caption).disabled(selection.workspaceRunning)
                } else {
                    Button("Choose a folder…", action: chooseFolderForScan).buttonStyle(.link).font(.caption).disabled(folderInspection.isScanning || selection.workspaceRunning)
                }
                Spacer(minLength: 0)
            }
            if selection.scans.values.contains(where: { !$0.isComplete }) || overviewObservation.map({ $0.excludedEntryCount > 0 || $0.hasUnmeasuredContents }) == true {
                StatusRow(text: "Some locations have partial coverage. Uninspected bytes remain unknown.", symbol: "exclamationmark.circle", role: .caution)
            }
            if folderInspection.isScanning { ProgressView("Rechecking selected locations…").font(.caption) }
            if let message = locationsModel.message { StatusRow(text: message, symbol: "info.circle", role: .caution) }
            if let message = folderInspection.message { StatusRow(text: message, symbol: "info.circle") }
        }
    }
    /// Folders the user picked plus the catalog's known locations; unknown stays unknown.
    private var scannedSummary: String {
        var parts: [String] = []
        if let result = overviewObservation {
            parts.append(selection.scans.count == 1 ? "1 folder" : "\(selection.scans.count) folders")
            parts.append(result.isComplete ? overviewBytes(result.totalLogicalBytes) + " observed" : "at least " + overviewBytes(result.logicalBytes) + " observed")
        } else if folderInspection.scope != nil {
            parts.append("Folder coverage unknown · Recheck required")
        }
        if let rows = selection.catalog.overview?.rows {
            let found = rows.reduce(0) { $0 + $1.rules.count }
            parts.append(found == 1 ? "1 recognized cache location" : "\(found) recognized cache locations")
        } else if selection.catalog.isScanning {
            parts.append("Checking recognized locations…")
        }
        return parts.isEmpty ? "No folders chosen yet" : parts.joined(separator: " · ")
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
            showRecovery: { openRecovery(caller: .history) }, manageLocalRecords: { openLocalRecords(caller: .history) }, goOverview: { navigate(.overview) }, viewPlan: { navigate(.plan) })
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "Locations & access", subtitle: "Remember locations to include in your next manual scan.")
            ScanHistoryRecordingNotice()
            HStack {
                Button("Add folder…") {
                    if let url = FolderInspection.chooseFolder(remembering: true) { _ = locationsModel.remember(url, downloads: isDownloadsLocation(url)) }
                }.disabled(folderInspection.isScanning || selection.workspaceRunning)
                Button("Scan selected locations") { scanLocations(locationsModel.included) }
                    .disabled(locationsModel.included.isEmpty || folderInspection.isScanning || selection.workspaceRunning)
            }
            if locationsModel.scopes.isEmpty { EmptyState(title: "No locations yet", detail: "Add a folder, then run a manual scan. Adding a location never starts scanning.", symbol: "folder.badge.plus") }
            ForEach(locationsModel.scopes) { scope in
                LocationScopeRow(name: URL(fileURLWithPath: scope.path).lastPathComponent, path: scope.path,
                    status: locationStatus(scope), overlap: locationOverlap(scope), included: Binding(get: { scope.isIncluded }, set: { included in
                        if locationsModel.setIncluded(included, scope: scope) { selection.suspendScope(URL(fileURLWithPath: scope.path)) }
                    }), enabled: !folderInspection.isScanning && !selection.workspaceRunning) {
                    HStack {
                        if locationsModel.statuses[scope.id]?.needsRecovery == true {
                            Button("Choose again…") {
                                if let url = FolderInspection.chooseFolder(remembering: true) {
                                    if url.standardizedFileURL.path == scope.path { _ = locationsModel.remember(url, downloads: isDownloadsLocation(url)) }
                                    else { locationsModel.message = "Choose the same location to renew access. Use Add folder for a different location." }
                                }
                            }
                            Button("Reconnect and recheck") { scanLocations([scope]) }.disabled(!scope.isIncluded)
                        }
                        Menu("More") {
                            Button("Forget location") { locationToForget = scope }
                        }.accessibilityIdentifier("locationActions:" + scope.path)
                    }
                }
                if locationsModel.statuses[scope.id]?.needsRecovery == true,
                   let previous = folderInspection.scopeReports.first(where: { $0.current.scope.path == scope.path })?.lastComplete {
                    Text("Last complete observation: " + previous.observedAt.formatted() + " · Historical, not current coverage").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
            if let message = locationsModel.message { StatusRow(text: message, symbol: "info.circle") }
            Text("Scanned folders are for inspection. Cleanup choices, Downloads included, come from the cleanup plan. Access is rechecked for each manual scan; no files are scanned at launch.").font(.caption).foregroundStyle(.secondary)
            LocationAccessGuide(expanded: $navigationState.accessGuideExpanded)
            LocalRecordsEntry { openLocalRecords(caller: .locations) }
        }.confirmationDialog("Forget location?", isPresented: Binding(get: { locationToForget != nil }, set: { if !$0 { locationToForget = nil } }), titleVisibility: .visible) {
            if let scope = locationToForget {
                Button("Forget location", role: .destructive) { if locationsModel.forget(scope) { selection.suspendScope(URL(fileURLWithPath: scope.path)) }; locationToForget = nil }
                Button("Cancel", role: .cancel) { locationToForget = nil }
            }
        } message: {
            if let scope = locationToForget {
                Text("Forget " + URL(fileURLWithPath: scope.path).lastPathComponent + "? Still stops scanning it. No files will be deleted.")
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

private struct StillStatusMenu: View {
    @ObservedObject var alerts: StorageAlertsController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Storage alerts active")
        Text(alerts.status)
        Button("Open Still") {
            openWindow(id: "workspace")
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .stillAlertOpened, object: nil)
        }
        Divider()
        Button("Quit Still") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

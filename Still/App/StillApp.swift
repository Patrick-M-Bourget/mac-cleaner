import SwiftUI
import Observation
import StillCore

@main
struct StillApp: App {
    @NSApplicationDelegateAdaptor(StillApplicationDelegate.self) private var delegate
    @StateObject private var lifecycle = AppLifecycleController.shared
    @StateObject private var alerts = AppLifecycleController.shared.alerts
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
    var growthFromHistory = false
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
    @State private var managedStorageVisible = false
    @State private var managedStorage = ManagedStorageModel()
    @State private var pipVisible = false
    @State private var dockerVisible = false
    @State private var exclusionsVisible = false
    private var diagnosticsVisible: Bool { get { navigationState.diagnosticsVisible } nonmutating set { navigationState.diagnosticsVisible = newValue } }
    @State private var overviewCloudExpanded = false
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
    private var showsPlan: Bool { destination == .plan && !navigationState.localRecordsVisible && !recoveryVisible && !nativeInspectionVisible && !homebrewVisible && !pipVisible && !dockerVisible && !managedStorageVisible && !diagnosticsVisible && !exclusionsVisible }
    private var inspectionVisible: Bool { nativeInspectionVisible }
    private var contextLabel: String {
        if selection.chrome.isRunning { return "Clearing approved Chrome caches" }
        if selection.execution.isRunning { return "Moving approved files to Trash" }
        if selection.workspaceRunning { return "Running approved cleanup" }
        if navigationState.localRecordsVisible && !recoveryVisible { return "Local records · Explicit maintenance only" }
        if diagnosticsVisible { return "Redacted diagnostics · Explicit local Save" }
        if recoveryVisible { return "Recovery review · Recorded facts only" }
        if selection.hasWorkspaceResult && showsPlan { return "Cleanup results · individual outcomes" }
        if nativeInspectionVisible { return "Read-only storage inspection" }
        if managedStorageVisible { return "App-managed inventory · selected objects only" }
        if homebrewVisible { return "Read-only Homebrew inventory" }
        if pipVisible { return "Read-only pip inventory" }
        if dockerVisible { return "Read-only Docker inventory" }
        if exclusionsVisible { return "Custom scan exclusions" }
        switch destination {
        case .overview: return "On-demand storage review"
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
                // What grew and Storage alerts stay unwired until after M1 (Decision 12).
                ForEach(Destination.allCases.filter { $0 != .locations && $0 != .alerts && $0 != .growth }) { navigation($0) }
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
                    ActionStrip(message: "\(StillDesign.files(selection.draft.selectedCount)) · \(selection.chrome.selectedCount) Chrome groups selected · Nothing changes before confirmation.") {
                        Button("View cleanup plan") {
                            nativeInspectionVisible = false
                            planReturnsToExplorer = explorerCaller != .plan
                            destination = .plan
                        }.buttonStyle(.borderedProminent)
                    }
                } else if showsPlan {
                    LiveCleanupPlanView(selection: selection, recheck: { scope in scanLocations(locationsModel.included.filter { $0.path == scope.path }) }, stopRefresh: { folderInspection.cancel() }, chooseDownloads: scanDownloads,
                        exploreDownloads: { openExplorer(downloads: true, caller: .plan) },
                        viewHistory: { destination = .history }, newPlan: startNewPlan,
                        reviewRecovery: { openRecovery(caller: .plan) },
                        backToExplorer: navigationState.planReturnsToGrowth ? { navigationState.planReturnsToGrowth = false; destination = .growth } : planReturnsToExplorer ? { nativeInspectionVisible = true; planReturnsToExplorer = false } : nil,
                        backToExplorerTitle: navigationState.planReturnsToGrowth ? "Back to What grew" : "Back to Explorer",
                        manageLocations: { destination = .locations }, scopeMessage: locationsModel.message ?? folderInspection.message, presentation: planPresentation)
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
                        } else if managedStorageVisible {
                            ManagedStorageView(model: managedStorage) { managedStorageVisible = false; destination = .overview }
                        } else if dockerVisible {
                            DockerInspectionView { dockerVisible = false; destination = .overview }
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
                            case .growth: GrowthHistoryView(model: GrowthHistoryModel.shared,
                                reviewTitle: growthReviewTitle, review: { Task { await reviewGrowthLocation() } },
                                scanHistorical: { Task { await scanHistoricalGrowthLocation() } }, actionsEnabled: canStartGrowthScan)
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
                            } else if !recoveryVisible && !diagnosticsVisible && !exclusionsVisible && !managedStorageVisible && !dockerVisible && !pipVisible && !homebrewVisible {
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
                }.id(recoveryVisible ? "recovery" : diagnosticsVisible ? "diagnostics" : navigationState.localRecordsVisible ? "local-records" : destination.rawValue)

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
                    } else if inspectionVisible {
                        ActionStrip(message: nativeInspectionVisible ? "\(StillDesign.files(selection.draft.selectedCount)) selected" : "Nothing selected") {
                            Button("View cleanup plan") { nativeInspectionVisible = false; destination = .plan }.buttonStyle(.borderedProminent)
                        }
                    } else if destination == .growth {
                        if navigationState.growthFromHistory {
                            ActionStrip(message: "Recorded observation · Current files and cleanup choices stay unchanged.") {
                                Button("Back to History") { navigate(.history) }
                                if folderInspection.isScanning {
                                    Button("Stop scan") { folderInspection.cancel() }.buttonStyle(.borderedProminent)
                                } else if !GrowthHistoryModel.shared.isHistorical {
                                    Button(GrowthHistoryModel.shared.scanTitle) { Task { await scanGrowthLocation() } }.buttonStyle(.borderedProminent).disabled(!canStartGrowthScan || GrowthHistoryModel.shared.isResolving || GrowthHistoryModel.shared.authorityChecking)
                                }
                            }
                        } else {
                            ActionStrip(message: "Two compatible completed observations reveal net changes.") {
                                if folderInspection.isScanning {
                                    Button("Stop scan") { folderInspection.cancel() }.buttonStyle(.borderedProminent)
                                } else {
                                    if GrowthHistoryModel.shared.comparison?.current != nil {
                                        Button("Choose another location…") { chooseNewGrowthLocation() }.disabled(!canStartGrowthScan)
                                    }
                                    Button(GrowthHistoryModel.shared.scanTitle) { Task { await scanGrowthLocation() } }
                                        .buttonStyle(.borderedProminent).disabled(!canStartGrowthScan || GrowthHistoryModel.shared.isResolving || GrowthHistoryModel.shared.authorityChecking)
                                }
                            }
                        }
                    } else if destination == .overview && !managedStorageVisible && !dockerVisible && !pipVisible && !homebrewVisible {
                        if folderInspection.isScanning {
                            ActionStrip(message: "Manual scan running · No cleanup is running") { EmptyView() }
                        } else {
                        ActionStrip(message: "\(StillDesign.files(selection.draft.selectedCount)) · \(selection.chrome.selectedCount) Chrome groups · \(selection.catalog.selectedCount == 1 ? "1 cache folder" : "\(selection.catalog.selectedCount) cache folders") selected · Nothing changes before confirmation.") {
                            Button("Review cleanup plan") { destination = .plan }.buttonStyle(.borderedProminent).disabled(selection.scans.isEmpty && !selection.hasPendingChoices)
                        }
                        }
                    } else if showsPlan {
                        ActionStrip(message: "Nothing changes until you confirm the next step.") { Button("Review cleanup") {}.disabled(true) }
                    }
                }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StillDesign.reading)
        }
        .onChange(of: selection.chrome.isBusy) { previous, current in if previous && !current { capacity.request(.scanEnded) } }
        .onChange(of: selection.chrome.selectionRevision) { _, _ in AppLifecycleController.shared.hasPendingPlan = selection.hasPendingChoices }
        .onChange(of: selection.catalog.selectionRevision) { _, _ in AppLifecycleController.shared.hasPendingPlan = selection.hasPendingChoices }
        .onChange(of: selection.mutationVersion) { _, _ in AppLifecycleController.shared.hasPendingPlan = selection.hasPendingChoices }
        .task { if await recovery.loadOnce() { openRecovery(caller: .overview, refresh: false) } }
        .task { locationsModel.load() }
        .onChange(of: locationsModel.scopes) { _, _ in
            explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
            explorerContext.downloadsScopes = Set(locationsModel.includedDownloads.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        }
        .onAppear { AppLifecycleController.shared.openWorkspace = { openWindow(id: "workspace") } }
        .onReceive(NotificationCenter.default.publisher(for: .stillAlertOpened)) { _ in destination = .overview; navigationState.localRecordsVisible = false; exclusionsVisible = false; diagnosticsVisible = false; recoveryVisible = false; nativeInspectionVisible = false; homebrewVisible = false; pipVisible = false; dockerVisible = false; managedStorageVisible = false }
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
        if selection.execution.isRunning {
            Text(contextLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else if folderInspection.isScanning {
            ToolbarScanStatus(location: folderInspection.scope?.lastPathComponent ?? "selected locations",
                phase: folderInspection.progress.map { $0.phase == .rechecking ? "Rechecking changed coverage (one attempt)…" : $0.phase == .checkingDirectories ? "Checking directory stability…" : "Reading file metadata…" } ?? "Preparing metadata scan…",
                inspectedEntries: folderInspection.progress?.visitedEntries,
                returnToScan: scanReturnAction,
                stop: { folderInspection.cancel() })
        } else { Text(contextLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
    }

    private var scanReturnAction: (() -> Void)? {
        let atOrigin = destination == scanOrigin && !navigationState.localRecordsVisible && !nativeInspectionVisible && !diagnosticsVisible && !exclusionsVisible && !recoveryVisible && !homebrewVisible && !pipVisible && !dockerVisible && !managedStorageVisible
        if atOrigin { return nil }
        return { returnToScanOrigin() }
    }

    private func returnToScanOrigin() {
        destination = scanOrigin
        navigationState.localRecordsVisible = false
        nativeInspectionVisible = false; diagnosticsVisible = false
        exclusionsVisible = false; recoveryVisible = false; homebrewVisible = false
        pipVisible = false; dockerVisible = false; managedStorageVisible = false
        planReturnsToExplorer = false
    }

    private func navigate(_ value: Destination, configureAlerts: Bool = true) {
        navigationState.routeGeneration = UUID()
        if navigationState.growthFromHistory { GrowthHistoryModel.shared.endHistoricalRequest() }
        navigationState.growthFromHistory = false
        navigationState.planReturnsToGrowth = false
        navigationState.configureAlertsOnEntry = configureAlerts
        destination = value
        planReturnsToExplorer = false
        if value == .plan && selection.hasWorkspaceResult { startNewPlan() }
        navigationState.localRecordsVisible = false
        diagnosticsVisible = false; exclusionsVisible = false
        recoveryVisible = false; navigationState.recoveryCaller = .overview; nativeInspectionVisible = false; homebrewVisible = false
        pipVisible = false; dockerVisible = false; managedStorageVisible = false
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
            selection.leaveRetryMode()
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
                Button("Scan again", action: scanKnownLocations).disabled(locationsModel.included.isEmpty || folderInspection.isScanning || selection.execution.isRunning)
            }
            ScanHistoryRecordingNotice()
            if let context = alerts.openedAlertContext {
                SummarySurface {
                    VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                        StatusRow(text: context.observedAt.map { "Alert checked \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Alert check time unavailable", symbol: "bell", identifier: "openedStorageAlert")
                        Text("This alert is an earlier observation. Choose a folder for a fresh scan; nothing runs automatically.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Choose a folder to scan…", action: chooseFolderForScan)
                                .disabled(folderInspection.isScanning || selection.execution.isRunning)
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
                          refreshTitle: capacity.failed ? "Try again" : "Refresh capacity", refreshing: capacity.isRefreshing,
                          refresh: { capacity.request(.manual) })
            scannedLocations
            overviewRecommendations
        }.task { await selection.catalog.scanIfNeeded() }
    }

    private var overviewRecommendations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                Text("Recommended for review").font(StillDesign.TypeStyle.section)
                RecommendationGroup {
                    overviewCloudRow
                    if overviewCloudExpanded, let report = overviewObservation?.cloudInventory { CloudInventoryView(report: report).padding(StillDesign.Space.md) }
                    Divider().padding(.horizontal, StillDesign.Space.lg)
                    StorageReviewRow(category: .developer, title: "Xcode build files", detail: "Build-file cleanup isn’t available yet.", value: "Not inspected", meaning: "Unavailable")
                    Divider().padding(.horizontal, StillDesign.Space.lg)
                    ForEach(selection.catalog.rulesFound) { rule in
                        let catalog = selection.catalog
                        StorageReviewRow(category: rule.category.storageCategory, title: rule.title, detail: rule.detail,
                            value: catalogBytes(catalog.estimatedBytes(for: rule), complete: catalog.sizeComplete(for: rule)),
                            meaning: catalog.isSelected(rule) ? "Estimated · In cleanup plan" : "Estimated",
                            actionTitle: "Add \(rule.title) to the cleanup plan",
                            action: catalog.canEdit ? { catalog.setSelected(rule, true); destination = .plan } : nil,
                            identifier: "overviewRule-" + rule.id)
                        Divider().padding(.horizontal, StillDesign.Space.lg)
                    }
                    overviewDownloadsRow
                    Divider().padding(.horizontal, StillDesign.Space.lg)
                    StorageReviewRow(category: .browser, title: "Browser caches", detail: "Browser cache cleanup isn’t available yet.", value: "Not inspected", meaning: "Unavailable")
                }
                Text("Moving files to Trash won’t free space until you empty it.").font(.caption).foregroundStyle(.secondary)
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
    private var overviewDownloadsRow: some View {
        if selection.retryTargetIDs != nil {
            return StorageReviewRow(category: .downloads, title: "Downloads to review", detail: "A retry includes only unfinished files. Scan again to choose from all observed Downloads files.", value: overviewBytes(selection.overviewDownloadsLogicalBytes), meaning: "Observed logical size", actionTitle: "Scan again to review all files", action: folderInspection.isScanning || selection.execution.isRunning ? nil : { scanKnownLocations() }, identifier: "overviewDownloadsFinding")
        }
        let rows = selection.overviewDownloadRows
        let action: (() -> Void)? = rows.isEmpty || folderInspection.isScanning || selection.execution.isRunning ? nil : { reviewDownloads() }
        let detail: String
        let value: String
        if !rows.isEmpty {
            detail = selection.overviewDownloadsCoverage == .incomplete ? "\(StillDesign.files(rows.count)) eligible observed · Other contents remain uninspected." : "\(StillDesign.files(rows.count)) eligible across scanned Downloads locations · Move to Trash after review."
            value = overviewBytes(selection.overviewDownloadsLogicalBytes)
        } else {
            switch selection.overviewDownloadsCoverage {
            case .notInspected:
                detail = "Choose Downloads to inspect its files. Other folders are inspection only."
                value = "Not inspected"
            case .incomplete:
                detail = "Downloads coverage is incomplete. Recheck before choosing files."
                value = "Unknown"
            case .complete:
                detail = "No eligible files in the scanned Downloads locations."
                value = "No eligible files"
            }
        }
        return StorageReviewRow(category: .downloads, title: "Downloads to review", detail: detail, value: value, meaning: "Logical file size · Not freed space", actionTitle: "Review files", action: action, identifier: "overviewDownloadsFinding")
    }

    private func overviewBytes(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "Unknown"
    }
    private func scanKnownLocations() {
        scanLocations(locationsModel.included)
    }
    private func reviewDownloads() {
        openExplorer(downloads: true, caller: .overview)
    }
    private var scannedLocations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                    Text("Scanned locations").font(StillDesign.TypeStyle.section)
                    if let result = overviewObservation {
                        Text("\(selection.scans.count) locations · Current: \(result.scope.lastPathComponent)").font(.caption).foregroundStyle(.secondary).help(result.scope.path)
                        Text("Observed \(result.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    } else if locationsModel.included.isEmpty {
                        Text("No included locations with current observations.").font(.caption).foregroundStyle(.secondary)
                    } else if folderInspection.scope != nil {
                        Text("Current coverage: Unknown · Recheck required").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("overviewScopeCoverage")
                        if let previous = folderInspection.lastComplete { Text("Last complete observation: " + previous.observedAt.formatted() + " · Historical").font(.caption).foregroundStyle(.secondary) }
                    } else { Text("Choose a folder to understand its local storage.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: StillDesign.Space.sm) {
                    Button("Choose folder…", systemImage: "folder.badge.plus", action: chooseFolderForScan).disabled(folderInspection.isScanning || selection.execution.isRunning)
                    if overviewObservation != nil { Button("Explore storage") { openExplorer(downloads: false, caller: .overview) }.disabled(selection.execution.isRunning) }
                }
            }
            if let result = overviewObservation {
                Text(result.isComplete ? "Current location · \(overviewBytes(result.totalLogicalBytes)) logical · \(overviewBytes(result.totalAllocatedBytes)) allocated" : "Partial coverage · Observed logical subtotal \(overviewBytes(result.logicalBytes)) · Remaining bytes unknown")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("overviewScopeCoverage")
                if result.excludedEntryCount > 0 || result.hasUnmeasuredContents { Text("Unmeasured or excluded contents remain unknown.").font(.caption).foregroundStyle(.secondary) }
            }
            if selection.scans.values.contains(where: { !$0.isComplete }) {
                StatusRow(text: "Some locations have partial coverage. Uninspected bytes remain unknown.", symbol: "exclamationmark.circle", role: .caution)
            }
            if folderInspection.isScanning { ProgressView("Rechecking selected locations…").font(.caption) }
            if let message = locationsModel.message { StatusRow(text: message, symbol: "info.circle", role: .caution) }
            if let message = folderInspection.message { StatusRow(text: message, symbol: "info.circle") }
            CleanupScopeNotice(enabled: !folderInspection.isScanning && !selection.execution.isRunning, compact: true, chooseDownloads: chooseDownloads)
        }
    }

    private func isDownloadsLocation(_ url: URL) -> Bool {
        guard let root = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return false }
        return url.standardizedFileURL.pathComponents.starts(with: root.standardizedFileURL.pathComponents)
    }
    private func chooseDownloads() { scanDownloads() }
    private func scanDownloads() {
        guard !folderInspection.isScanning, !selection.execution.isRunning else { return }
        if !locationsModel.includedDownloads.isEmpty { scanLocations(locationsModel.includedDownloads); return }
        guard let url = FolderInspection.chooseFolder(downloads: true) else { return }
        guard isDownloadsLocation(url) else {
            locationsModel.message = "Choose Downloads or a folder inside it. Add other folders in Locations & access for inspection."
            return
        }
        guard locationsModel.remember(url, downloads: true) else { return }
        selection.leaveRetryMode(); scanOrigin = destination
        folderInspection.scan(url)
    }
    private func scanLocations(_ scopes: [RememberedScope]) {
        guard !folderInspection.isScanning, !selection.execution.isRunning else { return }
        let leases = scopes.compactMap { locationsModel.resolve($0) }
        let resolved = Set(leases.map { $0.url.standardizedFileURL.path })
        for scope in scopes where !resolved.contains(scope.path) {
            let url = URL(fileURLWithPath: scope.path)
            selection.suspendScope(url); folderInspection.markUnavailable(url)
        }
        guard !scopes.isEmpty else { return }
        selection.leaveRetryMode(); scanOrigin = destination
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

    private var canStartGrowthScan: Bool {
        !folderInspection.isScanning && !selection.execution.isRunning && !selection.isRefreshing && !selection.isPreparing && !AppLifecycleController.shared.maintenanceInProgress
    }
    private var growthReviewTitle: String? {
        let model = GrowthHistoryModel.shared
        guard model.reviewSnapshot != nil else { return nil }
        if model.authorityChecking { return "Checking location…" }
        guard let url = model.resolvedURL else { return "Locate folder…" }
        guard selection.scans[url.standardizedFileURL] != nil, !selection.unavailableScopes.contains(url.standardizedFileURL) else { return "Scan to review" }
        return isDownloadsLocation(url) ? "Review Downloads" : "Explore folder"
    }
    private func chooseNewGrowthLocation() {
        guard canStartGrowthScan else { return }
        guard let url = FolderInspection.chooseFolder(), locationsModel.remember(url, downloads: isDownloadsLocation(url)) else { return }
        GrowthHistoryModel.shared.selectNextLocation = true
        selection.leaveRetryMode(); scanOrigin = .growth; folderInspection.scan(url)
    }
    private func scanGrowthLocation(locate: Bool = false, fromHistorical: Bool = false) async {
        let model = GrowthHistoryModel.shared
        guard canStartGrowthScan, !model.isResolving else { return }
        guard let snapshot = model.reviewSnapshot else { chooseNewGrowthLocation(); return }
        let route = navigationState.routeGeneration
        model.isResolving = true
        defer { model.isResolving = false }
        if !locate && !model.needsLocationAccess, let lease = await model.leaseForSelection() {
            guard canStartGrowthScan, destination == .growth, navigationState.routeGeneration == route, model.reviewSnapshot?.id == snapshot.id else { lease.close(); return }
            model.accessNotice = nil; model.needsLocationAccess = false
            if fromHistorical { model.moveHistoricalToCurrent() }
            selection.leaveRetryMode(); scanOrigin = .growth
            folderInspection.scanAgain(scopes: [lease.url], leases: [lease]); return
        }
        guard locate || model.needsLocationAccess else {
            model.accessNotice = "This location is not currently authorized or available. Locate the original folder to reconnect before scanning or reviewing. Retained observations stay readable."
            model.needsLocationAccess = true; return
        }
        guard let url = FolderInspection.chooseFolder() else { return }
        guard await model.matches(url, snapshot: snapshot), model.reviewSnapshot?.id == snapshot.id else {
            model.accessNotice = "That folder does not match the recorded location’s root and volume identity. Nothing was scanned or rebound."; return
        }
        guard canStartGrowthScan, locationsModel.remember(url, downloads: isDownloadsLocation(url)) else { return }
        guard let lease = await model.leaseForSelection() else { model.accessNotice = "Access could not be renewed. Nothing was scanned."; return }
        guard canStartGrowthScan, destination == .growth, navigationState.routeGeneration == route, model.reviewSnapshot?.id == snapshot.id else { lease.close(); return }
        model.accessNotice = nil; model.needsLocationAccess = false
        if fromHistorical { model.moveHistoricalToCurrent() }
        selection.leaveRetryMode(); scanOrigin = .growth
        folderInspection.scanAgain(scopes: [lease.url], leases: [lease])
    }
    private func reviewGrowthLocation() async {
        let model = GrowthHistoryModel.shared
        guard canStartGrowthScan, !model.isResolving else { return }
        let route = navigationState.routeGeneration, snapshot = model.reviewSnapshot?.id
        let resolved = await model.leaseForSelection()
        guard canStartGrowthScan, destination == .growth, navigationState.routeGeneration == route, model.reviewSnapshot?.id == snapshot else { resolved?.close(); return }
        guard let lease = resolved else { await scanGrowthLocation(locate: true, fromHistorical: model.isHistorical); return }
        let url = lease.url.standardizedFileURL; lease.close()
        guard selection.scans[url] != nil, !selection.unavailableScopes.contains(url) else { await scanGrowthLocation(fromHistorical: model.isHistorical); return }
        if isDownloadsLocation(url) {
            navigationState.planReturnsToGrowth = true; planReturnsToExplorer = false; destination = .plan
        } else {
            openExplorer(downloads: false, caller: .growth)
            explorerContext.openLocation(url)
        }
    }
    private func scanHistoricalGrowthLocation() async {
        guard canStartGrowthScan else { return }
        await scanGrowthLocation(fromHistorical: true)
    }

    private var history: some View {
        CleanupHistoryView(model: navigationState.historyModel, expandedRuns: $navigationState.historyExpandedRuns,
            showRecovery: { openRecovery(caller: .history) }, manageLocalRecords: { openLocalRecords(caller: .history) }, goOverview: { navigate(.overview) }, viewPlan: { navigate(.plan) }, showGrowth: nil)
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "Locations & access", subtitle: "Remember locations to include in your next manual scan.")
            ScanHistoryRecordingNotice()
            HStack {
                Button("Add folder…") {
                    if let url = FolderInspection.chooseFolder(remembering: true) { _ = locationsModel.remember(url, downloads: isDownloadsLocation(url)) }
                }.disabled(folderInspection.isScanning || selection.execution.isRunning)
                Button("Scan selected locations") { scanLocations(locationsModel.included) }
                    .disabled(locationsModel.included.isEmpty || folderInspection.isScanning || selection.execution.isRunning)
            }
            if locationsModel.scopes.isEmpty { EmptyState(title: "No locations yet", detail: "Add a folder, then run a manual scan. Adding a location never starts scanning.", symbol: "folder.badge.plus") }
            ForEach(locationsModel.scopes) { scope in
                LocationScopeRow(name: URL(fileURLWithPath: scope.path).lastPathComponent, path: scope.path,
                    status: locationStatus(scope), overlap: locationOverlap(scope), included: Binding(get: { scope.isIncluded }, set: { included in
                        if locationsModel.setIncluded(included, scope: scope) { selection.suspendScope(URL(fileURLWithPath: scope.path)) }
                    }), enabled: !folderInspection.isScanning && !selection.execution.isRunning) {
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
                            Button("Forget location") {
                                let count = selection.dependentSelectionCount(for: URL(fileURLWithPath: scope.path))
                                if count > 0 { locationToForget = scope } else { if locationsModel.forget(scope) { selection.suspendScope(URL(fileURLWithPath: scope.path), forget: true) } }
                            }
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
            Text("Downloads files support cleanup. Other folders are inspection only. Access is rechecked for each manual scan; no files are scanned at launch.").font(.caption).foregroundStyle(.secondary)
            LocationAccessGuide(expanded: $navigationState.accessGuideExpanded)
            LocalRecordsEntry { openLocalRecords(caller: .locations) }
        }.confirmationDialog("Forget location?", isPresented: Binding(get: { locationToForget != nil }, set: { if !$0 { locationToForget = nil } }), titleVisibility: .visible) {
            if let scope = locationToForget {
                Button("Forget location", role: .destructive) { if locationsModel.forget(scope) { selection.suspendScope(URL(fileURLWithPath: scope.path), forget: true) }; locationToForget = nil }
                Button("Cancel", role: .cancel) { locationToForget = nil }
            }
        } message: {
            if let scope = locationToForget {
                let count = selection.dependentSelectionCount(for: URL(fileURLWithPath: scope.path))
                Text("Forget " + URL(fileURLWithPath: scope.path).lastPathComponent + " and remove \(count) dependent " + (count == 1 ? "choice" : "choices") + "? No files will be deleted.")
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

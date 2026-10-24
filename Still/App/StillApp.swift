import SwiftUI
import StillCore

@main
struct StillApp: App {
    @NSApplicationDelegateAdaptor(StillApplicationDelegate.self) private var delegate
    @StateObject private var lifecycle = AppLifecycleController.shared
    @StateObject private var alerts = AppLifecycleController.shared.alerts
    #if DEBUG
    @State private var capturePresented = !ProcessInfo.processInfo.arguments.contains(where: {
        ["--design-minimum", "--design-initial-size"].contains($0)
    })
    #endif
    private var initialSize: CGSize {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--design-minimum") { return CGSize(width: 900, height: 640) }
        #endif
        return CGSize(width: 1120, height: 760)
    }
    var body: some Scene {
        Window("Still", id: "workspace") {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--design-gallery") { DesignGallery() }
                else { WorkspaceView(alerts: lifecycle.alerts) }
                #else
                WorkspaceView(alerts: lifecycle.alerts)
                #endif
            }
            #if DEBUG
            .opacity(capturePresented ? 1 : 0)
            .accessibilityHidden(!capturePresented)
            .allowsHitTesting(capturePresented)
            #endif
            .frame(minWidth: 900).background {
                #if DEBUG
                NativeWindowContract(onCaptureFit: { capturePresented = true })
                #else
                NativeWindowContract()
                #endif
            }.modifier(DesignAccessibilityPreview())
        }
        .defaultSize(width: initialSize.width, height: initialSize.height)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show Still") { lifecycle.openWorkspace?() }
            }
        }
        MenuBarExtra("Still storage alerts", systemImage: "internaldrive", isInserted: Binding(get: { StorageAlertsController.futureEnabled && alerts.effectiveMonitoring }, set: { inserted in
            // SwiftUI can echo false while the extra is initially hidden or authorization is pending.
            // Only removal of effective monitoring is a user opt-out.
            if !inserted && alerts.requested && alerts.effectiveMonitoring {
                Task { await alerts.setEnabled(false) }
            }
        })) {
            StillStatusMenu(alerts: lifecycle.alerts)
        }
    }
}

private enum Destination: String, CaseIterable, Identifiable {
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

private struct FixtureItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let size: String
    static let downloads = [
        FixtureItem(id: "trip", name: "Summer trip.mov", path: "Downloads/Trips/Summer trip.mov", size: "1.6 GB"),
        FixtureItem(id: "installer", name: "Editor installer.dmg", path: "Downloads/Editor installer.dmg", size: "420 MB"),
        FixtureItem(id: "guide", name: "Camera guide.pdf", path: "Downloads/Camera guide.pdf", size: "8 MB")
    ]
}

private struct WorkspaceView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var alerts: StorageAlertsController
    @State private var destination = Destination.overview
    @State private var inspecting = false
    @State private var inspected = FixtureItem.downloads[0]
    @State private var appearance = "Automatic"
    @State private var expanded = false
    @State private var folderInspection = AppLifecycleController.shared.inspection
    @State private var selection = AppLifecycleController.shared.selection
    @State private var recovery = AppLifecycleController.shared.recovery
    @State private var recoveryVisible = false
    @State private var nativeInspectionVisible = false
    @State private var homebrewVisible = false
    @State private var managedStorageVisible = false
    @State private var managedStorage = ManagedStorageModel()
    @State private var pipVisible = false
    @State private var dockerVisible = false
    @State private var exclusionsVisible = false
    @State private var diagnosticsVisible = false
    @State private var overviewCloudExpanded = false
    @State private var moreToolsExpanded = false
    @State private var diagnostics = DiagnosticsModel()
    @State private var locationsModel = AppLifecycleController.shared.locations
    @State private var explorerContext = AppLifecycleController.shared.downloadsExplorer
    @State private var planPresentation = AppLifecycleController.shared.planPresentation
    @State private var explorerCaller = Destination.overview
    @State private var planReturnsToExplorer = false
    @State private var scanOrigin = Destination.overview
    @State private var locationToForget: RememberedScope?
    @State private var startupCapacity: StartupVolumeCapacity?
    #if DEBUG
    @State private var injectedAlertOpen = false
    #endif
    private var fixtureMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--fixture-workspace")
        #else
        false
        #endif
    }
    private var showsPlan: Bool { destination == .plan && !recoveryVisible && !inspecting && !nativeInspectionVisible && !homebrewVisible && !pipVisible && !dockerVisible && !managedStorageVisible && !diagnosticsVisible && !exclusionsVisible }
    private var inspectionVisible: Bool { inspecting || nativeInspectionVisible }
    private var contextLabel: String {
        diagnosticsVisible ? "Redacted diagnostics · Explicit local Save" : recoveryVisible ? "Recovery review · Recorded facts only" : selection.execution.isRunning ? "Moving approved files to Trash" : selection.execution.result != nil ? "Cleanup results · individual outcomes" : managedStorageVisible ? "App-managed inventory · selected objects only" : folderInspection.scope != nil ? "Read-only metadata · explicitly selected folder" : fixtureMode ? "Synthetic data — no personal files accessed" : "On-demand storage review"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                AppBrand().padding(.horizontal, StillDesign.Space.sm).padding(.bottom, StillDesign.Space.xl)
                Text("Storage").font(.caption).foregroundStyle(.secondary).padding(.horizontal, StillDesign.Space.sm)
                ForEach(Destination.allCases.filter { $0 != .locations && $0 != .alerts && ($0 != .growth || GrowthHistoryModel.enabled) }) { navigation($0) }
                Text("Settings").font(.caption).foregroundStyle(.secondary).padding(.horizontal, StillDesign.Space.sm).padding(.top, StillDesign.Space.xl)
                navigation(.locations)
                if StorageAlertsController.futureEnabled { navigation(.alerts) }
                Spacer()
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    Label("This Mac", systemImage: "laptopcomputer").font(.callout)
                    CapacityMeter(available: startupCapacity?.available, total: startupCapacity?.total, compact: true)
                    if let reading = startupCapacity {
                        Text("Observed " + reading.observedAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Divider()
                    Label("On-demand scanning", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, StillDesign.Space.sm)

            }
            .padding(.horizontal, StillDesign.Space.md).padding(.vertical, StillDesign.Space.lg)
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background { ChromeSurface(role: .sidebar) }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                if nativeInspectionVisible {
                    StorageExplorerView(model: folderInspection, selection: selection, context: explorerContext,
                        backTitle: "Back to " + explorerCaller.rawValue, back: { nativeInspectionVisible = false; destination = explorerCaller })
                    ActionStrip(message: "\(StillDesign.files(selection.draft.selectedCount)) selected · Nothing changes before confirmation.") {
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
                        backToExplorer: planReturnsToExplorer ? { nativeInspectionVisible = true; planReturnsToExplorer = false } : nil,
                        manageLocations: { destination = .locations }, scopeMessage: locationsModel.message ?? folderInspection.message, presentation: planPresentation)
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                        if recoveryVisible {
                            CleanupRecoveryView(model: recovery)
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
                        else if inspecting { inspection }
                        else {
                            switch destination {
                            case .alerts: StorageAlertsView(controller: alerts)
                            case .growth: GrowthHistoryView(model: GrowthHistoryModel.shared)
                            case .overview: overview
                            case .plan: EmptyView()
                            case .history: history
                            case .locations: locations
                            }
                        }
                    }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
                }
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
                            Button("Back to Overview") { diagnosticsVisible = false; destination = .overview }.disabled(diagnostics.isSaving)
                            Button("Save diagnostics…") { Task { await diagnostics.save() } }.buttonStyle(.borderedProminent).disabled(diagnostics.export == nil || diagnostics.isSaving)
                        }
                    } else if recoveryVisible {
                        ActionStrip(message: "Recovery records are retained. Nothing resumes automatically.") {
                            Button("Return to Overview") { recoveryVisible = false; destination = .overview }.buttonStyle(.borderedProminent)
                        }
                    } else if nativeInspectionVisible && folderInspection.isScanning {
                        ActionStrip(message: "Preliminary observations · No cleanup is running") {
                            Button("Stop scan") { folderInspection.cancel() }.buttonStyle(.borderedProminent)
                        }
                    } else if inspectionVisible {
                        ActionStrip(message: nativeInspectionVisible ? "\(StillDesign.files(selection.draft.selectedCount)) selected" : "Nothing selected") {
                            Button("View cleanup plan") { nativeInspectionVisible = false; inspecting = false; destination = .plan }.buttonStyle(.borderedProminent)
                        }
                    } else if destination == .growth {
                        ActionStrip(message: "Two compatible completed observations reveal net changes.") {
                            Button("Inspect a folder") { if let url = FolderInspection.chooseFolder() { nativeInspectionVisible = true; folderInspection.scan(url) } }.buttonStyle(.borderedProminent)
                        }
                    } else if destination == .overview && !managedStorageVisible && !dockerVisible && !pipVisible && !homebrewVisible {
                        if folderInspection.isScanning {
                            ActionStrip(message: "Manual scan running · No cleanup is running") { EmptyView() }
                        } else {
                        ActionStrip(message: "\(StillDesign.files(selection.draft.selectedCount)) selected · Nothing changes before confirmation.") {
                            Button("Review cleanup plan") { destination = .plan }.buttonStyle(.borderedProminent).disabled(selection.scans.isEmpty && selection.draft.selectedCount == 0)
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
        .task {
            #if DEBUG
            if !injectedAlertOpen, LocalStateLocation.isDisposableTest, StorageAlertsController.futureEnabled,
               let _ = try? LocalStateLocation.root(create: false),
               let fixture = ProcessInfo.processInfo.environment["STILL_TEST_ALERT_OPEN"] {
                injectedAlertOpen = true
                let payload: [AnyHashable: Any] = fixture == "dated" ? ["Still.observedAt": 1_000_000.0] : fixture == "malformed" ? ["Still.observedAt": "invalid"] : [:]
                alerts.openAlert(context: AlertOpenContext(notificationUserInfo: payload))
            }
            #endif
        }
        .task { if await recovery.loadOnce() { recoveryVisible = true } }
        .task { locationsModel.load() }
        .onChange(of: locationsModel.scopes) { _, _ in
            explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
            explorerContext.downloadsScopes = Set(locationsModel.includedDownloads.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        }
        .task { startupCapacity = await Task.detached(priority: .utility) { StartupVolumeCapacity.read() }.value }
        .onAppear { AppLifecycleController.shared.openWorkspace = { openWindow(id: "workspace") } }
        .onReceive(NotificationCenter.default.publisher(for: .stillAlertOpened)) { _ in destination = .overview; exclusionsVisible = false; diagnosticsVisible = false; recoveryVisible = false; inspecting = false; nativeInspectionVisible = false; homebrewVisible = false; pipVisible = false; dockerVisible = false; managedStorageVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await alerts.activated() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in Task { await alerts.activated() } }
        .toolbar {
            contextToolbar
            ToolbarItem(placement: .automatic) {
            Picker("Appearance", selection: $appearance) {
                Text("Automatic").tag("Automatic")
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
            }.controlSize(.small).frame(width: 110).accessibilityLabel("Appearance")
            }
        }
        .preferredColorScheme(appearance == "Automatic" ? nil : appearance == "Dark" ? .dark : .light)
    }

    @ToolbarContentBuilder private var contextToolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) { contextToolbarLabel }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { contextToolbarLabel }
        }
    }
    @ViewBuilder private var contextToolbarLabel: some View {
        if folderInspection.isScanning {
            ToolbarScanStatus(location: folderInspection.scope?.lastPathComponent ?? "selected locations",
                phase: folderInspection.progress.map { $0.phase == .rechecking ? "Rechecking changed coverage (one attempt)…" : $0.phase == .checkingDirectories ? "Checking directory stability…" : "Reading file metadata…" } ?? "Preparing metadata scan…",
                inspectedEntries: folderInspection.progress?.visitedEntries,
                returnToScan: destination == scanOrigin && !nativeInspectionVisible ? nil : { nativeInspectionVisible = false; destination = scanOrigin },
                stop: { folderInspection.cancel() })
        } else { Text(contextLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
    }

    private func navigation(_ value: Destination) -> some View {
        StillSidebarRow(title: value.rawValue, symbol: value.symbol, selected: destination == value,
                        accent: value == .growth ? StillDesign.purple : value == .plan ? StillDesign.teal : value == .history ? .secondary : StillDesign.blue) {
            destination = value
            planReturnsToExplorer = false
            if value == .plan && selection.execution.result != nil { startNewPlan() }
            diagnosticsVisible = false; exclusionsVisible = false
            recoveryVisible = false; inspecting = false; nativeInspectionVisible = false; homebrewVisible = false
            pipVisible = false; dockerVisible = false; managedStorageVisible = false
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

    private var overview: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            HStack(alignment: .top) {
                PageHeader(title: "Storage overview", subtitle: "A clearer picture of what’s on your Mac.")
                Spacer(minLength: StillDesign.Space.md)
                Button("Scan again", action: scanKnownLocations).disabled(locationsModel.included.isEmpty || folderInspection.isScanning || selection.execution.isRunning)
            }
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
                        Button("Review interrupted cleanup") { recoveryVisible = true }
                    }
                }
            }
            if !fixtureMode {
                VolumeSummary(available: startupCapacity?.available, total: startupCapacity?.total,
                              observation: startupCapacity.map { "Observed \($0.observedAt.formatted()) · \($0.metric == "important" ? "Available for important usage" : "Available capacity fallback")" } ?? "Capacity not observed")
            } else if folderInspection.scope == nil {
                SummarySurface {
                    VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                        CapacityMeter(available: 42_800_000_000, total: 512_000_000_000)
                        Text("Synthetic startup volume · Fixture observation").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            scannedLocations
            overviewRecommendations
            if StorageAlertsController.futureEnabled {
                Button { moreToolsExpanded.toggle() } label: {
                    Label("More tools", systemImage: moreToolsExpanded ? "chevron.down" : "chevron.right")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(moreToolsExpanded ? "Expanded" : "Collapsed")
                if moreToolsExpanded {
                FindingRow(category: .managed, title: "Diagnostics", detail: "Review a redacted snapshot and save locally") {
                    Button("Review diagnostics") {
                        diagnostics.review(selection: selection, inspection: folderInspection, recovery: recovery)
                        diagnosticsVisible = true; recoveryVisible = false; managedStorageVisible = false; dockerVisible = false; pipVisible = false; homebrewVisible = false; nativeInspectionVisible = false; inspecting = false
                    }
                }
                FindingRow(category: .managed, title: "App-managed storage", detail: "Libraries, backups and system storage guidance") {
                    Button("Review app-managed storage") { managedStorageVisible = true; homebrewVisible = false; pipVisible = false; dockerVisible = false; nativeInspectionVisible = false; inspecting = false }
                }
                FindingRow(category: .developer, title: "Docker storage", detail: "Review runtime and disk-image measurements") {
                    Button("Review Docker storage") { dockerVisible = true; pipVisible = false; homebrewVisible = false; managedStorageVisible = false; nativeInspectionVisible = false; inspecting = false }
                }
                FindingRow(category: .developer, title: "Homebrew opportunities", detail: "Explicit cache inventory; vendor cleanup remains unavailable") {
                    Button("Review Homebrew opportunities") { homebrewVisible = true; pipVisible = false; dockerVisible = false; managedStorageVisible = false; nativeInspectionVisible = false; inspecting = false }
                }
                FindingRow(category: .developer, title: "Pip cache opportunities", detail: "Review selected cache provenance") {
                    Button("Review pip cache opportunities") { pipVisible = true; homebrewVisible = false; dockerVisible = false; managedStorageVisible = false; nativeInspectionVisible = false; inspecting = false }
                }
                }
            }
        }
    }

    private var overviewRecommendations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                Text("Recommended for review").font(StillDesign.TypeStyle.section)
                RecommendationGroup {
                    overviewCloudRow
                    if overviewCloudExpanded, let report = folderInspection.result?.cloudInventory { CloudInventoryView(report: report).padding(StillDesign.Space.md) }
                    Divider().padding(.horizontal, StillDesign.Space.lg)
                    StorageReviewRow(category: .developer, title: "Xcode build files", detail: "Build-file cleanup isn’t available yet.", value: "Not inspected", meaning: "Unavailable")
                    Divider().padding(.horizontal, StillDesign.Space.lg)
                    overviewDownloadsRow
                    Divider().padding(.horizontal, StillDesign.Space.lg)
                    StorageReviewRow(category: .browser, title: "Browser caches", detail: "Browser cleanup isn’t available yet; manage caches in your browser.", value: "Not inspected", meaning: "Unavailable")
                }
                Text("Moving files to Trash won’t free space until you empty it.").font(.caption).foregroundStyle(.secondary)
            }
    }

    private var overviewCloudRow: some View {
        let action: (() -> Void)? = folderInspection.result == nil ? nil : { overviewCloudExpanded.toggle() }
        let value = folderInspection.result.map { result in
            let report = result.cloudInventory
            return report.unknownMembershipCount > 0 || report.unknownStateCount > 0 ? "Unknown" : overviewBytes(report.localAllocatedBytes)
        } ?? "Not inspected"
        return StorageReviewRow(category: .cloud, title: "Downloaded iCloud files", detail: "Local copies in this location · Cleanup unavailable.", value: value, meaning: "Local allocation · Unknown metadata stays unknown", actionTitle: overviewCloudExpanded ? "Hide iCloud inventory" : "Review iCloud inventory", action: action, identifier: "overviewCloudFinding")
    }
    private var overviewDownloadsRow: some View {
        if selection.retryTargetIDs != nil {
            return StorageReviewRow(category: .downloads, title: "Downloads to review", detail: "A retry includes only unfinished files. Scan again to choose from all observed Downloads files.", value: overviewBytes(selection.overviewDownloadsLogicalBytes), meaning: "Observed logical size", actionTitle: "Scan again to review all files", action: folderInspection.isScanning || selection.execution.isRunning ? nil : { scanKnownLocations() }, identifier: "overviewDownloadsFinding")
        }
        if fixtureMode && folderInspection.scope == nil {
            return StorageReviewRow(category: .downloads, title: "Downloads to review", detail: "Synthetic example · 3 files · Nothing selected automatically.", value: "2.028 GB", meaning: "Synthetic logical size", actionTitle: "Review Downloads", action: { inspecting = true }, identifier: "overviewDownloadsFinding")
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
                    if let result = folderInspection.result {
                        Text("\(folderInspection.scopeReports.count) locations · Current: \(result.scope.lastPathComponent)").font(.caption).foregroundStyle(.secondary).help(result.scope.path)
                        Text("Observed \(result.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    } else if let previous = folderInspection.lastComplete {
                        Text("Current coverage: Unknown · Access unavailable").font(.caption).foregroundStyle(.secondary)
                        Text("Last complete observation: " + previous.observedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                    } else { Text("Choose a folder to understand its local storage.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: StillDesign.Space.sm) {
                    Button("Choose folder…", systemImage: "folder.badge.plus", action: chooseFolderForScan).disabled(folderInspection.isScanning || selection.execution.isRunning)
                    if folderInspection.result != nil { Button("Explore storage") { openExplorer(downloads: false, caller: .overview) }.disabled(selection.execution.isRunning) }
                }
            }
            if let result = folderInspection.result {
                Text(result.isComplete ? "Current location · \(overviewBytes(result.totalLogicalBytes)) logical · \(overviewBytes(result.totalAllocatedBytes)) allocated" : "Partial coverage · Observed logical subtotal \(overviewBytes(result.logicalBytes)) · Remaining bytes unknown")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("overviewScopeCoverage")
                if result.excludedEntryCount > 0 || result.hasUnmeasuredContents { Text("Unmeasured or excluded contents remain unknown.").font(.caption).foregroundStyle(.secondary) }
            }
            if folderInspection.scopeReports.contains(where: { $0.requiresRecheck }) {
                StatusRow(text: "Some locations have partial coverage. Uninspected bytes remain unknown.", symbol: "exclamationmark.circle", role: .caution)
            }
            if folderInspection.isScanning { ProgressView("Rechecking selected locations…").font(.caption) }
            if let message = locationsModel.message { StatusRow(text: message, symbol: "info.circle", role: .caution) }
            if let message = folderInspection.message { StatusRow(text: message, symbol: "info.circle") }
            CleanupScopeNotice(enabled: !folderInspection.isScanning && !selection.execution.isRunning, compact: true, chooseDownloads: chooseDownloads)
        }
    }

    private var inspection: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Button("Back to Overview", systemImage: "chevron.left") { inspecting = false; destination = .overview }
            heading("Downloads inspection", "Synthetic files · Names inspect without selecting.")
            ForEach(FixtureItem.downloads) { item in
                HStack {
                    Button { inspected = item } label: {
                        Label(item.name, systemImage: "doc").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Inspect \(item.name)")
                    Text(item.size).monospacedDigit().foregroundStyle(.secondary)
                }.padding(.vertical, StillDesign.Space.sm)
                Divider()
            }
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                Text(inspected.name).font(.headline)
                Text(inspected.path).textSelection(.enabled)
                Text("Logical size: \(inspected.size)")
                Text("Example ordinary file · Proposed action: Move to Trash. No action is enabled in this fixture workspace.")
                    .foregroundStyle(.secondary)
            }.padding(StillDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                .background(StillDesign.summary, in: RoundedRectangle(cornerRadius: StillDesign.Radius.surface))

        }
    }

    private func isDownloadsLocation(_ url: URL) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-downloads-root"),
           ProcessInfo.processInfo.environment["STILL_TEST_DOWNLOADS_ROOT"] == url.standardizedFileURL.path,
           url.lastPathComponent.hasPrefix("StillSelectionUI-") { return true }
        #endif
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
        guard !leases.isEmpty else { return }
        selection.leaveRetryMode(); scanOrigin = destination
        folderInspection.scanAgain(scopes: leases.map(\.url), leases: leases)
    }
    private func openExplorer(downloads: Bool, caller: Destination) {
        explorerContext = downloads ? AppLifecycleController.shared.downloadsExplorer : AppLifecycleController.shared.locationsExplorer
        if explorerContext.downloadsOnly != downloads { if downloads { explorerContext.openDownloads() } else { explorerContext.openLocations() } }
        explorerContext.allowedScopes = Set(locationsModel.included.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        explorerContext.downloadsScopes = Set(locationsModel.includedDownloads.map { URL(fileURLWithPath: $0.path).standardizedFileURL })
        explorerCaller = caller; nativeInspectionVisible = true; planReturnsToExplorer = false
    }
    private func startNewPlan() {
        planPresentation.reset(); selection.startNewPlan(); planReturnsToExplorer = false; nativeInspectionVisible = false; destination = .plan
        Task { await folderInspection.resetSession() }
    }

    private var history: some View {
        CleanupHistoryView(showRecovery: { recoveryVisible = true; Task { await recovery.refresh() } }, didReset: {
            appearance = "Automatic"; nativeInspectionVisible = false; inspecting = false
            diagnosticsVisible = false; diagnostics = DiagnosticsModel(); exclusionsVisible = false
        })
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "Locations & access", subtitle: "Remember locations to include in your next manual scan.")
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
                    status: locationStatus(scope), included: Binding(get: { scope.isIncluded }, set: { included in
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
                        }
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
            if GrowthHistoryModel.enabled {
                SettingsRow(title: "Custom exclusions", detail: "Explicit path rules reduce scan coverage; fixed protections stay active.") {
                    Button("Manage exclusions") { exclusionsVisible = true }.accessibilityIdentifier("manageExclusions")
                }
            }
        }.confirmationDialog("Forget location?", isPresented: Binding(get: { locationToForget != nil }, set: { if !$0 { locationToForget = nil } }), titleVisibility: .visible) {
            if let scope = locationToForget {
                Button("Forget location", role: .destructive) { if locationsModel.forget(scope) { selection.suspendScope(URL(fileURLWithPath: scope.path), forget: true) }; locationToForget = nil }
                Button("Cancel", role: .cancel) { locationToForget = nil }
            }
        } message: {
            if let scope = locationToForget { Text("Forget " + URL(fileURLWithPath: scope.path).lastPathComponent + " and remove \(selection.dependentSelectionCount(for: URL(fileURLWithPath: scope.path))) dependent choices? No files will be deleted.") }
        }
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

    private func heading(_ title: String, _ subtitle: String) -> some View {
        PageHeader(title: title, subtitle: subtitle)
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

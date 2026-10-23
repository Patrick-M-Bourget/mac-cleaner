import SwiftUI
import StillCore

@main
struct StillApp: App {
    @NSApplicationDelegateAdaptor(StillApplicationDelegate.self) private var delegate
    @StateObject private var lifecycle = AppLifecycleController.shared
    @StateObject private var alerts = AppLifecycleController.shared.alerts
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
            }.frame(minWidth: 900).background { NativeWindowContract() }.modifier(DesignAccessibilityPreview())
        }
        .defaultSize(width: initialSize.width, height: initialSize.height)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show Still") { lifecycle.openWorkspace?() }
            }
        }
        MenuBarExtra("Still storage alerts", systemImage: "internaldrive", isInserted: Binding(get: { StorageAlertsController.futureEnabled && alerts.effectiveMonitoring }, set: { inserted in if !inserted { Task { await alerts.setEnabled(false) } } })) {
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
    @State private var diagnosticsVisible = false
    @State private var diagnostics = DiagnosticsModel()
    @State private var startupCapacity: StartupVolumeCapacity?
    private var fixtureMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--fixture-workspace")
        #else
        false
        #endif
    }
    private var showsPlan: Bool { destination == .plan && !recoveryVisible && !inspecting && !nativeInspectionVisible && !homebrewVisible && !pipVisible && !dockerVisible && !managedStorageVisible && !diagnosticsVisible }
    private var inspectionVisible: Bool { inspecting || nativeInspectionVisible }
    private var contextLabel: String {
        diagnosticsVisible ? "Redacted diagnostics · Explicit local Save" : recoveryVisible ? "Recovery review · Recorded facts only" : selection.execution.isRunning ? "Moving approved files to Trash" : selection.execution.result != nil ? "Cleanup results · individual outcomes" : managedStorageVisible ? "App-managed inventory · selected objects only" : folderInspection.scope != nil ? "Read-only metadata · explicitly selected folder" : fixtureMode ? "Synthetic data — no personal files accessed" : "On-demand storage review"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                HStack(spacing: StillDesign.Space.sm) {
                    Image(systemName: "square.3.layers.3d").foregroundStyle(.white).font(.system(size: 17))
                        .frame(width: 30, height: 30).background(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
                    Text("Still").font(.system(size: 17, weight: .medium))
                }.padding(.bottom, StillDesign.Space.xl)
                Text("Storage").font(.caption).foregroundStyle(.secondary)
                ForEach(Destination.allCases.filter { $0 != .locations && $0 != .alerts && ($0 != .growth || GrowthHistoryModel.enabled) }) { navigation($0) }
                Text("Settings").font(.caption).foregroundStyle(.secondary).padding(.top, StillDesign.Space.xl)
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
                }

            }
            .padding(StillDesign.Space.lg)
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background { ChromeSurface(role: .sidebar) }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                if showsPlan && (!selection.scans.isEmpty || selection.execution.isRunning || selection.execution.result != nil || selection.execution.error != nil) {
                    LiveCleanupPlanView(selection: selection, recheck: { folderInspection.scan($0) }, stopRefresh: { folderInspection.cancel() })
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                        if recoveryVisible {
                            CleanupRecoveryView(model: recovery)
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
                            case .plan: if selection.scans.isEmpty { plan } else { LiveCleanupPlanView(selection: selection, recheck: { folderInspection.scan($0) }, stopRefresh: { folderInspection.cancel() }) }
                            case .history: history
                            case .locations: locations
                            }
                        }
                    }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if diagnosticsVisible {
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
                    } else if showsPlan {
                        ActionStrip(message: "Nothing changes until you confirm the next step.") { Button("Review cleanup") {}.disabled(true) }
                    }
                }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StillDesign.reading)
        }
        .task { if await recovery.loadOnce() { recoveryVisible = true } }
        .task { startupCapacity = await Task.detached(priority: .utility) { StartupVolumeCapacity.read() }.value }
        .onAppear { AppLifecycleController.shared.openWorkspace = { openWindow(id: "workspace") } }
        .onReceive(NotificationCenter.default.publisher(for: .stillAlertOpened)) { _ in destination = .overview; diagnosticsVisible = false; recoveryVisible = false; inspecting = false; nativeInspectionVisible = false; homebrewVisible = false; pipVisible = false; dockerVisible = false; managedStorageVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await alerts.activated() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in Task { await alerts.activated() } }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(contextLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            ToolbarItem(placement: .automatic) {
            Picker("Appearance", selection: $appearance) {
                Text("Automatic").tag("Automatic")
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
            }.frame(width: 120).accessibilityLabel("Appearance")
            }
        }
        .preferredColorScheme(appearance == "Automatic" ? nil : appearance == "Dark" ? .dark : .light)
    }

    private func navigation(_ value: Destination) -> some View {
        StillSidebarRow(title: value.rawValue, symbol: value.symbol, selected: destination == value) {
            destination = value
            diagnosticsVisible = false
            recoveryVisible = false; inspecting = false; nativeInspectionVisible = false; homebrewVisible = false
            pipVisible = false; dockerVisible = false; managedStorageVisible = false
        }.keyboardShortcut(value.shortcut, modifiers: .command)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            heading("Your storage", "Understand what is stored locally before choosing what to clean.")
            if recovery.requiresReview {
                SummarySurface {
                    HStack {
                        StatusRow(text: "Interrupted cleanup needs review", symbol: "exclamationmark.circle", role: .caution)
                        Button("Review interrupted cleanup") { recoveryVisible = true }
                    }
                }
            }
            if !fixtureMode {
                SummarySurface {
                    VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                        Text("This Mac · Startup volume").font(StillDesign.TypeStyle.section)
                        CapacityMeter(available: startupCapacity?.available, total: startupCapacity?.total)
                        if let reading = startupCapacity { Text("Observed \(reading.observedAt.formatted()) · \(reading.metric == "important" ? "Available for important usage" : "Available capacity fallback")").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if StorageAlertsController.futureEnabled {
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
                FindingRow(category: .developer, title: "Homebrew opportunities", detail: "Qualification and supported management guidance") {
                    Button("Review Homebrew opportunities") { homebrewVisible = true; pipVisible = false; dockerVisible = false; managedStorageVisible = false; nativeInspectionVisible = false; inspecting = false }
                }
                FindingRow(category: .developer, title: "Pip cache opportunities", detail: "Review selected cache provenance") {
                    Button("Review pip cache opportunities") { pipVisible = true; homebrewVisible = false; dockerVisible = false; managedStorageVisible = false; nativeInspectionVisible = false; inspecting = false }
                }
            }
            HStack {
                Button("Choose folder…", systemImage: "folder.badge.plus") {
                    if let url = FolderInspection.chooseFolder() {
                    selection.leaveRetryMode()
                        folderInspection.scan(url)
                        nativeInspectionVisible = true
                    }
                }
                if folderInspection.scope != nil {
                    Button("Review scanned folder") { nativeInspectionVisible = true }
                }
            }
            if let result = folderInspection.result {
                Text("Selected scope: \(result.scope.path)").textSelection(.enabled)
                Text("\(result.observations.count) entries observed · \(result.isComplete ? "Completed" : "Partial coverage")")
                Text("Complete scope logical bytes: \(result.totalLogicalBytes.map(String.init) ?? "Unknown") · Complete scope allocated bytes: \(result.totalAllocatedBytes.map(String.init) ?? "Unknown")")
                    .foregroundStyle(.secondary)
                Text("These totals describe the selected scope, separately from startup-volume capacity. Scan inventory is read-only. Moving selected Downloads files requires final confirmation.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            else if folderInspection.scope == nil && fixtureMode {
            SummarySurface {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    CapacityMeter(available: 42_800_000_000, total: 512_000_000_000)
                    Text("Synthetic startup volume · Fixture observation").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Storage findings").font(StillDesign.TypeStyle.section)
            FindingRow(category: .downloads, title: "Downloads", detail: "3 example files · 2.028 GB logical size", consequence: "Moving files to Trash keeps their space occupied until Trash is emptied.") {
                Button("Review Downloads") { inspecting = true }
            }
            Text("Other storage categories are introduced as their adapters are validated. This build displays fixtures only.")
                .font(.callout).foregroundStyle(.secondary)
            } else {
                EmptyState(title: "Start with a folder", detail: "Choose Downloads or another folder to review what is stored locally. Nothing is selected automatically.", symbol: "folder")
            }
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

    private var plan: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            heading("Cleanup plan", "Review categories and their consequences before any action.")
            SelectionSummary(value: "Nothing selected", detail: "Choose exact files")
            Text("Space remains occupied until Finder empties Trash.").foregroundStyle(.secondary)
            Divider()
            if folderInspection.scope == nil && fixtureMode {
            FindingRow(category: .downloads, title: "Downloads", detail: "3 eligible fixture files · 2.028 GB", consequence: "Move selected files to Trash; space remains occupied until emptied.") { EmptyView() }
            Button {
                expanded.toggle()
            } label: {
                Label("Choose items", systemImage: expanded ? "chevron.down" : "chevron.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(spacing: StillDesign.Space.md) {
                    ForEach(FixtureItem.downloads) { item in
                        HStack { Text(item.name); Spacer(); Text(item.size).foregroundStyle(.secondary) }
                    }
                }
            }
            }
            Text("Choose and scan Downloads to build a plan. Nothing is selected automatically.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        CleanupHistoryView(showRecovery: { recoveryVisible = true; Task { await recovery.refresh() } }, didReset: {
            appearance = "Automatic"; nativeInspectionVisible = false; inspecting = false
            diagnosticsVisible = false; diagnostics = DiagnosticsModel()
        })
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            heading("Locations & access", "Review scan coverage and access in one place.")
            if let scope = folderInspection.scope {
                SettingsRow(title: "Selected location", detail: "Explicitly chosen this session") {
                    Label(scope.path, systemImage: "folder").textSelection(.enabled)
                    StatusRow(text: "Scope access is balanced around each scan. No background scan runs.", symbol: "lock")
                }
            } else {
                EmptyState(title: "No folder selected", detail: "Choose a folder from Overview to inspect metadata. Access is requested in context.", symbol: "folder.badge.gearshape")
            }
        }
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

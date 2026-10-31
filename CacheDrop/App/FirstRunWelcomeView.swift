import Foundation
import Darwin
import Observation
import CacheDropCore
import SwiftUI

/// Owns the initial preparation task independently of the sheet, so Close never stops a scan (#478).
@MainActor @Observable final class WelcomeModel {
    enum Step { case welcome, access, scanning, ready, failed }
    static let shared = WelcomeModel()
    var isShowing = false
    private(set) var step = Step.welcome
    private(set) var requestingAccess = false
    private(set) var preparingInventory = false
    private(set) var failure = ""
    private var introduction = true
    private var catalog: CatalogCleanupModel?
    private var preparation: Task<Void, Never>?
    var waitsForAccess: Bool { isShowing && (step == .welcome || step == .access) }

    func decideAtLaunch(migration: LegacyStillMigration.Outcome?, stateExisted: Bool) {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            introduction = ProcessInfo.processInfo.environment["CACHEDROP_TEST_SHOW_WELCOME"] == "1" && !Self.testMarkerExists
            isShowing = introduction || ProcessInfo.processInfo.environment["CACHEDROP_TEST_SHOW_WELCOME"] == "1"
                || ProcessInfo.processInfo.environment["CACHEDROP_TEST_STARTUP_GATE"] == "1"
            step = introduction ? .welcome : .scanning
            return
        }
        #endif
        introduction = FirstRunWelcome(preferences: UserDefaults.standard).shouldShow(migration: migration, stateExisted: stateExisted)
        step = introduction ? .welcome : .scanning
        isShowing = true
    }

    func launch(catalog: CatalogCleanupModel) {
        guard self.catalog == nil else { return }
        self.catalog = catalog
        if !waitsForAccess { begin() }
    }
    func showAccess() { step = .access }
    func reopen() { introduction = true; step = .welcome; isShowing = true }

    func requestAccess() async {
        guard !requestingAccess, let home = CatalogCleanupModel.home else { return }
        requestingAccess = true
        await Task.detached { Self.requestBasicAccess(home: home) }.value
        requestingAccess = false
        begin()
    }
    func begin(retry: Bool = false) {
        step = .scanning
        guard preparation == nil, let catalog else { return }
        preparingInventory = false
        preparation = Task {
            if catalog.isScanning { await catalog.waitForScanCompletion() }
            if retry || catalog.preparedScan == nil { await catalog.rescan() }
            else { await catalog.rescanIfFullDiskAccessGranted() }
            var problem: String?
            while true {
                preparingInventory = false
                if catalog.isScanning { await catalog.waitForScanCompletion() }
                guard let scanID = catalog.preparedScan else {
                    problem = catalog.settingsUnreadable ? CatalogCleanupModel.settingsUnreadableText : "The scan couldn't finish. Try again or continue with available results."
                    break
                }
                let apps = ApplicationsModel.shared
                preparingInventory = true
                await apps.load(plugIns: catalog.plugInInventory, scanID: scanID)
                // Returning from System Settings can start another scan while inventory loads.
                // Only inventory prepared for the current completed catalog can unlock the workspace.
                if catalog.isScanning || catalog.preparedScan != scanID { continue }
                if apps.appsUnreadable || !apps.hasLoaded { problem = "CacheDrop couldn't read the list of apps." }
                break
            }
            failure = problem ?? ""
            preparation = nil
            if step == .scanning {
                step = problem == nil ? .ready : .failed
                if problem == nil && !introduction { isShowing = false }
            }
        }
    }

    /// Also used by View results and Continue with available results. Existing preparation is left running.
    func finish() {
        let needsScan = preparation == nil && (step == .welcome || step == .access) && catalog?.hasScanned == false
        isShowing = false
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            if let marker = Self.testMarker { try? Data().write(to: marker) }
        } else {
            FirstRunWelcome(preferences: UserDefaults.standard).markSeen()
        }
        #else
        FirstRunWelcome(preferences: UserDefaults.standard).markSeen()
        #endif
        if needsScan { begin() }
    }

    /// Reads directory handles only, in order; never writes or recursively reads personal files.
    /// Actual prompt coverage must be established in a clean-account acceptance pass.
    nonisolated private static func requestBasicAccess(home: URL) {
        func openDirectory(_ url: URL) {
            let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd >= 0 { close(fd) }
        }
        openDirectory(home.appendingPathComponent("Downloads"))
        for (folder, suffix) in [("Library/Containers", "Data"), ("Library/Group Containers", "")] {
            let root = home.appendingPathComponent(folder)
            openDirectory(root)
            for child in ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) {
                guard child.path == child.resolvingSymlinksInPath().path else { continue }
                openDirectory(suffix.isEmpty ? child : child.appendingPathComponent(suffix))
            }
        }
    }
    #if DEBUG
    private static var testMarker: URL? { try? LocalStateLocation.root(create: false).appendingPathComponent("welcome-seen") }
    private static var testMarkerExists: Bool { testMarker.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    #endif
}

struct FirstRunWelcomeView: View {
    let model: WelcomeModel
    let catalog: CatalogCleanupModel
    @State private var access = FullDiskAccessModel()
    @State private var furthestProgress = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            HStack {
                AppBrand()
                Spacer()
                CloseButton(identifier: "welcomeCancel") { model.finish() }.disabled(model.requestingAccess)
            }
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                Text(title).font(CacheDropDesign.TypeStyle.sheet).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(model.step == .failed ? "welcomeFailure" : "welcomeStepTitle")
                Text("Nothing is cleaned until you review it.")
                    .font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
            }
            switch model.step {
            case .welcome:
                Text("CacheDrop finds space you can safely get back, and cleans only what you choose.")
                    .font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                StatusRow(text: "It never touches your files without asking, your logins, or Photos, Mail and Messages data.",
                          symbol: "hand.raised", identifier: "welcomeNeverTouches")
            case .access:
                Text("CacheDrop can request access to Downloads and app data. macOS may ask you to allow access. Full Disk Access is optional.")
                    .font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                FullDiskAccessLink(title: "Full Disk Access is optional · Learn more", model: access)
            case .scanning, .ready:
                ScanPreparationProgress(text: progressText, fraction: model.step == .ready ? 1 : furthestProgress, identifier: "welcomeScanProgress")
            case .failed:
                Text(model.failure).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
            }
            if model.step != .scanning {
                Divider()
                SheetFooter {
                    EmptyView()
                } actions: {
                    switch model.step {
                    case .welcome:
                        Button("Continue") { model.showAccess() }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeContinue")
                    case .access:
                        Button("Scan with current access") { model.begin() }.disabled(model.requestingAccess).accessibilityIdentifier("welcomeCurrentAccess")
                        Button(model.requestingAccess ? "Requesting access…" : "Request access…") { Task { await model.requestAccess() } }
                            .disabled(model.requestingAccess).keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeRequestAccess")
                    case .ready:
                        Button("View results") { model.finish() }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeDone")
                    case .failed:
                        Button("Continue with available results") { model.finish() }.accessibilityIdentifier("welcomeAvailableResults")
                        Button("Retry") { model.begin(retry: true) }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeRetry")
                    case .scanning:
                        EmptyView()
                    }
                }
            }
        }
        .padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading).cacheDropButtonRule()
        .interactiveDismissDisabled()
        .onChange(of: fraction, initial: true) { _, value in furthestProgress = max(furthestProgress, value) }
        .onChange(of: model.step) { _, step in if step == .scanning { furthestProgress = fraction } }
    }
    private var title: String {
        switch model.step {
        case .welcome: "Welcome to CacheDrop"
        case .access: "Choose access"
        case .scanning: "Preparing your results"
        case .ready: "Your results are ready"
        case .failed: "Preparation couldn't finish"
        }
    }
    private var progressText: String {
        model.step == .ready ? "Your results are ready" : catalog.isScanning ? catalog.scanProgressText : "Preparing Applications…"
    }
    /// A visual stage estimate, not a work/time percentage. Only actual readiness reaches the end.
    private var fraction: Double {
        if model.step == .ready { return 1 }
        if model.preparingInventory { return 0.98 }
        switch catalog.scanProgress?.phase ?? .starting {
        case .starting: return 0.02
        case .location(_, _, let total):
            return 0.03 + 0.72 * min(1, Double(catalog.scanProgress?.finished ?? 0) / Double(max(1, total)))
        case .removedAppLeftovers: return 0.80
        case .appsAndPlugIns: return 0.86
        case .openApps: return 0.90
        case .storageTrends: return 0.93
        case .appManagedStorage: return 0.96
        }
    }
}

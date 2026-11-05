import Foundation
import Darwin
import Observation
import CacheDropCore
import SwiftUI

/// Owns the initial preparation task independently of the sheet, so Close never stops a scan (#478).
@MainActor @Observable final class WelcomeModel {
    enum Step { case welcome, scanning, ready, failed }
    static let shared = WelcomeModel()
    var isShowing = false
    private(set) var step = Step.welcome
    private(set) var requestingAccess = false
    private(set) var failure = ""
    /// Start Smart clean closes the guide onto Smart clean; every other way out opens Overview (#784).
    private(set) var opensSmartClean = false
    /// First use, or reopened from Help; later launches show only the scanning step, without the welcome's icon.
    private(set) var introduction = true
    private var catalog: CatalogCleanupModel?
    private var preparation: Task<Void, Never>?
    var waitsForAccess: Bool { isShowing && (step == .welcome || requestingAccess) }

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
    func reopen() { introduction = true; step = .welcome; opensSmartClean = false; isShowing = true }
    /// Start scan: today's basic access request, then the scan, with the scanning step on screen at once (#784).
    func start() {
        step = .scanning
        Task { await requestAccess() }
    }

    private func requestAccess() async {
        guard !requestingAccess else { return }
        requestingAccess = true
        if let home = CatalogCleanupModel.home { await Task.detached { Self.requestBasicAccess(home: home) }.value }
        requestingAccess = false
        begin()
    }
    func begin(retry: Bool = false) {
        step = .scanning
        guard preparation == nil, let catalog else { return }
        preparation = Task {
            if catalog.isScanning { await catalog.waitForScanCompletion() }
            if retry || catalog.preparedScan == nil { await catalog.rescan() }
            else { await catalog.rescanIfFullDiskAccessGranted() }
            var problem: String?
            while true {
                if catalog.isScanning { await catalog.waitForScanCompletion() }
                guard let scanID = catalog.preparedScan else {
                    problem = catalog.settingsUnreadable ? CatalogCleanupModel.settingsUnreadableText : "The scan couldn’t finish. Try again or continue with available results."
                    break
                }
                let apps = ApplicationsModel.shared
                await apps.load(plugIns: catalog.plugInInventory, scanID: scanID)
                // Returning from System Settings can start another scan while inventory loads.
                // Only inventory prepared for the current completed catalog can unlock the workspace.
                if catalog.isScanning || catalog.preparedScan != scanID { continue }
                if apps.appsUnreadable || !apps.hasLoaded { problem = "CacheDrop couldn’t read the list of apps." }
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

    /// Close, View Overview, Start Smart clean (`openingSmartClean`) and Continue with available results. Existing
    /// preparation, and an access request under way, are left running.
    func finish(openingSmartClean: Bool = false) {
        let needsScan = preparation == nil && step == .welcome && catalog?.hasScanned == false
        opensSmartClean = openingSmartClean
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

/// The guide (#478, #784): Welcome, then one sheet that scans and shows what it found. Later launches show only the scanning
/// step, which closes by itself once preparation is ready. A failure keeps its own state.
struct FirstRunWelcomeView: View {
    let model: WelcomeModel
    let catalog: CatalogCleanupModel
    @State private var sharing = SetupProgressSharing.shared

    var body: some View {
        Group {
            switch model.step {
            case .welcome:
                OnboardingWelcomeStep(categories: Onboarding.categories, onStart: { model.start() }, onClose: { model.finish() })
            case .scanning, .ready:
                OnboardingScanStep(categories: Onboarding.categories, phase: phase, introduction: model.introduction, sharesSetupProgress: sharing.readyBinding,
                                   onStartSmartClean: { model.finish(openingSmartClean: true) }, onViewOverview: { model.finish() },
                                   onClose: { model.finish() })
            case .failed:
                failed
            }
        }.interactiveDismissDisabled()
    }

    private var phase: OnboardingScanStep.Phase {
        guard model.step == .ready else { return .scanning(found: Onboarding.found(catalog.overview), finished: finished) }
        guard let ready = Onboarding.ready(smartClean: catalog.smartCleanCandidates, catalog: catalog.catalog) else { return .nothingFound }
        return .ready(found: ready.found, top: ready.top.map { .init(category: $0.category, estimate: $0.estimate) })
    }
    /// Lit as the scan reads each category; all of them once it has finished and Applications is being prepared, none before.
    private var finished: Set<CatalogCategory> {
        if let progress = catalog.scanProgress {
            return Onboarding.finished(in: catalog.catalog, phase: progress.phase, lastFinishedRuleID: progress.lastFinishedRuleID)
        }
        return catalog.hasScanned && !model.requestingAccess ? Set(Onboarding.categories) : []
    }

    /// Preparation couldn't finish: today's state (Decision 108).
    private var failed: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            HStack {
                AppBrand()
                Spacer()
                CloseButton(identifier: "welcomeCancel") { model.finish() }
            }
            SheetHeader(title: "Preparation couldn’t finish", identifier: "welcomeFailure")
            Text(model.failure).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
            Divider()
            SheetFooter {
                EmptyView()
            } actions: {
                Button("Continue with available results") { model.finish() }.accessibilityIdentifier("welcomeAvailableResults")
                Button("Retry") { model.begin(retry: true) }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeRetry")
            }
        }
        .padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading).cacheDropButtonRule()
    }
}

import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// The catalog's categories in the app. Nothing here knows a specific rule; rules are data in CacheDropCore.
@MainActor @Observable final class CatalogCleanupModel {
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    /// What the catalog's known locations hold.
    private(set) var discovered: [Candidate] = [] { didSet { indexPickedFiles(); summaryChanged(); offeredChanged() } }
    /// Large and old files in each folder the user picked and scanned, keyed by that folder (`UserFiles`).
    private(set) var pickedFiles: [URL: [Candidate]] = [:] { didSet { indexPickedFiles() } }
    /// The picked folders' files the plan offers, by "dev:ino". A file a catalog rule already offers is left to that rule.
    private(set) var pickedByResource: [String: Candidate] = [:] { didSet { offeredChanged() } }
    /// Build folders in projects inside each folder the user picked and scanned, keyed by that folder (`ProjectBuilds`, #157).
    private(set) var projectBuilds: [URL: [Candidate]] = [:] { didSet { offeredChanged() } }
    /// The picked folders' build folders, once each, unless a catalog rule already offers one.
    var projectBuildCandidates: [Candidate] {
        var seen = Set(discovered.map(\.resourceID))
        return projectBuilds.keys.sorted { $0.path < $1.path }.flatMap { projectBuilds[$0] ?? [] }.filter { seen.insert($0.resourceID).inserted }
    }
    /// Installed apps with their files, offered on the Applications page to uninstall (#177); never on Overview or in the plan.
    private(set) var uninstallable: [Candidate] = [] { didSet { offeredChanged() } }
    /// The plug-ins the last scan read, for the Applications page's Plug-ins section (#176).
    private(set) var plugInInventory: PlugInInventory?
    /// Everything the plan and the Applications page can offer.
    var candidates: [Candidate] { discovered + pickedCandidates + projectBuildCandidates + uninstallable }
    /// The large and old files offered from picked folders, largest first.
    var pickedCandidates: [Candidate] { pickedByResource.values.sorted { $0.estimatedBytes != $1.estimatedBytes ? $0.estimatedBytes > $1.estimatedBytes : $0.url.path < $1.url.path } }
    private func indexPickedFiles() {
        let known = Set(discovered.map(\.resourceID))
        var index: [String: Candidate] = [:]
        for file in pickedFiles.keys.sorted(by: { $0.path < $1.path }).flatMap({ pickedFiles[$0] ?? [] }) where !known.contains(file.resourceID) && index[file.resourceID] == nil {
            index[file.resourceID] = file
        }
        pickedByResource = index
    }
    private(set) var isScanning = false
    private(set) var hasScanned = false { didSet { summaryChanged() } }
    /// The running catalog scan's progress, one location at a time (#128); nil when no scan is running. Only a finished
    /// location changes Overview's summary, not the phase.
    private(set) var scanProgress: CatalogScanProgress? {
        didSet { if oldValue?.finished != scanProgress?.finished || oldValue?.found.count != scanProgress?.found.count { summaryChanged() } }
    }
    /// Watches for Full Disk Access being granted while CacheDrop was away (#124, `rescanIfFullDiskAccessGranted`).
    var fullDiskAccessRescan = FullDiskAccessRescan()
    /// The one selection Smart clean, the Cleanup plan and Applications share, recommended items ticked to start (#349).
    private(set) var selections = CleanupSelections()
    /// Every page's ticked candidate ids.
    private var selectedIDs: Set<String> { selections.ticked }
    /// Moves on only when `page`'s chosen items change, or the dry run or a run does, so its open review sheet stays open
    /// while background work ends or another page's choices change (#307, #333).
    func selectionRevision(for page: CleanupSelections.Source) -> UInt64 { selections.revision(of: page) }
    /// Every page's revision, for watching whether any page's choices changed.
    var selectionRevisions: [UInt64] { CleanupSelections.Source.allCases.map(selections.revision(of:)) }
    /// Ticks newly recommended items and notes each page's choices after a change; the revision moves only if they differ.
    private func noteChoices() { selections.noteChoices(among: candidates, recommended: recommendedCandidates, held: heldCandidates) }
    /// What something held at the scan, or whose owner runs now (#374): listed unticked, never ticked for you.
    private var heldCandidates: [Candidate] { candidates.filter { $0.hold != nil } + recommendedPlan.held }
    private(set) var isRunning = false
    /// A cleanup changed files since the last catalog scan, so the next one is recorded as a post-cleanup rescan (#126).
    private var rescanFollowsCleanup = false
    private(set) var result: CatalogExecutionResult?
    /// The run whose disk is read again a minute after its Docker prunes (#411), and whether that check has finished.
    private var settleCheck: (batchID: UUID, finished: Bool)?
    /// Results' line under the measured freed space for `result` (#411): nil until the check finishes, then what it found.
    func settledLine(for result: CatalogExecutionResult) -> String? {
        result.settledLine(checked: settleCheck?.batchID == result.batchID && settleCheck?.finished == true)
    }
    /// Whether Results say a check is coming for `result`: until the minute's line is there (#411).
    func isSettling(_ result: CatalogExecutionResult) -> Bool { settleCheck?.batchID == result.batchID && settledLine(for: result) == nil }
    /// The running cleanup as the Cleaning up screen draws it (#355); nil when none runs.
    private(set) var runProgress: CleanupRunProgress?
    /// The startup disk's used space and total when the run began, which the screen's bar shaves from (#355).
    private(set) var runCapacity: (usedAtStart: Int64, total: Int64)?
    private var runRecords: [CleanupRecord] = []
    private(set) var message: String?
    /// The Protected items settings couldn't be read, so nothing could be scanned or checked (#310). Every page that cleans
    /// and Overview say so once, with Try again; never "Your choices changed" or "Nothing to review".
    private(set) var settingsUnreadable = false { didSet { summaryChanged() } }
    static let settingsUnreadableText = "CacheDrop couldn’t read your Protected items, so it can’t check what’s safe to clean."
    /// Why a rule kept items back, such as copies whose use couldn't be checked.
    private(set) var notes: [CatalogNote] = []
    /// Guidance-only categories found at the last scan. Never candidates, never in a plan. Set only by the guidance
    /// scan (`CatalogCleanupModel+Guidance.swift`), which lives in its own file and so can't use a private setter.
    var guidance: [GuidanceFinding] = []
    var guidanceStatus: String?
    /// Rules whose owner keeps its data elsewhere by a setting; they offer nothing.
    private(set) var overriddenRules: [CleanupRule] = []
    /// Rules CacheDrop can't read without Full Disk Access (Safari's cache): shown as not accessible, never as 0.
    private(set) var notAccessibleRules: [CleanupRule] = [] { didSet { summaryChanged() } }
    /// Names of owners that were running at the last scan. Their items stay choosable; the checks refuse them.
    private(set) var runningOwners: Set<String> = []
    /// The running owners themselves, by name, and those whose app (not only a command-line tool) is open (#138).
    private var runningOwnerDetails: [String: RuleOwner] = [:]
    private(set) var openApps: Set<String> = []
    /// Apps the user asked to quit: still waiting, or still open after the wait.
    private(set) var quitStates: [String: AppQuitState] = [:]
    enum AppQuitState { case quitting, stillOpen }
    /// Each candidate's owner name at the last scan, so views never look owners up while drawing.
    private var ownerNames: [String: [String]] = [:]
    private var executor: CleanupExecutor?
    /// The Settings dry run, off by default: with it on, the whole flow runs and nothing changes on disk (Decision 27).
    var dryRun: Bool {
        didSet {
            if oldValue != dryRun { selections.revise() }
            if !LocalStateLocation.isDisposableTest { UserDefaults.standard.set(dryRun, forKey: PreferenceKeys.dryRun) }
        }
    }

    init() {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            // A disposable test run starts with it off; a journey that asserts nothing changed turns it on (DEBUG seam).
            dryRun = ProcessInfo.processInfo.environment["CACHEDROP_TEST_DRY_RUN"] == "1"
            return
        }
        #endif
        dryRun = UserDefaults.standard.bool(forKey: PreferenceKeys.dryRun)
    }

    /// The home folder whose known locations the catalog sizes. Debug UI tests inject a temp
    /// fixture home; a disposable test run without one sees no catalog locations at all.
    static var home: URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            guard let path = ProcessInfo.processInfo.environment["CACHEDROP_TEST_CATALOG_HOME"] else { return nil }
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let prefix = "CacheDropTestHome-"
            guard url.lastPathComponent.hasPrefix(prefix), UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil,
                  ["tmp", "T"].contains(url.deletingLastPathComponent().lastPathComponent) else { return nil }
            return url
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// The home folder the check protects: the catalog's, or with none (a debug test run without a fixture home) the real
    /// one, so its protected folders are still never taken from a picked folder.
    static var checkHome: URL { home ?? FileManager.default.homeDirectoryForCurrentUser }

    /// The user's own `/private/var/folders` entry, for rules based there (Chrome's code-sign copies).
    /// A debug test home stands one in at `<home>/.cachedrop-test-user-folder`, so a UI test never reads the real one.
    static var userFolder: URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            guard let folder = home?.appendingPathComponent(".cachedrop-test-user-folder"), FileManager.default.fileExists(atPath: folder.path) else { return nil }
            return folder
        }
        #endif
        return Catalog.currentUserFolder()
    }

    /// Where a tool rule's executable is found. A debug test home only ever finds stand-ins inside
    /// `<home>/.cachedrop-test-tools`, so a UI test never runs a real tool. The sandboxed UI test runner quarantines the
    /// stand-ins it writes, and macOS won't run a quarantined script, so the attribute is cleared here.
    static var locateTool: @Sendable (ToolCommand) -> URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            guard let home else { return { _ in nil } }
            return { command in
                let tool = command.executables.lazy.map { home.appendingPathComponent(".cachedrop-test-tools/" + URL(fileURLWithPath: $0).lastPathComponent) }
                    .first { FileManager.default.isExecutableFile(atPath: $0.path) }
                if let tool { removexattr(tool.path, "com.apple.quarantine", 0) }
                return tool
            }
        }
        #endif
        return ToolCommand.installed
    }

    /// Where system-wide settings (administrator and managed browser policies) are read. A debug test home
    /// stands in for it, so a UI test never depends on this Mac's policies.
    static var systemRoot: URL {
        #if DEBUG
        if LocalStateLocation.isDisposableTest, let home { return home }
        #endif
        return URL(fileURLWithPath: "/")
    }

    /// iCloud as the catalog reads it. A debug test home stands in a fixture whose states come from
    /// `<home>/.cachedrop-test-icloud.json`, so a UI test never reads or evicts anything in real iCloud Drive.
    static var cloud: any UbiquitousItemAccess {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureUbiquitousItems(home: home) }
        #endif
        return SystemUbiquitousItems()
    }

    /// Which apps are installed, for files from deleted apps (#173). A debug test run never asks Spotlight or Launch Services:
    /// only the bundle IDs listed in `<home>/.cachedrop-test-installed-apps`, one per line, are installed.
    static var appPresence: any AppPresence {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureAppPresence(home: home) }
        #endif
        return SystemAppPresence()
    }

    /// Overview's summary. While the first scan runs it covers the locations finished so far, so rows and the total fill in
    /// as each one completes (#128); nil until the first one has. Read on every redraw, so it is built once per change in
    /// `discovered`, `hasScanned`, `settingsUnreadable` or a finished location, not on each read (#362).
    var overview: CatalogOverview? {
        summary.value(at: summaryRevision) {
            // Nothing was read, so nothing is "nothing to review" (#310).
            if settingsUnreadable { return nil }
            if hasScanned { return CatalogOverview(catalog: catalog, candidates: discovered, notAccessible: notAccessibleRules) }
            return scanProgress.flatMap { $0.finished > 0 ? CatalogOverview(catalog: catalog, candidates: $0.found) : nil }
        }
    }
    /// Moves whenever what `overview` is built from changes. Observed, so a view that read the stored summary redraws.
    private var summaryRevision: UInt64 = 0
    @ObservationIgnored private var summary = BuiltPerRevision<CatalogOverview?>()
    private func summaryChanged() { summaryRevision &+= 1 }
    /// Every candidate grouped as Overview groups them, for the plan's categories and the Applications page's Leftovers row:
    /// built once per change in `candidates` (`discovered`, the picked folders' files and builds, `uninstallable`), #362.
    private var offeredOverview: CatalogOverview { offered.value(at: offeredRevision) { CatalogOverview(catalog: catalog, candidates: candidates) } }
    private var offeredRevision: UInt64 = 0
    @ObservationIgnored private var offered = BuiltPerRevision<CatalogOverview>()
    private func offeredChanged() { offeredRevision &+= 1 }
    /// "Checking Xcode DerivedData… 4 of 31", then each phase after discovery (#308): one quiet line while the catalog scan runs (Decision 25).
    var scanProgressText: String { (scanProgress?.phase ?? .starting).progressText }
    /// Owners of the rule's items that were running at the last scan, in name order.
    func runningOwnerNames(for rule: CleanupRule) -> [String] {
        Set(candidates(for: rule).flatMap { ownerNames[$0.id] ?? [] }).intersection(runningOwners).sorted()
    }
    /// The plan's line for each running owner of the rule: an open app offers to quit, a tool offers a check (#138).
    func runningOwnerNotices(for rule: CleanupRule) -> [(name: String, notice: RunningOwnerNotice)] {
        runningOwnerNames(for: rule).map { ($0, RunningOwnerNotice(name: $0, appOpen: openApps.contains($0), stillOpen: quitStates[$0] == .stillOpen)) }
    }

    /// Asks CacheDrop's quitter; a debug UI test run never asks a real app to quit.
    nonisolated static var quitter: any AppQuitting {
        #if DEBUG
        // Only fixture apps run from the test's own home are seen and asked to quit (#377).
        if LocalStateLocation.isDisposableTest {
            return ProcessInfo.processInfo.environment["CACHEDROP_TEST_CATALOG_HOME"].map { FixtureAppQuitter(root: URL(fileURLWithPath: $0)) }
                ?? SystemAppQuitter(sendsRequests: false)
        }
        #endif
        return SystemAppQuitter()
    }

    /// Plug-in products to uninstall (#176): their formats, own support files and shared items, never what is `offered` elsewhere.
    nonisolated private static func plugIns(home: URL, system: URL, installed: [InstalledApp], receipts: ReceiptListings, offered: [Candidate],
                                            exclusions: ExclusionPolicy) -> (PlugInInventory, [Candidate]) {
        let inventory = PlugInInventory.scan(home: home, systemRoot: system, receipts: receipts)
        let owners = ApplicationsInventory.plugIns(inventory).map { ContentOwner($0) } + installed.map { ContentOwner($0) }
        let content = MusicContent.scan(owners: owners, home: home, systemRoot: system).items
        return (inventory, PlugInUninstall.scan(inventory, apps: installed, receipts: receipts, content: content, systemRoot: system, offered: offered, exclusions: exclusions))
    }

    /// Which owners are running, and which of them as an open app.
    nonisolated private static func running(_ owners: [String: RuleOwner], quitter: any AppQuitting) -> ([String: RuleOwner], Set<String>) {
        let checker = SystemRunningAppChecker().listedOnce()
        let running = owners.filter { checker.isRunning($0.value) == true }
        return (running, Set(running.values.filter { quitter.isOpen($0.bundleIDs) }.map(\.name)))
    }
    private func setRunning(_ owners: [String: RuleOwner], open: Set<String>) {
        runningOwnerDetails = owners; runningOwners = Set(owners.keys); openApps = open
        quitStates = quitStates.filter { owners[$0.key] != nil }
    }

    /// Looks again at the owners that were running, without a full scan. The checks run again at review either way.
    func checkRunningOwnersAgain() async {
        let owners = runningOwnerDetails, quitter = Self.quitter
        let (running, open) = await Task.detached(priority: .userInitiated) { Self.running(owners, quitter: quitter) }.value
        setRunning(running, open: open)
        // An owner that quit puts its items back in the recommended plan, ticked unless the user unticked them (#349).
        noteChoices()
    }

    /// Sends the owner's app a normal quit request, like ⌘Q, only because the user asked. When it quits, CacheDrop checks again;
    /// when it doesn't (unsaved work, or it refused), the plan says it is still open.
    func quitApp(named name: String) async {
        guard let owner = runningOwnerDetails[name], quitStates[name] != .quitting else { return }
        quitStates[name] = .quitting
        let outcome = await AppQuitRequest(quitter: Self.quitter).quit(owner)
        await checkRunningOwnersAgain()
        if runningOwners.contains(name) { quitStates[name] = outcome == .quit ? nil : .stillOpen }
    }

    func candidates(for rule: CleanupRule) -> [Candidate] { candidates.filter { $0.ruleID == rule.id } }
    func estimatedBytes(for rule: CleanupRule) -> Int64 { candidates(for: rule).reduce(0) { $0 + $1.estimatedBytes } }
    func sizeComplete(for rule: CleanupRule) -> Bool { candidates(for: rule).allSatisfy(\.sizeComplete) }
    func sizeIsEstimate(for rule: CleanupRule) -> Bool { candidates(for: rule).contains(where: \.sizeIsEstimate) }
    /// The Cleanup plan's chosen items; files from deleted apps are chosen on the Applications page (Decision 51).
    var selectedCandidates: [Candidate] { selections.chosen(on: .plan, from: candidates) }
    /// Whether the user changed any page's ticks from the recommended default: what quitting would lose (#270, #349).
    var anyPageDiffersFromRecommended: Bool { selections.differsFromRecommended(candidates) }
    /// Whether the user changed a category's ticks from the recommended default, for Overview's "Selected" (#349).
    func selectionDiffersFromRecommended(_ rules: [CleanupRule]) -> Bool { selections.differsFromRecommended(rules.flatMap(candidates(for:))) }
    /// The Applications page's chosen items.
    var applicationsSelected: [Candidate] { selections.chosen(on: .applications, from: candidates) }
    /// Rules with at least one chosen item.
    var selectedRuleCount: Int { Set(selectedCandidates.map(\.ruleID)).count }
    var selectedCount: Int { selectedCandidates.count }
    /// The space the plan's chosen items would release: Trash-bound items free nothing until the Trash is emptied (#350, SPEC section 6).
    var estimatedBytes: Int64 { selectedCandidates.filter(\.releasesSpace).reduce(0) { $0 + $1.estimatedBytes } }
    var canEdit: Bool { !isScanning && !isRunning && !AppLifecycleController.shared.operationInProgress && !AppLifecycleController.shared.maintenanceInProgress }
    var canReview: Bool { canEdit && selectedCount > 0 }
    /// Why choices and the dry run can't be changed now, for a disabled control's tooltip; nil when they can (#310).
    var editBlockedReason: String? {
        if isScanning { return "Wait for the scan to finish" }
        if isRunning || AppLifecycleController.shared.operationInProgress { return "Wait for the cleanup to finish" }
        if AppLifecycleController.shared.maintenanceInProgress { return "Wait while CacheDrop tidies its history" }
        return nil
    }
    func isSelected(_ rule: CleanupRule) -> Bool { candidates(for: rule).contains { selectedIDs.contains($0.id) } }
    func isSelected(_ candidate: Candidate) -> Bool { selectedIDs.contains(candidate.id) }
    /// The plan's categories, grouped as Overview groups them, picked folders' files included. Files from deleted apps
    /// are on the Applications page instead (Decision 51).
    var planCategories: [CatalogOverview.Row] { offeredOverview.rows.filter { CleanupSelections.Source.page(of: $0) == .plan } }
    /// Whether the plan has a row for `category` now.
    func plans(_ category: CatalogCategory) -> Bool { planCategories.contains { $0.category == category } }
    /// The Applications page's Leftovers row; nil when none were found.
    var leftoversRow: CatalogOverview.Row? { offeredOverview.rows.first { $0.category == .leftovers } }
    /// The items to uninstall an Applications row with, by its id (`AppUninstall.Target.path`): an installed app's (#177), or
    /// a plug-in product's, shared items included (#176); empty when it can't be uninstalled here.
    func uninstallItems(ofRow id: String) -> [Candidate] { uninstallable.filter { $0.isUninstalled(with: id) } }
    func selectionState(ofRow id: String) -> CategorySelectionState {
        CategorySelection(rules: AppRuleFamily.uninstallRules, candidates: uninstallItems(ofRow: id), selected: selectedIDs).state
    }
    /// An app's checkbox, as a category's (#240): returns true when only its possibly related items are left to choose one by one.
    func toggleRow(_ id: String) -> Bool {
        toggle(CategorySelection(rules: AppRuleFamily.uninstallRules, candidates: uninstallItems(ofRow: id), selected: selectedIDs))
    }
    func selectionState(for rules: [CleanupRule]) -> CategorySelectionState { categorySelection(rules).state }
    /// What a checkbox over `rules` shows and does (#240), over `items` when given (Smart clean's recommended items), else
    /// everything the rules found. Items chosen one by one, and held items (#374), are never ticked with it.
    func categorySelection(_ rules: [CleanupRule], items: [Candidate]? = nil) -> CategorySelection {
        CategorySelection(rules: rules, candidates: items ?? rules.flatMap(candidates(for:)), selected: selectedIDs)
    }
    /// The category's or rule's checkbox (#240): chooses what may be chosen together or clears every chosen item. Returns true when
    /// nothing may be chosen together and nothing is chosen, so the category lists its items to choose one by one.
    @discardableResult func toggleCategory(_ rules: [CleanupRule]) -> Bool { toggle(categorySelection(rules)) }
    @discardableResult func toggle(_ selection: CategorySelection) -> Bool {
        guard canEdit else { return false }
        switch selection.toggle {
        case .choose(let ids): selections.set(ids, ticked: true)
        case .clear(let ids): selections.set(ids, ticked: false)
        case .showItems: return true
        }
        noteChoices()
        return false
    }

    /// Rescans the remembered, included folders. Set by the workspace; called once after each scan `rescan` starts,
    /// so those folders are scanned along with the catalog (#125, #306).
    var scanRememberedFolders: (() -> Void)?
    /// A rescan asked for while a scan ran; it starts once that scan ends (#306).
    private var rescanPending = false
    /// The launch scan: once, until a scan has finished.
    func scanIfNeeded() async { if !hasScanned { await rescan() } }
    /// CacheDrop scans again by itself (#306): at launch, when a run ends and after a Put back, whichever page is open.
    /// Asked while a scan runs, it scans again once that one ends. Each scan it starts rechecks the remembered folders once.
    func rescan() async {
        if isScanning { rescanPending = true; return }
        if await scan(rescan: true) { scanRememberedFolders?() }
    }
    /// Read-only sizing of the catalog's known locations. False when it couldn't start: a scan or a cleanup is running.
    @discardableResult func scan() async -> Bool { await scan(rescan: false) }
    private func scan(rescan: Bool) async -> Bool {
        let lifecycle = AppLifecycleController.shared
        // History holds the maintenance lease for a moment: scan once it lets go, never not at all (#310). A rescan
        // waits as a rescan, so it still rechecks the remembered folders once when it runs (#332).
        if lifecycle.maintenanceInProgress, !isScanning, !isRunning, !lifecycle.operationInProgress {
            lifecycle.afterMaintenance.waitFor(.catalogScan, rescan: rescan) { asRescan in
                Task { if asRescan { await self.rescan() } else { await self.scan() } }
            }
            return false
        }
        guard canEdit else { return false }
        await scanCatalog()
        // Something changed on disk while it ran, such as a Put back: scan again, as its own rescan.
        if rescanPending { rescanPending = false; Task { await self.rescan() } }
        return true
    }
    private func scanCatalog() async {
        isScanning = true; message = nil; scanProgress = CatalogScanProgress()
        defer { isScanning = false; hasScanned = true; scanProgress = nil }
        guard let home = Self.home else { discovered = []; uninstallable = []; notes = []; overriddenRules = []; notAccessibleRules = []; setRunning([:], open: []); ownerNames = [:]; return }
        // Excluded items are never offered (SPEC section 2); without the settings nothing can be offered safely.
        guard let exclusions = try? await ExclusionsModel.shared.policyForScan() else {
            discovered = []; uninstallable = []; notes = []; overriddenRules = []; notAccessibleRules = []; setRunning([:], open: []); ownerNames = [:]
            settingsUnreadable = true; return
        }
        settingsUnreadable = false
        let catalog = catalog
        let locate = Self.locateTool, system = Self.systemRoot
        let userFolder = Self.userFolder, cloud = Self.cloud
        // What grew records each completed catalog scan (#119).
        let growth = await StorageTrendsHistoryModel.shared.beginCatalog(home: home, exclusionFingerprint: exclusions.fingerprint)
        let quitter = Self.quitter
        // Discovery reports each location as it goes; the steps reach the main actor in order (#128).
        // After discovery, each later phase is named too (#308).
        let (steps, reporter) = AsyncStream.makeStream(of: CatalogScanStep.self)
        let progress = Task { for await step in steps { scanProgress?.apply(step) } }
        let presence = Self.appPresence.snapshot(), own = Bundle.main.bundleIdentifier
        let scanned = await Task.detached(priority: .userInitiated) { () -> CatalogScanResult in
            // Probed once per scan, at launch too, and shared with the guidance scan: it only opens a protected folder
            // and never prompts (#117).
            let access = FullDiskAccessProbe(home: home).status()
            let discovered = catalog.discovery(home: home, userFolder: userFolder, exclusions: exclusions, locateTool: locate, systemRoot: system, cloud: cloud,
                                               access: access, progress: { step in
                                                   reporter.yield(.discovery(step))
                                                   #if DEBUG
                                                   if case .finished = step { Self.pauseForTests() }
                                                   #endif
                                               })
            func enter(_ phase: CatalogScanPhase) {
                reporter.yield(.phase(phase))
                #if DEBUG
                Self.pauseForTests()
                #endif
            }
            enter(.removedAppLeftovers)
            // Installer receipts, read once for leftovers, app uninstall, plug-ins and their guidance (#318). A debug test run reads the
            // fixture system root's, so never this Mac's.
            let listings = ReceiptListings.read(under: system), receipts = ReadReceipts(listings, home: home)
            // Files from deleted apps (#173), except what a catalog rule already offers, holds or sits inside.
            let found = RemovedAppLeftovers.scan(home: home, apps: presence, receipts: receipts, exclusions: exclusions)
            let leftovers = RemovedAppLeftovers.notOffered(by: discovered.candidates, found)
            // Installed apps with their files (#177), each read once.
            enter(.appsAndPlugIns)
            let apps = ApplicationsInventory.withUninstallers(presence.installedApps() ?? [], excluding: own, home: home).flatMap { app, uninstaller in
                AppUninstall.scan(app, uninstaller: uninstaller, excluding: own, home: home, apps: presence, receipts: receipts, leftovers: found, offered: discovered.candidates,
                                  exclusions: exclusions)
            }
            // Plug-in products (#176): their formats, own support files and shared items, never what is offered above.
            let (inventory, plugIns) = Self.plugIns(home: home, system: system, installed: presence.installedApps() ?? [], receipts: listings,
                                                    offered: discovered.candidates + found + apps,
                                                    exclusions: exclusions)
            var owners: [String: RuleOwner] = [:], names: [String: [String]] = [:]
            for candidate in discovered.candidates + leftovers + apps + plugIns {
                // A plug-in product's hosts must be closed too (#176).
                guard let owner = catalog.owner(for: candidate) else { continue }
                for owner in [owner] + (candidate.uninstall?.plugIn?.hosts ?? []) { owners[owner.name] = owner; names[candidate.id, default: []].append(owner.name) }
            }
            enter(.openApps)
            let running = Self.running(owners, quitter: quitter)
            reporter.finish()
            return CatalogScanResult(discovery: discovered, overriddenRules: catalog.overriddenRules(home: home, systemRoot: system), owners: running.0, openOwners: running.1,
                                     ownerNames: names, access: access, leftovers: leftovers, uninstallable: apps + plugIns, plugIns: inventory,
                                     receipts: listings)
        }.value
        await progress.value
        scanProgress?.phase = .storageTrends
        await StorageTrendsHistoryModel.shared.completeCatalog(scanned.discovery, catalog: catalog, fullDiskAccess: scanned.access, token: growth, afterCleanup: rescanFollowsCleanup)
        rescanFollowsCleanup = false
        fullDiskAccessRescan.scanned(scanned.access)
        discovered = scanned.discovery.candidates + scanned.leftovers; uninstallable = scanned.uninstallable; plugInInventory = scanned.plugIns
        notes = scanned.discovery.notes; notAccessibleRules = scanned.discovery.notAccessible; overriddenRules = scanned.overriddenRules
        setRunning(scanned.owners, open: scanned.openOwners); ownerNames = scanned.ownerNames
        keepOnlyCurrentChoices()
        scanProgress?.phase = .appManagedStorage
        await scanGuidance(home: home, fullDiskAccess: scanned.access, receipts: scanned.receipts)
        // Full Disk Access granted while it ran (from the welcome, during the launch scan): scan again once, by itself (#310).
        if fullDiskAccessRescan.scanEnded(probing: FullDiskAccessProbe(home: home)) { rescanPending = true }
    }
    /// What one catalog scan found, handed from the background task to the model.
    private struct CatalogScanResult: Sendable {
        let discovery: CatalogDiscovery
        let overriddenRules: [CleanupRule]
        /// Every owner to close, by name, and those running now.
        let owners: [String: RuleOwner]
        let openOwners: Set<String>
        /// Each candidate's owners' names, by candidate id.
        let ownerNames: [String: [String]]
        let access: FullDiskAccessStatus
        /// Files from deleted apps (#173).
        let leftovers: [Candidate]
        /// Installed apps' and plug-in products' items (#177, #176).
        let uninstallable: [Candidate]
        let plugIns: PlugInInventory
        /// The scan's one read of the installer receipts, for the guidance scan's plug-in products (#318).
        let receipts: ReceiptListings
    }
    #if DEBUG
    /// A disposable test run can slow discovery down (`CACHEDROP_TEST_DISCOVERY_PAUSE`, seconds after each location), so a UI journey sees
    /// Overview fill in while the fixture scan runs. Never set outside tests.
    nonisolated private static func pauseForTests() {
        guard LocalStateLocation.isDisposableTest, let pause = ProcessInfo.processInfo.environment["CACHEDROP_TEST_DISCOVERY_PAUSE"].flatMap(Double.init), pause > 0 else { return }
        Thread.sleep(forTimeInterval: min(pause, 2))
    }
    /// A disposable test run can hold each finished cleanup item (`CACHEDROP_TEST_CLEANUP_PAUSE`, seconds), so a UI journey
    /// sees the Cleaning up screen tick off (#355). Never set outside tests.
    nonisolated private static func cleanupPauseForTests() async {
        guard LocalStateLocation.isDisposableTest, let pause = ProcessInfo.processInfo.environment["CACHEDROP_TEST_CLEANUP_PAUSE"].flatMap(Double.init), pause > 0 else { return }
        try? await Task.sleep(for: .seconds(min(pause, 5)))
    }
    /// A disposable test run can shorten the wait before measuring again (`CACHEDROP_TEST_LATER_WAIT`, seconds), so a UI
    /// journey sees Results' "check again" resolve (#411). Never set outside tests.
    private static func laterWaitForTests() -> Double? {
        guard LocalStateLocation.isDisposableTest, let seconds = ProcessInfo.processInfo.environment["CACHEDROP_TEST_LATER_WAIT"].flatMap(Double.init), seconds >= 0 else { return nil }
        return min(seconds, 10)
    }
    #endif
    /// Drops chosen items that are no longer offered, and says so. The revision moves only when a page's choices changed (#307).
    private func keepOnlyCurrentChoices() {
        if selections.keepOnly(candidates, recommended: recommendedCandidates, held: heldCandidates) { message = "Some items changed or are no longer on this Mac and were removed from your plan." }
    }

    /// Lists a picked folder's large and old files from its finished scan, and its projects' build folders. Read-only; nothing is chosen.
    func showPickedFiles(_ scan: ScanResult) async {
        guard !isRunning, let exclusions = try? await ExclusionsModel.shared.policyForScan() else { return }
        let home = Self.checkHome
        let (found, builds) = await Task.detached(priority: .userInitiated) {
            (UserFiles.candidates(in: scan, exclusions: exclusions, home: home), ProjectBuilds.candidates(in: scan.scope, exclusions: exclusions, home: home))
        }.value
        guard !isRunning else { return }
        pickedFiles[scan.scope.standardizedFileURL] = found
        projectBuilds[scan.scope.standardizedFileURL] = builds
        keepOnlyCurrentChoices()
    }
    /// A picked folder was forgotten, lost access or must be scanned again: its files are no longer offered.
    func forgetPickedFiles(_ scope: URL? = nil) {
        guard !isRunning else { return }
        if let scope { pickedFiles[scope.standardizedFileURL] = nil; projectBuilds[scope.standardizedFileURL] = nil } else { pickedFiles = [:]; projectBuilds = [:] }
        keepOnlyCurrentChoices()
    }
    func setSelected(_ candidate: Candidate, _ selected: Bool) { setSelected([candidate], selected) }
    /// Ticks or unticks found items on any page; every page that lists them shows it (#349).
    func setSelected(_ items: [Candidate], _ selected: Bool) {
        let found = Set(candidates.map(\.id)), items = items.filter { found.contains($0.id) }
        guard canEdit, !items.isEmpty else { return }
        selections.set(items, ticked: selected)
        noteChoices()
    }

    /// The recommended plan as the last scan sees it (`RecommendedPlan`): what an owner running at the scan holds is in `recommendedHeld` (#374).
    /// The full checks run when it is chosen, and again in the review.
    var recommendedCandidates: [Candidate] { recommendedPlan.candidates }
    /// What Smart clean would take but something holds (#374): in use at the scan, or its owner running. Listed unticked.
    var recommendedHeld: [Candidate] { recommendedPlan.held }
    private var recommendedPlan: RecommendedPlan {
        let running = runningOwners, names = ownerNames
        return RecommendedPlan(catalog: catalog, candidates: discovered) { item in
            names[item.id]?.first { running.contains($0) }.map(CheckRefusal.ownerRunning)
        }
    }
    /// "Up to" when part of the plan is copies that share disk blocks (SPEC section 6).
    /// The items' total size; "Up to" when part of it is copies that share disk blocks (SPEC section 6).
    func sizeText(of items: [Candidate]) -> String {
        SizeEstimate(sum: items.map(SizeEstimate.init)).text(upperBound: items.contains { catalog.rule($0.ruleID)?.estimateIsUpperBound == true })
    }
    /// Smart clean's ticked items as the last scan sees them: the recommended ones, ticked here or on any page (#349).
    var smartCleanCandidates: [Candidate] { (recommendedCandidates + recommendedHeld).filter(selections.isTicked) }
    /// Smart clean's selection checked now: the recommended plan with the full checks, minus what was unticked, plus what the
    /// page listed that the checks now refuse, for the review to explain. Nil when nothing could be checked or the scan changed meanwhile.
    /// Smart clean's items checked now, with the check that read them, so its review reuses the same snapshot of what's open
    /// instead of reading every process again (#463).
    func smartCleanCheckedNow() async -> (items: [Candidate], check: CandidateCheck)? {
        guard canEdit, let check = await currentCheck()?.snapshotted() else { return nil }
        // What the page listed stays in when the check now refuses it, so the review says why it will be skipped (#310).
        let catalog = catalog, found = discovered, selections = selections, listed = smartCleanCandidates
        let items = await Task.detached { selections.smartClean(catalog: catalog, found: found, listed: listed, check: check.check) }.value
        guard canEdit, discovered == found else { return nil }
        return (items, check)
    }

    /// Freezes the Cleanup plan's chosen candidates and checks them once so the review can show what would be refused.
    func prepareReview() async -> CatalogReview? {
        guard canReview else { return nil }
        return await prepareReview(of: selectedCandidates)
    }
    /// Freezes `candidates`, from either selection, and checks them once (#141: one review path).
    /// `snapshot` is a check taken earlier in the same click (Smart clean's); without one, the review takes its own. Reading every
    /// open process is the slowest part of a check (#463), and Clean up checks each item again when it runs.
    func prepareReview(of candidates: [Candidate], using snapshot: CandidateCheck? = nil) async -> CatalogReview? {
        guard canEdit, !candidates.isEmpty else { return nil }
        let approval = CatalogApproval(candidates: candidates, previewOnly: dryRun)
        guard let check = await snapshotOrCurrent(snapshot) else { return nil }
        let refusals = await Task.detached { check.refusals(of: approval.candidates) }.value
        return CatalogReview(approval: approval, refusals: refusals, staying: AppUninstall.staying(chosen: candidates, offered: uninstallable))
    }
    /// The review sheet's rows checked again now, after their app quit (#377): each refused row's new reason, by candidate id.
    /// Read-only: no choice changes, so the review stays open. Nil when nothing could be checked.
    func checkedAgain(_ items: [Candidate]) async -> [String: CheckRefusal]? {
        guard let check = await currentCheck()?.snapshotted() else { return nil }
        return await Task.detached { check.refusals(of: items) }.value
    }
    func execute(_ approval: CatalogApproval, cancellation: CleanupCancellation) async {
        guard !isRunning else { return }
        isRunning = true
        let reading = AppLifecycleController.shared.capacity.reading
        runCapacity = reading.flatMap { reading in
            guard let available = reading.available, let total = CapacityMeter.validTotal(available: available, total: reading.total) else { return nil }
            return (total - available, total)
        }
        runRecords = []; runProgress = CleanupRunProgress(approval: approval, catalog: catalog, records: [])
        defer { isRunning = false; executor = nil; runProgress = nil; runRecords = [] }
        guard let check = await currentCheck() else { return }
        do {
            let run = CleanupExecutor(journal: try CleanupJournalLocation.writer(), check: check, trash: TrashModel.mover, cancellation: cancellation)
            executor = run
            // Each finished item ticks its category off and shaves the bar (#355).
            let outcome = await run.execute(approval) { [weak self] progress in
                guard let record = progress.last else { return }
                await self?.progressed(record, of: approval)
                #if DEBUG
                await Self.cleanupPauseForTests()
                #endif
            }
            result = outcome
            measureStoppedWorkAgain(outcome, of: approval, run: run)
            if !approval.previewOnly { rescanFollowsCleanup = true }
            // What the run cleaned leaves every page; what it skipped keeps its tick (#349). Picked folders keep the large and old files this run didn't act on (#125).
            // The other rows stay, dimmed, until the rescan that follows replaces them (#375).
            selections.finishRun(cleaned: outcome.cleanedCandidateIDs); selections.revise()
            discovered = outcome.keptDuringRescan(discovered); uninstallable = outcome.keptDuringRescan(uninstallable); pickedFiles = pickedFiles.mapValues { UserFiles.remaining($0, after: outcome) }
            projectBuilds = projectBuilds.mapValues { UserFiles.remaining($0, after: outcome) }; noteChoices()
        } catch { message = "CacheDrop couldn’t open its cleanup history, so nothing was changed." }
    }
    /// A stopped daemon-backed tool's work may still be finishing, so its item is measured again a minute later, and
    /// once more at about 5 minutes if it was still shrinking, as the scan measures it; the journal records what went
    /// (#190, #209). After a completed Docker prune, the disk's free space is read again a minute later, since Docker hands
    /// space back to macOS after it returns (#411). Results show each finding if they are still open.
    private func measureStoppedWorkAgain(_ outcome: CatalogExecutionResult, of approval: CatalogApproval, run: CleanupExecutor) {
        guard run.measuresLater(outcome), let home = Self.home else { return }
        let catalog = catalog, userFolder = Self.userFolder, locate = Self.locateTool, system = Self.systemRoot, cloud = Self.cloud
        if run.settles(outcome) { settleCheck = (outcome.batchID, false) }
        var wait = CleanupExecutor.sleeping
        #if DEBUG
        if let seconds = Self.laterWaitForTests() { wait = { _ in (try? await Task.sleep(for: .seconds(seconds))) != nil } }
        #endif
        Task {
            defer { if settleCheck?.batchID == outcome.batchID { settleCheck?.finished = true } }
            let later = await run.measureAgainLater(outcome, of: approval, wait: wait, update: { [weak self] partial in await self?.showLaterMeasurement(partial) }) { candidates in
                // Without the exclusions the scan used, nothing is measured: every item stays unmeasured.
                guard let exclusions = try? await ExclusionsModel.shared.policyForScan() else { return [:] }
                return await Task.detached(priority: .utility) {
                    let only = catalog.only(candidates)
                    return catalog.measuredAgain(candidates, in: only.discovery(home: home, userFolder: userFolder, exclusions: exclusions, locateTool: locate,
                                                                                  systemRoot: system, cloud: cloud))
                }.value
            }
            showLaterMeasurement(later)
        }
    }
    private func progressed(_ record: CleanupRecord, of approval: CatalogApproval) {
        guard runProgress != nil else { return }
        runRecords.append(record)
        runProgress = CleanupRunProgress(approval: approval, catalog: catalog, records: runRecords)
    }
    private func showLaterMeasurement(_ later: CatalogExecutionResult) {
        if result?.batchID == later.batchID { result = later }
    }
    func cancel() { executor?.cancel() }
    /// Leaves a finished run's results without starting a new plan: the selection is kept.
    func dismissResult() {
        guard !isRunning else { return }
        result = nil; message = nil
    }
    func endSession() {
        guard !isRunning else { return }
        // A new plan starts the plan over at the recommended default and keeps the Applications page's choices (#270, #349).
        selections.clear(.plan); pickedFiles = [:]; projectBuilds = [:]; result = nil; message = nil; noteChoices()
    }
    private func snapshotOrCurrent(_ snapshot: CandidateCheck?) async -> CandidateCheck? {
        if let snapshot { return snapshot }
        return await currentCheck()?.snapshotted()
    }
    private func currentCheck() async -> CandidateCheck? {
        do { return CandidateCheck(catalog: catalog, running: SystemRunningAppChecker(), exclusions: try await ExclusionsModel.shared.policyForScan(), cloud: Self.cloud,
                                    home: Self.checkHome, apps: Self.appPresence, systemRoot: Self.systemRoot) }
        catch { settingsUnreadable = true; return nil }
    }
}

/// A frozen approval plus what the checks found at review time.
struct CatalogReview {
    let approval: CatalogApproval
    let refusals: [String: CheckRefusal]
    /// What an uninstall leaves and why (#177).
    var staying: [AppUninstall.Staying] = []
}

extension CatalogCategory {
    var storageCategory: StorageCategory {
        switch self {
        case .developer: .developer
        case .icloud: .cloud
        case .browser: .browser
        case .downloads: .downloads
        case .files: .files
        case .system: .appCaches
        case .models: .models
        case .updaters: .appUpdates
        case .logs: .logs
        case .managed: .managed
        case .leftovers: .leftovers
        case .apps: .apps
        }
    }
    /// Overview's row title for a category; the rows themselves come from what the catalog found.
    var overviewTitle: String {
        switch self {
        case .developer: "Developer caches and build files"
        case .browser: "Browser caches"
        case .downloads: "Downloads"
        case .system: "App caches"
        case .models: "Models and disk images"
        case .updaters: "App update downloads"
        case .logs: "Logs and crash reports"
        case .icloud: "Downloaded iCloud files"
        case .files: "Large and old files"
        case .managed: "App-managed storage"
        case .leftovers: "Files from deleted apps"
        case .apps: "Apps, plug-ins and their files"
        }
    }
    /// Smart clean's title: it takes only downloads untouched for 7 days (#342), so it says so.
    var smartCleanTitle: String { self == .downloads ? "Old downloads" : overviewTitle }
    /// The one short line under a category's title on Overview and in the plan, written per category rather than built from rule names.
    var overviewDetail: String {
        switch self {
        case .developer: "Package caches and build files that tools rebuild"
        case .browser: "Cached pages and images browsers fetch again"
        case .downloads: "Every file in your Downloads folder, to review"
        case .system: "Caches apps rebuild when they need them"
        case .models: "AI models and disk images you can download again"
        case .updaters: "Updates apps downloaded and kept"
        case .logs: "Logs and crash reports apps wrote"
        case .icloud: "Local copies of files that stay in iCloud"
        case .files: "Files of 500 MB or more, or not opened in 90 days"
        case .managed: "Data the apps that own it look after"
        case .leftovers: "Settings and data they left behind"
        case .apps: "Installed apps you chose to uninstall"
        }
    }
}

extension CatalogOverview.Row {
    /// The row's size; "Up to" when part of it is copies that share disk blocks.
    var valueText: String { estimate.text(upperBound: rules.contains(where: \.estimateIsUpperBound)) }
}

extension CleanupRule {
    /// Whether every item the rule offers is a single file.
    var offersFiles: Bool { contents != nil || id == UserFiles.ruleID }
    /// The plan shows its items one row per project (#157).
    var groupsByProject: Bool { id == ProjectBuilds.ruleID }
}

extension Candidate {
    /// The name the plan shows, e.g. a model's name rather than its folder or manifest.
    var displayName: String { itemName ?? url.lastPathComponent }
    /// The row the plan groups the item under: the app it belongs to, or its browser profile.
    var group: String? { appName ?? profile }
}

/// One step the background scan reports: discovery's progress, or a later phase (#308).
enum CatalogScanStep: Sendable {
    case discovery(CatalogDiscoveryProgress)
    case phase(CatalogScanPhase)
}

/// How far the catalog scan is: its phase (during discovery, the location being checked and its number), and what the
/// finished locations found.
struct CatalogScanProgress {
    var phase = CatalogScanPhase.starting
    var finished = 0
    var found: [Candidate] = []
    mutating func apply(_ step: CatalogScanStep) {
        switch step {
        case .discovery(.checking(_, let title, let number, let total)): phase = .location(title: title, number: number, total: total)
        case .discovery(.finished(_, let number, _, let found)): finished = number; self.found += found
        case .phase(let next): phase = next
        }
    }
}

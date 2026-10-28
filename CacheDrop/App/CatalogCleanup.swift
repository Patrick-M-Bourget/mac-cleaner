import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// The catalog's categories in the app. Nothing here knows a specific rule; rules are data in CacheDropCore.
@MainActor @Observable final class CatalogCleanupModel {
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    /// What the catalog's known locations hold.
    private(set) var discovered: [Candidate] = [] { didSet { indexPickedFiles() } }
    /// Large and old files in each folder the user picked and scanned, keyed by that folder (`UserFiles`).
    private(set) var pickedFiles: [URL: [Candidate]] = [:] { didSet { indexPickedFiles() } }
    /// The picked folders' files the plan offers, by "dev:ino". A file a catalog rule already offers is left to that rule.
    private(set) var pickedByResource: [String: Candidate] = [:]
    /// Build folders in projects inside each folder the user picked and scanned, keyed by that folder (`ProjectBuilds`, #157).
    private(set) var projectBuilds: [URL: [Candidate]] = [:]
    /// The picked folders' build folders, once each, unless a catalog rule already offers one.
    var projectBuildCandidates: [Candidate] {
        var seen = Set(discovered.map(\.resourceID))
        return projectBuilds.keys.sorted { $0.path < $1.path }.flatMap { projectBuilds[$0] ?? [] }.filter { seen.insert($0.resourceID).inserted }
    }
    /// Installed apps with their files, offered on the Applications page to uninstall (#177); never on Overview or in the plan.
    private(set) var uninstallable: [Candidate] = []
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
    private(set) var hasScanned = false
    /// The running catalog scan's progress, one location at a time (#128); nil when no scan is running.
    private(set) var scanProgress: CatalogScanProgress?
    /// Watches for Full Disk Access being granted while CacheDrop was away (#124, `rescanIfFullDiskAccessGranted`).
    var fullDiskAccessRescan = FullDiskAccessRescan()
    /// The Cleanup plan's selection and Smart clean's, kept apart (#141).
    private(set) var selections = CleanupSelections()
    /// The Cleanup plan's chosen candidate ids. Nothing is preselected (Decision 28).
    private(set) var selectedIDs: Set<String> { get { selections.ticked } set { selections.ticked = newValue } }
    /// Moves on only when a page's chosen items change, or the dry run does, so an open review sheet stays open while
    /// background work ends (#307).
    var selectionRevision: UInt64 { selections.revision }
    /// Notes each page's choices after a change; the revision moves only if they differ.
    private func noteChoices() { selections.noteChoices(among: candidates, smartClean: smartCleanCandidates) }
    private(set) var isRunning = false
    /// A cleanup changed files since the last catalog scan, so the next one is recorded as a post-cleanup rescan (#126).
    private var rescanFollowsCleanup = false
    private(set) var result: CatalogExecutionResult?
    private(set) var message: String?
    /// Why a rule kept items back, such as copies whose use couldn't be checked.
    private(set) var notes: [CatalogNote] = []
    /// Guidance-only categories found at the last scan. Never candidates, never in a plan. Set only by the guidance
    /// scan (`CatalogCleanupModel+Guidance.swift`), which lives in its own file and so can't use a private setter.
    var guidance: [GuidanceFinding] = []
    var guidanceStatus: String?
    /// Rules whose owner keeps its data elsewhere by a setting; they offer nothing.
    private(set) var overriddenRules: [CleanupRule] = []
    /// Rules CacheDrop can't read without Full Disk Access (Safari's cache): shown as not accessible, never as 0.
    private(set) var notAccessibleRules: [CleanupRule] = []
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

    /// Which apps are installed, for leftovers of removed apps (#173). A debug test run never asks Spotlight or Launch Services:
    /// only the bundle IDs listed in `<home>/.cachedrop-test-installed-apps`, one per line, are installed.
    static var appPresence: any AppPresence {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureAppPresence(home: home) }
        #endif
        return SystemAppPresence()
    }
    /// Installer receipts; a debug test run reads none.
    static func receipts(home: URL) -> any InstallerReceiptReading {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureAppPresence(home: home) }
        #endif
        return SystemInstallerReceipts(home: home)
    }

    /// Overview's summary. While the first scan runs it covers the locations finished so far, so rows and the total fill in
    /// as each one completes (#128); nil until the first one has.
    var overview: CatalogOverview? {
        if hasScanned { return CatalogOverview(catalog: catalog, candidates: discovered) }
        return scanProgress.flatMap { $0.finished > 0 ? CatalogOverview(catalog: catalog, candidates: $0.found) : nil }
    }
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
        if LocalStateLocation.isDisposableTest { return SystemAppQuitter(sendsRequests: false) }
        #endif
        return SystemAppQuitter()
    }

    /// Plug-in products to uninstall (#176): their formats, own support files and shared items, never what is `offered` elsewhere.
    nonisolated private static func plugIns(home: URL, system: URL, installed: [InstalledApp], offered: [Candidate],
                                            exclusions: ExclusionPolicy) -> (PlugInInventory, [Candidate]) {
        let inventory = PlugInInventory.scan(home: home, systemRoot: system)
        let owners = ApplicationsInventory.plugIns(inventory).map { ContentOwner($0) } + installed.map { ContentOwner($0) }
        let content = MusicContent.scan(owners: owners, home: home, systemRoot: system).items
        return (inventory, PlugInUninstall.scan(inventory, apps: installed, receipts: ReceiptListings.read(under: system), content: content, systemRoot: system, offered: offered, exclusions: exclusions))
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

    var rulesFound: [CleanupRule] { catalog.rules.filter { rule in candidates.contains { $0.ruleID == rule.id } } }
    func candidates(for rule: CleanupRule) -> [Candidate] { candidates.filter { $0.ruleID == rule.id } }
    func estimatedBytes(for rule: CleanupRule) -> Int64 { candidates(for: rule).reduce(0) { $0 + $1.estimatedBytes } }
    func sizeComplete(for rule: CleanupRule) -> Bool { candidates(for: rule).allSatisfy(\.sizeComplete) }
    func sizeIsEstimate(for rule: CleanupRule) -> Bool { candidates(for: rule).contains(where: \.sizeIsEstimate) }
    /// The Cleanup plan's chosen items; leftovers of removed apps are chosen on the Applications page (Decision 51).
    var selectedCandidates: [Candidate] { selections.chosen(on: .plan, from: candidates) }
    /// Whether the plan or the Applications page has chosen items: what quitting would lose (#270).
    var hasAnyChoices: Bool { selections.hasChoices(among: candidates) }
    /// The Applications page's chosen items.
    var applicationsSelected: [Candidate] { selections.chosen(on: .applications, from: candidates) }
    /// Rules with at least one chosen item.
    var selectedRuleCount: Int { Set(selectedCandidates.map(\.ruleID)).count }
    var selectedCount: Int { selectedCandidates.count }
    var estimatedBytes: Int64 { selectedCandidates.reduce(0) { $0 + $1.estimatedBytes } }
    /// The chosen items that go to Trash and their size; nil when none do.
    var selectedTrashBytes: Int64? {
        let trash = selectedCandidates.filter { $0.action == .trash }
        return trash.isEmpty ? nil : trash.reduce(0) { $0 + $1.estimatedBytes }
    }
    var canEdit: Bool { !isScanning && !isRunning && !AppLifecycleController.shared.operationInProgress && !AppLifecycleController.shared.maintenanceInProgress }
    var canReview: Bool { canEdit && selectedCount > 0 }
    func isSelected(_ rule: CleanupRule) -> Bool { candidates(for: rule).contains { selectedIDs.contains($0.id) } }
    func isSelected(_ candidate: Candidate) -> Bool { selectedIDs.contains(candidate.id) }
    /// The plan's categories, grouped as Overview groups them, picked folders' files included. Leftovers of removed apps
    /// are on the Applications page instead (Decision 51).
    var planCategories: [CatalogOverview.Row] { CatalogOverview(catalog: catalog, candidates: candidates).rows.filter { CleanupSelections.Source.page(of: $0) == .plan } }
    /// The Applications page's Leftovers row; nil when none were found.
    var leftoversRow: CatalogOverview.Row? { CatalogOverview(catalog: catalog, candidates: candidates).rows.first { $0.category == .leftovers } }
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
    private func categorySelection(_ rules: [CleanupRule]) -> CategorySelection {
        CategorySelection(rules: rules, candidates: rules.flatMap(candidates(for:)), selected: selectedIDs)
    }
    /// The category's checkbox (#240): chooses what may be chosen together or clears every chosen item. Returns true when
    /// nothing may be chosen together and nothing is chosen, so the category lists its items to choose one by one.
    func toggleCategory(_ rules: [CleanupRule]) -> Bool { toggle(categorySelection(rules)) }
    private func toggle(_ selection: CategorySelection) -> Bool {
        guard canEdit else { return false }
        switch selection.toggle {
        case .choose(let ids): selectedIDs.formUnion(ids)
        case .clear(let ids): selectedIDs.subtract(ids)
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
        if await scan() { scanRememberedFolders?() }
    }
    /// Read-only sizing of the catalog's known locations. False when it couldn't start: a scan or a cleanup is running.
    @discardableResult func scan() async -> Bool {
        guard canEdit else { return false }
        await scanCatalog()
        // Something changed on disk while it ran, such as a Put back: scan again, as its own rescan.
        if rescanPending { rescanPending = false; Task { await rescan() } }
        return true
    }
    private func scanCatalog() async {
        isScanning = true; message = nil; scanProgress = CatalogScanProgress()
        defer { isScanning = false; hasScanned = true; scanProgress = nil }
        guard let home = Self.home else { discovered = []; uninstallable = []; notes = []; overriddenRules = []; notAccessibleRules = []; setRunning([:], open: []); ownerNames = [:]; return }
        // Excluded items are never offered (SPEC section 2); without the settings nothing can be offered safely.
        guard let exclusions = try? await ExclusionsModel.shared.policyForScan() else {
            discovered = []; uninstallable = []; notes = []; overriddenRules = []; notAccessibleRules = []; setRunning([:], open: []); ownerNames = [:]
            message = "Exclusion settings are unavailable, so nothing can be checked. Try again."; return
        }
        let catalog = catalog
        let locate = Self.locateTool, system = Self.systemRoot
        let userFolder = Self.userFolder, cloud = Self.cloud
        // What grew records each completed catalog scan (#119).
        let growth = await GrowthHistoryModel.shared.beginCatalog(home: home, exclusionFingerprint: exclusions.fingerprint)
        let quitter = Self.quitter
        // Discovery reports each location as it goes; the steps reach the main actor in order (#128).
        // After discovery, each later phase is named too (#308).
        let (steps, reporter) = AsyncStream.makeStream(of: CatalogScanStep.self)
        let progress = Task { for await step in steps { scanProgress?.apply(step) } }
        let presence = Self.appPresence.snapshot(), receipts = Self.receipts(home: home), own = Bundle.main.bundleIdentifier
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
            // Leftovers of removed apps (#173), except what a catalog rule already offers, holds or sits inside.
            let found = RemovedAppLeftovers.scan(home: home, apps: presence, receipts: receipts, exclusions: exclusions)
            let leftovers = RemovedAppLeftovers.notOffered(by: discovered.candidates, found)
            // Installed apps with their files (#177), each read once; receipts are read once for all of them.
            enter(.appsAndPlugIns)
            let readReceipts = ReadReceipts(receipts.receipts())
            let apps = ApplicationsInventory.withUninstallers(presence.installedApps() ?? [], excluding: own, home: home).flatMap { app, uninstaller in
                AppUninstall.scan(app, uninstaller: uninstaller, excluding: own, home: home, apps: presence, receipts: readReceipts, leftovers: found, offered: discovered.candidates,
                                  exclusions: exclusions)
            }
            // Plug-in products (#176): their formats, own support files and shared items, never what is offered above.
            let (inventory, plugIns) = Self.plugIns(home: home, system: system, installed: presence.installedApps() ?? [], offered: discovered.candidates + found + apps,
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
                                     ownerNames: names, access: access, leftovers: leftovers, uninstallable: apps + plugIns, plugIns: inventory)
        }.value
        await progress.value
        scanProgress?.phase = .storageTrends
        await GrowthHistoryModel.shared.completeCatalog(scanned.discovery, catalog: catalog, fullDiskAccess: scanned.access, token: growth, afterCleanup: rescanFollowsCleanup)
        rescanFollowsCleanup = false
        fullDiskAccessRescan.scanned(scanned.access)
        discovered = scanned.discovery.candidates + scanned.leftovers; uninstallable = scanned.uninstallable; plugInInventory = scanned.plugIns
        notes = scanned.discovery.notes; notAccessibleRules = scanned.discovery.notAccessible; overriddenRules = scanned.overriddenRules
        setRunning(scanned.owners, open: scanned.openOwners); ownerNames = scanned.ownerNames
        keepOnlyCurrentChoices()
        scanProgress?.phase = .appManagedStorage
        await scanGuidance(home: home, fullDiskAccess: scanned.access)
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
        /// Leftovers of removed apps (#173).
        let leftovers: [Candidate]
        /// Installed apps' and plug-in products' items (#177, #176).
        let uninstallable: [Candidate]
        let plugIns: PlugInInventory
    }
    #if DEBUG
    /// A disposable test run can slow discovery down (`CACHEDROP_TEST_DISCOVERY_PAUSE`, seconds after each location), so a UI journey sees
    /// Overview fill in while the fixture scan runs. Never set outside tests.
    nonisolated private static func pauseForTests() {
        guard LocalStateLocation.isDisposableTest, let pause = ProcessInfo.processInfo.environment["CACHEDROP_TEST_DISCOVERY_PAUSE"].flatMap(Double.init), pause > 0 else { return }
        Thread.sleep(forTimeInterval: min(pause, 2))
    }
    #endif
    /// Drops chosen items that are no longer offered, and says so. The revision moves only when a page's choices changed (#307).
    private func keepOnlyCurrentChoices() {
        if selections.keepOnly(candidates, smartClean: smartCleanCandidates) { message = "Some items changed or are no longer on this Mac and were removed from your plan." }
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
    /// Chooses or clears every item the rule found.
    func setSelected(_ rule: CleanupRule, _ selected: Bool) { setSelected([rule], selected) }
    /// Chooses or clears every item the rules found, such as a whole category. Items chosen one by one (possibly related
    /// leftovers, #173) are never chosen with them.
    func setSelected(_ rules: [CleanupRule], _ selected: Bool) {
        let ids = rules.filter { !$0.selectedOneByOne }.flatMap(candidates(for:)).map(\.id)
        guard canEdit, !ids.isEmpty else { return }
        if selected { selectedIDs.formUnion(ids) } else { selectedIDs.subtract(ids) }
        noteChoices()
    }
    func setSelected(_ candidate: Candidate, _ selected: Bool) {
        guard canEdit, candidates.contains(candidate) else { return }
        if selected { selectedIDs.insert(candidate.id) } else { selectedIDs.remove(candidate.id) }
        noteChoices()
    }

    /// The recommended plan as the last scan sees it (`RecommendedPlan`): owners running at the scan are left out.
    /// The full checks run when it is chosen, and again in the review.
    var recommendedCandidates: [Candidate] {
        let running = runningOwners, names = ownerNames
        return RecommendedPlan(catalog: catalog, candidates: discovered) { item in
            names[item.id]?.first { running.contains($0) }.map(CheckRefusal.ownerRunning)
        }.candidates
    }
    /// "Up to" when part of the plan is copies that share disk blocks (SPEC section 6).
    var recommendedSizeText: String {
        let items = recommendedCandidates
        return SizeEstimate(sum: items.map(SizeEstimate.init)).text(upperBound: items.contains { catalog.rule($0.ruleID)?.estimateIsUpperBound == true })
    }
    /// Smart clean's ticked items as the last scan sees them; the Cleanup plan's selection never changes them (#141).
    var smartCleanCandidates: [Candidate] { recommendedCandidates.filter(selections.isInSmartClean) }
    func isInSmartClean(_ candidate: Candidate) -> Bool { selections.isInSmartClean(candidate) }
    func setSmartClean(_ items: [Candidate], _ included: Bool) {
        guard canEdit, !items.isEmpty else { return }
        selections.setSmartClean(items, included: included); noteChoices()
    }
    /// Smart clean's selection checked now: the recommended plan with the full checks, minus what was unticked.
    /// Nil when nothing could be checked or the scan changed meanwhile. Never touches the Cleanup plan's selection.
    func smartCleanCheckedNow() async -> [Candidate]? {
        guard canEdit, let check = await currentCheck()?.snapshotted() else { return nil }
        let catalog = catalog, found = discovered, selections = selections
        let items = await Task.detached { selections.smartClean(catalog: catalog, found: found, check: check.check) }.value
        guard canEdit, discovered == found else { return nil }
        return items
    }

    /// Freezes the Cleanup plan's chosen candidates and checks them once so the review can show what would be refused.
    func prepareReview() async -> CatalogReview? {
        guard canReview else { return nil }
        return await prepareReview(of: selectedCandidates)
    }
    /// Freezes `candidates`, from either selection, and checks them once (#141: one review path).
    func prepareReview(of candidates: [Candidate]) async -> CatalogReview? {
        guard canEdit, !candidates.isEmpty else { return nil }
        let approval = CatalogApproval(candidates: candidates, previewOnly: dryRun)
        guard let check = await currentCheck()?.snapshotted() else { return nil }
        let refusals = await Task.detached { Dictionary(uniqueKeysWithValues: approval.candidates.compactMap { c in check.check(c).map { (c.id, $0) } }) }.value
        return CatalogReview(approval: approval, refusals: refusals, staying: AppUninstall.staying(chosen: candidates, offered: uninstallable))
    }
    func execute(_ approval: CatalogApproval, from source: CleanupSelections.Source, cancellation: CleanupCancellation) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false; executor = nil }
        guard let check = await currentCheck() else { return }
        do {
            let run = CleanupExecutor(journal: try CleanupJournalLocation.writer(), check: check, trash: TrashModel.mover, cancellation: cancellation)
            executor = run
            let outcome = await run.execute(approval)
            result = outcome
            measureStoppedWorkAgain(outcome, of: approval, run: run)
            if !approval.previewOnly { rescanFollowsCleanup = true }
            // Picked folders keep the large and old files this run didn't act on (#125).
            selections.finishRun(from: source); discovered = []; uninstallable = []; pickedFiles = pickedFiles.mapValues { UserFiles.remaining($0, after: outcome) }
            projectBuilds = projectBuilds.mapValues { UserFiles.remaining($0, after: outcome) }; hasScanned = false; noteChoices()
        } catch { message = "The cleanup journal is unavailable. Nothing was changed." }
    }
    /// A stopped daemon-backed tool's work may still be finishing, so its item is measured again a minute later, and
    /// once more at about 5 minutes if it was still shrinking, as the scan measures it; the journal records what went
    /// (#190, #209). Results show each finding if they are still open.
    private func measureStoppedWorkAgain(_ outcome: CatalogExecutionResult, of approval: CatalogApproval, run: CleanupExecutor) {
        guard outcome.records.contains(where: { $0.mayStillBeFinishing == true }), let home = Self.home else { return }
        let catalog = catalog, userFolder = Self.userFolder, locate = Self.locateTool, system = Self.systemRoot, cloud = Self.cloud
        Task {
            let later = await run.measureAgainLater(outcome, of: approval, update: { [weak self] partial in await self?.showLaterMeasurement(partial) }) { candidates in
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
    private func showLaterMeasurement(_ later: CatalogExecutionResult) {
        if result?.batchID == later.batchID { result = later }
    }
    func cancel() { executor?.cancel() }
    /// Leaves a finished run's results without starting a new plan: both selections are kept.
    func dismissResult() {
        guard !isRunning else { return }
        result = nil; message = nil
    }
    func endSession() {
        guard !isRunning else { return }
        // A new plan keeps the Applications page's choices (#270).
        selections.clear(.plan); pickedFiles = [:]; projectBuilds = [:]; result = nil; message = nil; noteChoices()
    }
    private func currentCheck() async -> CandidateCheck? {
        do { return CandidateCheck(catalog: catalog, running: SystemRunningAppChecker(), exclusions: try await ExclusionsModel.shared.policyForScan(), cloud: Self.cloud,
                                    home: Self.checkHome, apps: Self.appPresence, systemRoot: Self.systemRoot) }
        catch { message = "Exclusion settings are unavailable, so nothing can be checked. Try again."; return nil }
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
        case .downloads: "Downloads to review"
        case .system: "App caches"
        case .models: "Models and disk images"
        case .updaters: "App update downloads"
        case .logs: "Logs and crash reports"
        case .icloud: "Downloaded iCloud files"
        case .files: "Large and old files"
        case .managed: "App-managed storage"
        case .leftovers: "Leftovers of removed apps"
        case .apps: "Apps, plug-ins and their files"
        }
    }
    /// The one short line under a category's title on Overview and in the plan, written per category rather than built from rule names.
    var overviewDetail: String {
        switch self {
        case .developer: "Package caches and build files that tools rebuild"
        case .browser: "Cached pages and images browsers fetch again"
        case .downloads: "Installers and large files you haven’t opened lately"
        case .system: "Caches apps rebuild when they need them"
        case .models: "AI models and disk images you can download again"
        case .updaters: "Updates apps downloaded and kept"
        case .logs: "Logs and crash reports apps wrote"
        case .icloud: "Local copies of files that stay in iCloud"
        case .files: "Large files you haven’t opened in a while"
        case .managed: "Data the apps that own it look after"
        case .leftovers: "Files apps you removed left behind"
        case .apps: "Installed apps you chose to uninstall"
        }
    }
}

extension SizeEstimate {
    /// Unknown stays unknown, never 0 (SPEC section 1).
    var text: String {
        switch self {
        case .measured(let bytes): catalogBytes(bytes)
        case .atLeast(let bytes): catalogBytes(bytes, complete: false)
        case .about(let bytes): catalogBytes(bytes, estimate: true)
        case .unknown: "Unknown"
        }
    }
}

extension SizeEstimate {
    /// "Up to" when part of it is copies that share disk blocks (SPEC section 6).
    func text(upperBound: Bool) -> String {
        if upperBound, case .measured(let bytes) = self { return catalogBytes(bytes, upperBound: true) }
        return text
    }
}

extension CatalogOverview.Row {
    /// The row's size; "Up to" when part of it is copies that share disk blocks.
    var valueText: String { estimate.text(upperBound: rules.contains(where: \.estimateIsUpperBound)) }
}

/// A size as text. An incomplete size of 0 is unknown, as in `SizeEstimate`.
/// `upperBound` is for copies that share disk blocks (SPEC section 6): less may come back. An estimate reads "About".
func catalogBytes(_ value: Int64, complete: Bool = true, upperBound: Bool = false, estimate: Bool = false) -> String {
    if !complete && value == 0 { return SizeEstimate.unknown.text }
    return (!complete ? "At least " : upperBound ? "Up to " : estimate ? "About " : "") + ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
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

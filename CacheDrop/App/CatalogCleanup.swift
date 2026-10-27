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
    /// Everything the plan can offer.
    var candidates: [Candidate] { discovered + pickedCandidates + projectBuildCandidates }
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
    private(set) var selectedIDs: Set<String> { get { selections.plan } set { selections.plan = newValue } }
    private(set) var selectionRevision: UInt64 = 0
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
    private var ownerNames: [String: String] = [:]
    private var executor: CleanupExecutor?
    private static let dryRunKey = PreferenceKeys.dryRun
    /// The Settings dry run, off by default: with it on, the whole flow runs and nothing changes on disk (Decision 27).
    var dryRun: Bool {
        didSet {
            selectionRevision &+= 1
            if !LocalStateLocation.isDisposableTest { UserDefaults.standard.set(dryRun, forKey: Self.dryRunKey) }
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
        dryRun = UserDefaults.standard.bool(forKey: Self.dryRunKey)
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

    /// Overview's summary. While the first scan runs it covers the locations finished so far, so rows and the total fill in
    /// as each one completes (#128); nil until the first one has.
    var overview: CatalogOverview? {
        if hasScanned { return CatalogOverview(catalog: catalog, candidates: discovered) }
        return scanProgress.flatMap { $0.finished > 0 ? CatalogOverview(catalog: catalog, candidates: $0.found) : nil }
    }
    /// "Checking Xcode DerivedData… 4 of 31": one quiet line while the catalog scan runs (Decision 25).
    var scanProgressText: String {
        guard let progress = scanProgress, progress.total > 0 else { return "Checking known locations…" }
        return "Checking \(progress.title)… \(progress.number) of \(progress.total)"
    }
    /// Owners of the rule's items that were running at the last scan, in name order.
    func runningOwnerNames(for rule: CleanupRule) -> [String] {
        Set(candidates(for: rule).compactMap { ownerNames[$0.id] }).intersection(runningOwners).sorted()
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

    /// Which owners are running, and which of them as an open app.
    nonisolated private static func running(_ owners: [String: RuleOwner], quitter: any AppQuitting) -> ([String: RuleOwner], Set<String>) {
        let checker = SystemRunningAppChecker()
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
    var selectedCandidates: [Candidate] { candidates.filter { selectedIDs.contains($0.id) } }
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
    /// The plan's categories, grouped as Overview groups them, picked folders' files included.
    var planCategories: [CatalogOverview.Row] { CatalogOverview(catalog: catalog, candidates: candidates).rows }
    func selectionState(for rules: [CleanupRule]) -> CategorySelectionState {
        let items = rules.flatMap(candidates(for:)), chosen = items.filter { selectedIDs.contains($0.id) }.count
        return chosen == 0 ? .unchecked : chosen == items.count ? .checked : .mixed
    }

    /// Rescans the remembered, included folders. Set by the workspace; called after each scan `scanIfNeeded` starts,
    /// at launch and after a cleanup, so those folders are scanned along with the catalog (#125).
    var scanRememberedFolders: (() -> Void)?
    func scanIfNeeded() async { if !hasScanned { await scan(); scanRememberedFolders?() } }
    /// Read-only sizing of the catalog's known locations.
    func scan() async {
        guard canEdit else { return }
        isScanning = true; message = nil; scanProgress = CatalogScanProgress()
        defer { isScanning = false; hasScanned = true; scanProgress = nil }
        guard let home = Self.home else { discovered = []; notes = []; overriddenRules = []; notAccessibleRules = []; setRunning([:], open: []); ownerNames = [:]; return }
        // Excluded items are never offered (SPEC section 2); without the settings nothing can be offered safely.
        guard let exclusions = try? await ExclusionsModel.shared.policyForScan() else {
            discovered = []; notes = []; overriddenRules = []; notAccessibleRules = []; setRunning([:], open: []); ownerNames = [:]
            message = "Exclusion settings are unavailable, so nothing can be checked. Try again."; return
        }
        let catalog = catalog
        let locate = Self.locateTool, system = Self.systemRoot
        let userFolder = Self.userFolder, cloud = Self.cloud
        // What grew records each completed catalog scan (#119).
        let growth = await GrowthHistoryModel.shared.beginCatalog(home: home, exclusionFingerprint: exclusions.fingerprint)
        let quitter = Self.quitter
        // Discovery reports each location as it goes; the steps reach the main actor in order (#128).
        let (steps, reporter) = AsyncStream.makeStream(of: CatalogDiscoveryProgress.self)
        let progress = Task { for await step in steps { scanProgress?.apply(step) } }
        let scanned = await Task.detached(priority: .userInitiated) { () -> (CatalogDiscovery, [CleanupRule], ([String: RuleOwner], Set<String>), [String: String], FullDiskAccessStatus) in
            // Probed once per scan, at launch too, and shared with the guidance scan: it only opens a protected folder
            // and never prompts (#117).
            let access = FullDiskAccessProbe(home: home).status()
            let discovered = catalog.discovery(home: home, userFolder: userFolder, exclusions: exclusions, locateTool: locate, systemRoot: system, cloud: cloud,
                                               access: access, progress: { step in
                                                   reporter.yield(step)
                                                   #if DEBUG
                                                   if case .finished = step { Self.pauseForTests() }
                                                   #endif
                                               })
            reporter.finish()
            var owners: [String: RuleOwner] = [:], names: [String: String] = [:]
            for candidate in discovered.candidates { if let owner = catalog.owner(for: candidate) { owners[owner.name] = owner; names[candidate.id] = owner.name } }
            return (discovered, catalog.overriddenRules(home: home, systemRoot: system), Self.running(owners, quitter: quitter), names, access)
        }.value
        await progress.value
        await GrowthHistoryModel.shared.completeCatalog(scanned.0, catalog: catalog, fullDiskAccess: scanned.4, token: growth, afterCleanup: rescanFollowsCleanup)
        rescanFollowsCleanup = false
        fullDiskAccessRescan.scanned(scanned.4)
        discovered = scanned.0.candidates; notes = scanned.0.notes; notAccessibleRules = scanned.0.notAccessible; overriddenRules = scanned.1; setRunning(scanned.2.0, open: scanned.2.1); ownerNames = scanned.3
        keepOnlyCurrentChoices()
        await scanGuidance(home: home, fullDiskAccess: scanned.4)
    }
    #if DEBUG
    /// A disposable test run can slow discovery down (`CACHEDROP_TEST_DISCOVERY_PAUSE`, seconds after each location), so a UI journey sees
    /// Overview fill in while the fixture scan runs. Never set outside tests.
    nonisolated private static func pauseForTests() {
        guard LocalStateLocation.isDisposableTest, let pause = ProcessInfo.processInfo.environment["CACHEDROP_TEST_DISCOVERY_PAUSE"].flatMap(Double.init), pause > 0 else { return }
        Thread.sleep(forTimeInterval: min(pause, 2))
    }
    #endif
    /// Drops chosen items that are no longer offered, and says so.
    private func keepOnlyCurrentChoices() {
        let found = Set(candidates.map(\.id))
        if !selectedIDs.isSubset(of: found) { selectedIDs.formIntersection(found); message = "Some items changed or are no longer on this Mac and were removed from your plan." }
        selectionRevision &+= 1
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
    /// Chooses or clears every item the rules found, such as a whole category.
    func setSelected(_ rules: [CleanupRule], _ selected: Bool) {
        let ids = rules.flatMap(candidates(for:)).map(\.id)
        guard canEdit, !ids.isEmpty else { return }
        if selected { selectedIDs.formUnion(ids) } else { selectedIDs.subtract(ids) }
        selectionRevision &+= 1
    }
    func setSelected(_ candidate: Candidate, _ selected: Bool) {
        guard canEdit, candidates.contains(candidate) else { return }
        if selected { selectedIDs.insert(candidate.id) } else { selectedIDs.remove(candidate.id) }
        selectionRevision &+= 1
    }

    /// The recommended plan as the last scan sees it (`RecommendedPlan`): owners running at the scan are left out.
    /// The full checks run when it is chosen, and again in the review.
    var recommendedCandidates: [Candidate] {
        let running = runningOwners, names = ownerNames
        return RecommendedPlan(catalog: catalog, candidates: discovered) { item in
            names[item.id].flatMap { running.contains($0) ? .ownerRunning($0) : nil }
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
        selections.setSmartClean(items, included: included); selectionRevision &+= 1
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
        return CatalogReview(approval: approval, refusals: refusals)
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
            if !approval.previewOnly { rescanFollowsCleanup = true }
            // Picked folders keep the large and old files this run didn't act on (#125).
            selections.finishRun(from: source); discovered = []; pickedFiles = pickedFiles.mapValues { UserFiles.remaining($0, after: outcome) }
            projectBuilds = projectBuilds.mapValues { UserFiles.remaining($0, after: outcome) }; hasScanned = false; selectionRevision &+= 1
        } catch { message = "The cleanup journal is unavailable. Nothing was changed." }
    }
    func cancel() { executor?.cancel() }
    /// Leaves a finished run's results without starting a new plan: both selections are kept.
    func dismissResult() {
        guard !isRunning else { return }
        result = nil; message = nil
    }
    func endSession() {
        guard !isRunning else { return }
        selectedIDs = []; pickedFiles = [:]; projectBuilds = [:]; result = nil; message = nil; selectionRevision &+= 1
    }
    private func currentCheck() async -> CandidateCheck? {
        do { return CandidateCheck(catalog: catalog, running: SystemRunningAppChecker(), exclusions: try await ExclusionsModel.shared.policyForScan(), cloud: Self.cloud,
                                    home: Self.checkHome) }
        catch { message = "Exclusion settings are unavailable, so nothing can be checked. Try again."; return nil }
    }
}

/// A frozen approval plus what the checks found at review time.
struct CatalogReview {
    let approval: CatalogApproval
    let refusals: [String: CheckRefusal]
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

/// How far the catalog scan is: the location being checked, its number, and what the finished ones found.
struct CatalogScanProgress {
    var title = ""
    var number = 0
    var total = 0
    var finished = 0
    var found: [Candidate] = []
    mutating func apply(_ step: CatalogDiscoveryProgress) {
        switch step {
        case .checking(_, let title, let number, let total): self.title = title; self.number = number; self.total = total
        case .finished(_, let number, _, let found): finished = number; self.found += found
        }
    }
}

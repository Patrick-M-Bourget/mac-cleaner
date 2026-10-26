import AppKit
import Foundation
import Observation
import StillCore
import SwiftUI

/// The catalog's categories in the app. Nothing here knows a specific rule; rules are data in StillCore.
@MainActor @Observable final class CatalogCleanupModel {
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    /// What the catalog's known locations hold.
    private(set) var discovered: [Candidate] = [] { didSet { indexPickedFiles() } }
    /// Large and old files in each folder the user picked and scanned, keyed by that folder (`UserFiles`).
    private(set) var pickedFiles: [URL: [Candidate]] = [:] { didSet { indexPickedFiles() } }
    /// The picked folders' files the plan offers, by "dev:ino". A file a catalog rule already offers is left to that rule.
    private(set) var pickedByResource: [String: Candidate] = [:]
    /// Everything the plan can offer.
    var candidates: [Candidate] { discovered + pickedCandidates }
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
    /// Chosen candidate ids. Nothing is preselected.
    private(set) var selectedIDs: Set<String> = []
    private(set) var selectionRevision: UInt64 = 0
    private(set) var isRunning = false
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
    /// Rules Still can't read without Full Disk Access (Safari's cache): shown as not accessible, never as 0.
    private(set) var notAccessibleRules: [CleanupRule] = []
    /// Names of owners that were running at the last scan. Their items stay choosable; the checks refuse them.
    private(set) var runningOwners: Set<String> = []
    /// Each candidate's owner name at the last scan, so views never look owners up while drawing.
    private var ownerNames: [String: String] = [:]
    private var executor: CleanupExecutor?
    private static let previewKey = "StillPreviewOnly"
    /// Decision 16: on by default; with it on, the whole flow runs and nothing changes on disk.
    var previewOnly: Bool {
        didSet {
            selectionRevision &+= 1
            if !LocalStateLocation.isDisposableTest { UserDefaults.standard.set(previewOnly, forKey: Self.previewKey) }
        }
    }

    init() {
        let stored = LocalStateLocation.isDisposableTest ? nil : UserDefaults.standard.object(forKey: Self.previewKey) as? Bool
        previewOnly = stored ?? true
    }

    /// The home folder whose known locations the catalog sizes. Debug UI tests inject a temp
    /// fixture home; a disposable test run without one sees no catalog locations at all.
    static var home: URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            guard let path = ProcessInfo.processInfo.environment["STILL_TEST_CATALOG_HOME"] else { return nil }
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let prefix = "StillTestHome-"
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
    /// A debug test home stands one in at `<home>/.still-test-user-folder`, so a UI test never reads the real one.
    static var userFolder: URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            guard let folder = home?.appendingPathComponent(".still-test-user-folder"), FileManager.default.fileExists(atPath: folder.path) else { return nil }
            return folder
        }
        #endif
        return Catalog.currentUserFolder()
    }

    /// Where a tool rule's executable is found. A debug test home only ever finds stand-ins inside
    /// `<home>/.still-test-tools`, so a UI test never runs a real tool. The sandboxed UI test runner quarantines the
    /// stand-ins it writes, and macOS won't run a quarantined script, so the attribute is cleared here.
    static var locateTool: @Sendable (ToolCommand) -> URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            guard let home else { return { _ in nil } }
            return { command in
                let tool = command.executables.lazy.map { home.appendingPathComponent(".still-test-tools/" + URL(fileURLWithPath: $0).lastPathComponent) }
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
    /// `<home>/.still-test-icloud.json`, so a UI test never reads or evicts anything in real iCloud Drive.
    static var cloud: any UbiquitousItemAccess {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureUbiquitousItems(home: home) }
        #endif
        return SystemUbiquitousItems()
    }

    /// Overview's summary; nil until the first scan of the known locations has finished.
    var overview: CatalogOverview? { hasScanned ? CatalogOverview(catalog: catalog, candidates: discovered) : nil }
    /// Owners of the rule's items that were running at the last scan, in name order.
    func runningOwnerNames(for rule: CleanupRule) -> [String] {
        Set(candidates(for: rule).compactMap { ownerNames[$0.id] }).intersection(runningOwners).sorted()
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

    func scanIfNeeded() async { if !hasScanned { await scan() } }
    /// Read-only sizing of the catalog's known locations.
    func scan() async {
        guard canEdit else { return }
        isScanning = true; message = nil
        defer { isScanning = false; hasScanned = true }
        guard let home = Self.home else { discovered = []; notes = []; overriddenRules = []; notAccessibleRules = []; runningOwners = []; ownerNames = [:]; return }
        // Excluded items are never offered (SPEC section 2); without the settings nothing can be offered safely.
        guard let exclusions = try? await ExclusionsModel.shared.policyForScan() else {
            discovered = []; notes = []; overriddenRules = []; notAccessibleRules = []; runningOwners = []; ownerNames = [:]
            message = "Exclusion settings are unavailable, so nothing can be checked. Try again."; return
        }
        let catalog = catalog
        let locate = Self.locateTool, system = Self.systemRoot
        let userFolder = Self.userFolder, cloud = Self.cloud
        // What grew records each completed catalog scan (#119).
        let growth = await GrowthHistoryModel.shared.beginCatalog(home: home, exclusionFingerprint: exclusions.fingerprint)
        let scanned = await Task.detached(priority: .userInitiated) { () -> (CatalogDiscovery, [CleanupRule], Set<String>, [String: String], FullDiskAccessStatus) in
            // Probed once per scan, at launch too, and shared with the guidance scan: it only opens a protected folder
            // and never prompts (#117).
            let access = FullDiskAccessProbe(home: home).status()
            let discovered = catalog.discovery(home: home, userFolder: userFolder, exclusions: exclusions, locateTool: locate, systemRoot: system, cloud: cloud,
                                               access: access)
            var owners: [String: RuleOwner] = [:], names: [String: String] = [:]
            for candidate in discovered.candidates { if let owner = catalog.owner(for: candidate) { owners[owner.name] = owner; names[candidate.id] = owner.name } }
            let running = SystemRunningAppChecker()
            return (discovered, catalog.overriddenRules(home: home, systemRoot: system), Set(owners.values.filter { running.isRunning($0) == true }.map(\.name)), names,
                    access)
        }.value
        await GrowthHistoryModel.shared.completeCatalog(scanned.0, catalog: catalog, fullDiskAccess: scanned.4, token: growth)
        discovered = scanned.0.candidates; notes = scanned.0.notes; notAccessibleRules = scanned.0.notAccessible; overriddenRules = scanned.1; runningOwners = scanned.2; ownerNames = scanned.3
        keepOnlyCurrentChoices()
        await scanGuidance(home: home, fullDiskAccess: scanned.4)
    }
    /// Drops chosen items that are no longer offered, and says so.
    private func keepOnlyCurrentChoices() {
        let found = Set(candidates.map(\.id))
        if !selectedIDs.isSubset(of: found) { selectedIDs.formIntersection(found); message = "Some items changed or are no longer on this Mac and were removed from your plan." }
        selectionRevision &+= 1
    }

    /// Lists a picked folder's large and old files from its finished scan. Read-only; nothing is chosen.
    func showPickedFiles(_ scan: ScanResult) async {
        guard !isRunning, let exclusions = try? await ExclusionsModel.shared.policyForScan() else { return }
        let home = Self.checkHome
        let found = await Task.detached(priority: .userInitiated) { UserFiles.candidates(in: scan, exclusions: exclusions, home: home) }.value
        guard !isRunning else { return }
        pickedFiles[scan.scope.standardizedFileURL] = found
        keepOnlyCurrentChoices()
    }
    /// A picked folder was forgotten, lost access or must be scanned again: its files are no longer offered.
    func forgetPickedFiles(_ scope: URL? = nil) {
        guard !isRunning else { return }
        if let scope { pickedFiles[scope.standardizedFileURL] = nil } else { pickedFiles = [:] }
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

    /// Freezes the chosen candidates and checks them once so the review can show what would be refused.
    func prepareReview() async -> CatalogReview? {
        guard canReview else { return nil }
        let approval = CatalogApproval(candidates: selectedCandidates, previewOnly: previewOnly)
        guard let check = await currentCheck() else { return nil }
        let refusals = await Task.detached { Dictionary(uniqueKeysWithValues: approval.candidates.compactMap { c in check.check(c).map { (c.id, $0) } }) }.value
        return CatalogReview(approval: approval, refusals: refusals)
    }
    func execute(_ approval: CatalogApproval, cancellation: CleanupCancellation) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false; executor = nil }
        guard let check = await currentCheck() else { return }
        do {
            let run = CleanupExecutor(journal: try CleanupJournalLocation.writer(), check: check, cancellation: cancellation)
            executor = run
            result = await run.execute(approval)
            selectedIDs = []; discovered = []; pickedFiles = [:]; hasScanned = false; selectionRevision &+= 1
        } catch { message = "The cleanup journal is unavailable. Nothing was changed." }
    }
    func cancel() { executor?.cancel() }
    func endSession() {
        guard !isRunning else { return }
        selectedIDs = []; pickedFiles = [:]; result = nil; message = nil; selectionRevision &+= 1
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
    /// Rules whose items the user chooses one by one: single Downloads files, and each model or disk image.
    var choosesItems: Bool { contents != nil || regen == .model || action == .evict || fromPickedFolders }
    /// Whether every item the rule offers is a single file.
    var offersFiles: Bool { contents != nil || fromPickedFolders }
}

extension Candidate {
    /// The name the plan shows, e.g. a model's name rather than its folder or manifest.
    var displayName: String { itemName ?? url.lastPathComponent }
    /// The row the plan groups the item under: the app it belongs to, or its browser profile.
    var group: String? { appName ?? profile }
}

/// The plan's Preview only state, in its bottom bar. On by default (Decision 16).
struct PreviewOnlyToggle: View {
    @Bindable var model: CatalogCleanupModel
    var body: some View {
        Toggle("Preview only (don’t change anything)", isOn: $model.previewOnly)
            .toggleStyle(.checkbox).disabled(!model.canEdit).accessibilityIdentifier("previewOnlyToggle")
            .help(model.previewOnly ? "Still checks each item and records what it would do. Nothing on disk changes." : "Confirmed cleanups change files on disk.")
    }
}

/// The cleanup plan: one row per catalog category, as Overview groups them, with its rules and items under "Choose items".
struct CatalogPlanSection: View {
    @Bindable var model: CatalogCleanupModel
    @Binding var expanded: Set<CatalogCategory>
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.planCategories) { row in
                    PlanCategoryRow(model: model, row: row, expanded: Binding(get: { expanded.contains(row.category) },
                                                                             set: { if $0 { expanded.insert(row.category) } else { expanded.remove(row.category) } }))
                    Divider().padding(.vertical, StillDesign.Space.md)
                }
            }
            ForEach(model.overriddenRules) { rule in
                StatusRow(text: "\(rule.owner?.name ?? rule.title) keeps its data in a custom location, so Still leaves it alone.",
                          symbol: "info.circle", role: .neutral, identifier: "planOverridden-" + rule.id)
            }
            if !model.notAccessibleRules.isEmpty {
                HStack(spacing: StillDesign.Space.sm) {
                    StatusRow(text: ListFormatter.localizedString(byJoining: model.notAccessibleRules.map(\.title)) + " needs Full Disk Access.", symbol: "lock",
                              identifier: "planNotAccessible").fixedSize()
                    FullDiskAccessLink(title: "Learn more", symbol: nil)
                    Spacer(minLength: 0)
                }
            }
            ForEach(model.notes, id: \.ruleID) { note in StatusRow(text: note.text, symbol: "info.circle", role: .neutral, identifier: "planNote-" + note.ruleID) }
            if model.isScanning { ProgressView("Checking known locations…") }
            if let message = model.message { StatusRow(text: message, symbol: "info.circle", role: .caution) }
        }.task { await model.scanIfNeeded() }
    }
}

/// A category: tri-state checkbox, badge, title, one short line and size, with "Choose items" inside.
private struct PlanCategoryRow: View {
    @Bindable var model: CatalogCleanupModel
    let row: CatalogOverview.Row
    @Binding var expanded: Bool
    var body: some View {
        let state = model.selectionState(for: row.rules)
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            CategorySelectionHeader(category: row.category.storageCategory, state: state, title: row.category.overviewTitle, detail: row.category.overviewDetail,
                                    size: row.valueText, enabled: model.canEdit, identifier: "planCategory-" + row.id) { model.setSelected(row.rules, state != .checked) }
            switch row.planLayout {
            case .ruleRows:
                ActionDisclosureGroup("Choose items · \(row.itemCount)", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(row.rules) { rule in PlanRuleRows(model: model, rule: rule) }
                    }.padding(.top, StillDesign.Space.sm)
                }.padding(.leading, StillDesign.Size.categoryContentIndent)
            case .items:
                if let rule = row.rules.first {
                    PlanRunningOwners(model: model, rule: rule).padding(.leading, StillDesign.Size.categoryContentIndent)
                    ActionDisclosureGroup("Choose items · \(row.itemCount)", isExpanded: $expanded) {
                        PlanRuleItems(model: model, rule: rule).padding(.top, StillDesign.Space.sm)
                    }.padding(.leading, StillDesign.Size.categoryContentIndent)
                }
            case .categoryOnly:
                if let rule = row.rules.first { PlanRunningOwners(model: model, rule: rule).padding(.leading, StillDesign.Size.categoryContentIndent) }
            }
        }
    }
}

/// Why a rule can't be cleaned right now: its owner is open.
private struct PlanRunningOwners: View {
    let model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        ForEach(model.runningOwnerNames(for: rule), id: \.self) { name in
            StatusRow(text: CheckRefusal.ownerRunning(name).reason, symbol: "exclamationmark.circle", role: .caution, identifier: "planRunning-" + rule.id)
                .font(StillDesign.TypeStyle.caption)
        }
    }
}

/// A rule's items, each chosen on its own: profiles or apps when it groups them, otherwise single items.
private struct PlanRuleItems: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        if model.candidates(for: rule).contains(where: { $0.group != nil }) { CatalogProfileRows(model: model, rule: rule) }
        else { CatalogItemRows(model: model, rule: rule) }
    }
}

/// A rule inside its category, then the items it lets you choose one by one (Downloads files, models, profiles).
private struct PlanRuleRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        let items = model.candidates(for: rule), state = model.selectionState(for: [rule])
        VStack(alignment: .leading, spacing: 0) {
            InspectableItemRow(name: rule.title, detail: rule.detail,
                               size: catalogBytes(model.estimatedBytes(for: rule), complete: model.sizeComplete(for: rule), upperBound: rule.estimateIsUpperBound,
                                                  estimate: model.sizeIsEstimate(for: rule)),
                               symbol: rule.offersFiles ? "doc.on.doc" : "folder", inspected: false,
                               inspect: { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }, detailLineLimit: 1) {
                MacroCategoryCheckbox(state: state, label: rule.title, enabled: model.canEdit, action: { model.setSelected(rule, state != .checked) },
                                      identifier: "planRule-" + rule.id, showsTitle: false).fixedSize()
            }
            PlanRunningOwners(model: model, rule: rule).padding(.leading, StillDesign.Space.xl).padding(.bottom, StillDesign.Space.sm)
            if rule.choosesItems { CatalogItemRows(model: model, rule: rule).padding(.leading, StillDesign.Space.xl) }
            if items.contains(where: { $0.group != nil }) { CatalogProfileRows(model: model, rule: rule).padding(.leading, StillDesign.Space.xl) }
            Divider()
        }
    }
}

/// One row per profile or app with its cache size; choosing a row chooses all of its folders.
struct CatalogProfileRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        let groups = Dictionary(grouping: model.candidates(for: rule)) { $0.group ?? "" }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { profile in
                let items = groups[profile] ?? []
                InspectableItemRow(name: profile, detail: items.map(\.url.lastPathComponent).sorted().joined(separator: ", "),
                                   size: catalogBytes(items.reduce(0) { $0 + $1.estimatedBytes }, complete: items.allSatisfy(\.sizeComplete)),
                                   symbol: items.contains { $0.appName != nil } ? "app" : "person.crop.circle", inspected: false,
                                   inspect: { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }, detailLineLimit: 1) {
                    Toggle("Select " + profile, isOn: Binding(get: { items.allSatisfy(model.isSelected) }, set: { on in items.forEach { model.setSelected($0, on) } }))
                        .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planProfile-\(rule.id)-\(profile)")
                }.help(items.map(\.url.path).sorted().joined(separator: "\n"))
            }
        }
    }
}

/// Single items a rule found (Downloads files, models, disk images), each chosen on its own. Nothing is preselected.
struct CatalogItemRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        let items = model.candidates(for: rule).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                InspectableItemRow(name: item.displayName, detail: detail(item), size: catalogBytes(item.estimatedBytes, estimate: item.sizeIsEstimate),
                                   symbol: item.isDirectory ? "folder" : "doc", inspected: false, inspect: { NSWorkspace.shared.activateFileViewerSelecting([item.url]) },
                                   detailLineLimit: 1) {
                    Toggle("Select " + item.displayName, isOn: Binding(get: { model.isSelected(item) }, set: { model.setSelected(item, $0) }))
                        .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planItem-" + item.displayName)
                }.help(item.url.path)
            }
        }
    }
    private func detail(_ item: Candidate) -> String {
        let folder = PathDisplay.shortLocation(of: item.url, home: CatalogCleanupModel.checkHome)
        return item.lastUsed.map { folder + " · Last used " + $0.formatted(date: .abbreviated, time: .omitted) } ?? folder
    }
}

extension ConsequenceGroup {
    var badge: CategoryBadge {
        switch self {
        case .permanentlyRemoved: CategoryBadge(symbol: "xmark.bin", color: StillDesign.purple)
        case .movedToTrash: CategoryBadge(symbol: "trash", color: StillDesign.orange)
        case .localCopiesRemoved: CategoryBadge(symbol: "icloud", color: StillDesign.blue)
        case .commandsRun: CategoryBadge(symbol: "terminal", color: StillDesign.teal)
        }
    }
}

/// The review sheet, grouped by consequence: each group's consequence once, one line per category, the files behind one disclosure.
struct CatalogConfirmationSection: View {
    let review: CatalogReview
    let catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if review.approval.previewOnly {
                StatusRow(text: "Preview only is on. Nothing on disk changes.", symbol: "eye", role: .neutral, identifier: "reviewPreviewNotice")
            }
            ForEach(ReviewGroup.groups(catalog: catalog, candidates: review.approval.candidates)) { group in
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    HStack(spacing: StillDesign.Space.md) {
                        group.consequence.badge
                        Text(group.consequence.title).font(StillDesign.TypeStyle.section)
                        Spacer()
                        Text(SizeEstimate(sum: group.lines.map(\.estimate)).text(upperBound: group.lines.contains(where: \.isUpperBound)))
                            .font(StillDesign.TypeStyle.section).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                        Text(group.consequence.consequence).font(StillDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(group.lines) { line in
                            HStack {
                                Text(line.category.overviewTitle)
                                Spacer()
                                Text(line.estimate.text(upperBound: line.isUpperBound)).monospacedDigit()
                            }.font(StillDesign.TypeStyle.note).accessibilityElement(children: .combine).accessibilityIdentifier("reviewLine-\(group.consequence)-\(line.id)")
                        }
                        ForEach(group.candidates.filter { review.refusals[$0.id] != nil }) { item in
                            StatusRow(text: item.displayName + " will be skipped: " + (review.refusals[item.id]?.reason ?? ""), symbol: "exclamationmark.circle", role: .caution)
                        }
                        ActionDisclosureGroup(StillDesign.items(group.candidates.count) + " · Show files") {
                            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                                ForEach(group.lines) { line in ForEach(line.rules) { rule in files(rule, line.candidates(for: rule)) } }
                            }.padding(.top, StillDesign.Space.sm)
                        }
                    }.padding(.leading, StillDesign.Size.badgeIndent)
                }
                Divider()
            }
        }
    }
    private func files(_ rule: CleanupRule, _ items: [Candidate]) -> some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            Text(rule.title).font(StillDesign.TypeStyle.caption.weight(.medium))
            Text(rule.consequence).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(items) { item in
                // A tool shows the exact command, e.g. `ollama rm llama3:latest` or `docker builder prune -a -f`.
                if let tool = rule.tool { Text(tool.commandLine(for: item.itemName)).font(StillDesign.TypeStyle.code).textSelection(.enabled) }
                if rule.tool?.deletesLocationAfter ?? true {
                    Text(item.displayName + " · " + PathDisplay.shortLocation(of: item.url, home: CatalogCleanupModel.checkHome))
                        .font(StillDesign.TypeStyle.caption).help(item.url.path)
                }
            }
        }
    }
}

/// Results: outcomes first (skipped and failed items on top, with their reason), details on demand.
struct CatalogResultsSection: View {
    let result: CatalogExecutionResult
    let catalog: Catalog
    /// One switch for every row's path and messages, so the list stays one line per item until asked.
    @State private var showsDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if result.previewOnly {
                let previewed = result.records.filter(\.wasPreviewed)
                StatusRow(text: "Preview · Nothing changed · " + catalogBytes(previewed.reduce(0) { $0 + $1.recordedBytes }, upperBound: upperBound(previewed)) + " would be affected",
                          symbol: "eye", role: .neutral, identifier: "catalogPreviewNotice")
            } else {
                // SPEC section 6: measured and estimated, reported separately; Trash is never counted as freed.
                SummarySurface {
                    HStack(alignment: .top, spacing: StillDesign.Space.xl) {
                        metric(result.measuredFreedBytes.map { catalogBytes($0) } ?? SizeEstimate.unknown.text, "Measured freed space")
                        let upperBound = upperBound(result.records)
                        metric(catalogBytes(result.estimatedBytes, upperBound: upperBound), upperBound ? "Estimated before cleanup · Upper bound" : "Estimated before cleanup")
                        if result.movedToTrashBytes > 0 { metric(catalogBytes(result.movedToTrashBytes), "Moved to Trash · Not yet freed") }
                    }
                }
                Text("Measured from the change in available space around each item. Other activity on this Mac can affect it.")
                    .font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(showsDetails ? "Hide paths and messages" : "Show paths and messages") { showsDetails.toggle() }
                        .buttonStyle(.link).font(StillDesign.TypeStyle.caption).accessibilityIdentifier("resultsDetailsToggle")
                }
                ForEach(result.records.attentionFirst) { record in
                    CatalogResultRow(record: record, rule: record.ruleID.flatMap { catalog.rule($0) }, showsDetails: showsDetails)
                    Divider()
                }
            }
            if let failure = result.journalFailure { StatusRow(text: failure, symbol: "exclamationmark.triangle", role: .caution) }
        }
    }
    private func upperBound(_ records: [CleanupRecord]) -> Bool { records.contains { $0.ruleID.flatMap { catalog.rule($0)?.estimateIsUpperBound } == true } }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            Text(value).font(StillDesign.TypeStyle.value).monospacedDigit()
            Text(label).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
        }
    }
}

/// One result: name and short location, outcome and size; its reason when it needs attention; path and messages when shown.
private struct CatalogResultRow: View {
    let record: CleanupRecord
    let rule: CleanupRule?
    let showsDetails: Bool
    private var name: String {
        let file = record.originalURL.lastPathComponent
        return rule?.itemName?(file) ?? (rule?.choosesItems == true ? file : rule?.title ?? file)
    }
    var body: some View {
        let role: StatusRole = record.state == .succeeded ? .success : record.wasPreviewed ? .neutral : .caution
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.md) {
                Image(systemName: record.state == .succeeded ? "checkmark.circle" : record.wasPreviewed ? "eye" : "exclamationmark.circle").foregroundStyle(role.color)
                    .frame(width: StillDesign.Space.lg)
                (Text(name).font(StillDesign.TypeStyle.rowTitle)
                    + Text(" · " + PathDisplay.shortLocation(of: record.originalURL, home: CatalogCleanupModel.checkHome)).foregroundStyle(.secondary))
                    .lineLimit(1).help(record.originalURL.path)
                Spacer(minLength: StillDesign.Space.md)
                if record.state == .succeeded, let trashed = record.trashURL {
                    Button("Reveal in Trash") { NSWorkspace.shared.activateFileViewerSelecting([trashed]) }.buttonStyle(.link)
                        .accessibilityLabel("Reveal \(record.originalURL.lastPathComponent) in Trash")
                }
                Text(record.outcomeTitle).font(StillDesign.TypeStyle.note)
                Text(catalogBytes(record.recordedBytes)).font(StillDesign.TypeStyle.note).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                if record.needsAttention { Text(record.message).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if showsDetails {
                    Text(record.originalURL.path).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if !record.needsAttention { Text(record.message).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary) }
                    if let output = record.toolOutput {
                        Text(output).font(StillDesign.TypeStyle.code).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("toolOutput-" + (record.ruleID ?? ""))
                    }
                }
            }.padding(.leading, StillDesign.Space.lg + StillDesign.Space.md)
        }.padding(.vertical, StillDesign.Space.md)
    }
}

import AppKit
import Foundation
import Observation
import StillCore
import SwiftUI

/// The catalog's categories in the app. Nothing here knows a specific rule; rules are data in StillCore.
@MainActor @Observable final class CatalogCleanupModel {
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    private(set) var candidates: [Candidate] = []
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
    /// Rules whose owner keeps its data elsewhere by a setting; they offer nothing.
    private(set) var overriddenRules: [CleanupRule] = []
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
    /// `<home>/.still-test-tools`, so a UI test never runs a real tool.
    static var locateTool: @Sendable (ToolCommand) -> URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            guard let home else { return { _ in nil } }
            return { command in
                command.executables.lazy.map { home.appendingPathComponent(".still-test-tools/" + URL(fileURLWithPath: $0).lastPathComponent) }
                    .first { FileManager.default.isExecutableFile(atPath: $0.path) }
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

    /// Overview's summary; nil until the first scan of the known locations has finished.
    var overview: CatalogOverview? { hasScanned ? CatalogOverview(catalog: catalog, candidates: candidates) : nil }
    /// Owners of the rule's items that were running at the last scan, in name order.
    func runningOwnerNames(for rule: CleanupRule) -> [String] {
        Set(candidates(for: rule).compactMap { ownerNames[$0.id] }).intersection(runningOwners).sorted()
    }
    var rulesFound: [CleanupRule] { catalog.rules.filter { rule in candidates.contains { $0.ruleID == rule.id } } }
    func candidates(for rule: CleanupRule) -> [Candidate] { candidates.filter { $0.ruleID == rule.id } }
    func estimatedBytes(for rule: CleanupRule) -> Int64 { candidates(for: rule).reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) } }
    func sizeComplete(for rule: CleanupRule) -> Bool { candidates(for: rule).allSatisfy(\.sizeComplete) }
    func sizeIsEstimate(for rule: CleanupRule) -> Bool { candidates(for: rule).contains(where: \.sizeIsEstimate) }
    var selectedCandidates: [Candidate] { candidates.filter { selectedIDs.contains($0.id) } }
    /// Rules with at least one chosen item.
    var selectedRuleCount: Int { Set(selectedCandidates.map(\.ruleID)).count }
    var selectedCount: Int { selectedCandidates.count }
    var estimatedBytes: Int64 { selectedCandidates.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) } }
    var canEdit: Bool { !isScanning && !isRunning && !AppLifecycleController.shared.operationInProgress && !AppLifecycleController.shared.maintenanceInProgress }
    var canReview: Bool { canEdit && selectedCount > 0 }
    func isSelected(_ rule: CleanupRule) -> Bool { candidates(for: rule).contains { selectedIDs.contains($0.id) } }
    func isSelected(_ candidate: Candidate) -> Bool { selectedIDs.contains(candidate.id) }
    func selectionState(for rule: CleanupRule) -> CategorySelectionState {
        let items = candidates(for: rule), chosen = items.filter { selectedIDs.contains($0.id) }.count
        return chosen == 0 ? .unchecked : chosen == items.count ? .checked : .mixed
    }

    func scanIfNeeded() async { if !hasScanned { await scan() } }
    /// Read-only sizing of the catalog's known locations.
    func scan() async {
        guard canEdit else { return }
        isScanning = true; message = nil
        defer { isScanning = false; hasScanned = true }
        guard let home = Self.home else { candidates = []; notes = []; overriddenRules = []; runningOwners = []; ownerNames = [:]; return }
        // Excluded items are never offered (SPEC section 2); without the settings nothing can be offered safely.
        guard let exclusions = try? await ExclusionsModel.shared.policyForScan() else {
            candidates = []; notes = []; overriddenRules = []; runningOwners = []; ownerNames = [:]
            message = "Exclusion settings are unavailable, so nothing can be checked. Try again."; return
        }
        let catalog = catalog
        let locate = Self.locateTool, system = Self.systemRoot
        let userFolder = Self.userFolder
        let scanned = await Task.detached(priority: .userInitiated) { () -> (CatalogDiscovery, [CleanupRule], Set<String>, [String: String]) in
            let discovered = catalog.discovery(home: home, userFolder: userFolder, exclusions: exclusions, locateTool: locate, systemRoot: system)
            var owners: [String: RuleOwner] = [:], names: [String: String] = [:]
            for candidate in discovered.candidates { if let owner = catalog.owner(for: candidate) { owners[owner.name] = owner; names[candidate.id] = owner.name } }
            let running = SystemRunningAppChecker()
            return (discovered, catalog.overriddenRules(home: home, systemRoot: system), Set(owners.values.filter { running.isRunning($0) == true }.map(\.name)), names)
        }.value
        candidates = scanned.0.candidates; notes = scanned.0.notes; overriddenRules = scanned.1; runningOwners = scanned.2; ownerNames = scanned.3
        let found = Set(candidates.map(\.id))
        if !selectedIDs.isSubset(of: found) { selectedIDs.formIntersection(found); message = "Some items changed or are no longer on this Mac and were removed from your plan." }
        selectionRevision &+= 1
    }
    /// Chooses or clears every item the rule found.
    func setSelected(_ rule: CleanupRule, _ selected: Bool) {
        let ids = candidates(for: rule).map(\.id)
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
            selectedIDs = []; candidates = []; hasScanned = false; selectionRevision &+= 1
        } catch { message = "The cleanup journal is unavailable. Nothing was changed." }
    }
    func cancel() { executor?.cancel() }
    func endSession() {
        guard !isRunning else { return }
        selectedIDs = []; result = nil; message = nil; selectionRevision &+= 1
    }
    private func currentCheck() async -> CandidateCheck? {
        do { return CandidateCheck(catalog: catalog, running: SystemRunningAppChecker(), exclusions: try await ExclusionsModel.shared.policyForScan()) }
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
        case .browser: .browser
        case .downloads: .downloads
        case .system, .models, .updaters, .logs: .managed
        }
    }
}

extension CatalogCategory {
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
        }
    }
}

extension SizeEstimate {
    /// Unknown stays unknown, never 0 (SPEC section 1).
    var text: String {
        switch self {
        case .measured(let bytes): catalogBytes(bytes)
        case .atLeast(let bytes): catalogBytes(bytes, complete: false)
        case .unknown: "Unknown"
        }
    }
}

extension CatalogOverview.Row {
    /// The row's size; "Up to" when part of it is copies that share disk blocks.
    var valueText: String {
        if case .measured(let bytes) = estimate, rules.contains(where: \.estimateIsUpperBound) { return catalogBytes(bytes, upperBound: true) }
        return estimate.text
    }
    /// What happens and to what, e.g. "Clear npm cache, Yarn cache · Move Installers to Trash".
    var detail: String {
        let cleared = rules.filter { $0.action != .trash }.map(\.title)
        let trashed = rules.filter { $0.action == .trash }.map(\.title)
        return ([cleared.isEmpty ? nil : "Clear " + Self.list(cleared), trashed.isEmpty ? nil : "Move " + Self.list(trashed) + " to Trash"]
            .compactMap { $0 }).joined(separator: " · ")
    }
    private static func list(_ titles: [String]) -> String {
        titles.count <= 3 ? titles.joined(separator: ", ") : titles.prefix(2).joined(separator: ", ") + " and \(titles.count - 2) more"
    }
}

/// A size as text. An incomplete size of 0 is unknown, as in `SizeEstimate`.
/// `upperBound` is for copies that share disk blocks (SPEC section 6): less may come back. An estimate reads "About".
func catalogBytes(_ value: Int64, complete: Bool = true, upperBound: Bool = false, estimate: Bool = false) -> String {
    if !complete && value == 0 { return SizeEstimate.unknown.text }
    return (!complete ? "At least " : upperBound ? "Up to " : estimate ? "About " : "") + ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
}

extension CleanupRule {
    /// Rules whose items the user chooses one by one: single Downloads files, and each model or disk image.
    var choosesItems: Bool { contents != nil || regen == .model }
}

extension Candidate {
    /// The name the plan shows, e.g. a model's name rather than its folder or manifest.
    var displayName: String { itemName ?? url.lastPathComponent }
}

struct PreviewOnlyToggle: View {
    @Bindable var model: CatalogCleanupModel
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            Toggle("Preview only (don’t change anything)", isOn: $model.previewOnly)
                .toggleStyle(.checkbox).disabled(!model.canEdit).accessibilityIdentifier("previewOnlyToggle")
            Text(model.previewOnly ? "Still checks each item and records what it would do. Nothing on disk changes." : "Confirmed cleanups change files on disk.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One header per catalog category in the Cleanup plan.
struct CatalogPlanSection: View {
    @Bindable var model: CatalogCleanupModel
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            ForEach(model.rulesFound) { rule in
                CategorySelectionHeader(category: rule.category.storageCategory, state: model.selectionState(for: rule),
                    title: rule.title, detail: rule.detail + " " + rule.consequence,
                    size: catalogBytes(model.estimatedBytes(for: rule), complete: model.sizeComplete(for: rule), upperBound: rule.estimateIsUpperBound,
                                       estimate: model.sizeIsEstimate(for: rule)),
                    enabled: model.canEdit, identifier: "planRule-" + rule.id) { model.setSelected(rule, model.selectionState(for: rule) != .checked) }
                if rule.choosesItems { CatalogItemChooser(model: model, rule: rule).padding(.leading, StillDesign.Space.xl) }
                if model.candidates(for: rule).contains(where: { $0.profile != nil }) {
                    CatalogProfileRows(model: model, rule: rule).padding(.leading, StillDesign.Space.xl)
                }
                ForEach(model.runningOwnerNames(for: rule), id: \.self) { name in
                    StatusRow(text: CheckRefusal.ownerRunning(name).reason + " Still won’t close it for you.", symbol: "exclamationmark.circle", role: .caution,
                              identifier: "planRunning-" + rule.id).padding(.leading, StillDesign.Space.xl)
                }
            }
            ForEach(model.overriddenRules) { rule in
                StatusRow(text: "\(rule.owner?.name ?? rule.title) keeps its data in a custom location set in its settings, so Still leaves it alone.",
                          symbol: "info.circle", role: .neutral, identifier: "planOverridden-" + rule.id)
            }
            ForEach(model.notes, id: \.ruleID) { note in StatusRow(text: note.text, symbol: "info.circle", role: .neutral, identifier: "planNote-" + note.ruleID) }
            if model.isScanning { ProgressView("Checking known locations…") }
            if !model.rulesFound.isEmpty || model.result != nil { PreviewOnlyToggle(model: model).padding(.leading, StillDesign.Space.xl) }
            if let message = model.message { StatusRow(text: message, symbol: "info.circle", role: .caution) }
        }.task { await model.scanIfNeeded() }
    }
}

/// One row per profile with that profile's cache size; choosing a profile chooses all of its cache folders.
struct CatalogProfileRows: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    var body: some View {
        let groups = Dictionary(grouping: model.candidates(for: rule)) { $0.profile ?? "" }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { profile in
                let items = groups[profile] ?? []
                InspectableItemRow(name: profile, detail: items.map(\.url.lastPathComponent).sorted().joined(separator: ", "),
                                   size: catalogBytes(items.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) }, complete: items.allSatisfy(\.sizeComplete)),
                                   symbol: "person.crop.circle", inspected: false,
                                   inspect: { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }) {
                    Toggle("Select " + profile, isOn: Binding(get: { items.allSatisfy(model.isSelected) }, set: { on in items.forEach { model.setSelected($0, on) } }))
                        .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planProfile-\(rule.id)-\(profile)")
                }
                Divider()
            }
        }
    }
}

/// Single items a rule found (Downloads files, models, disk images), each chosen on its own. Nothing is preselected.
struct CatalogItemChooser: View {
    @Bindable var model: CatalogCleanupModel
    let rule: CleanupRule
    @State private var expanded = false
    var body: some View {
        let items = model.candidates(for: rule).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        DisclosureGroup(isExpanded: $expanded) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    InspectableItemRow(name: item.displayName, detail: detail(item), size: catalogBytes(item.allocatedBytes ?? item.logicalBytes, estimate: item.sizeIsEstimate),
                                       symbol: item.isDirectory ? "folder" : "doc", inspected: false, inspect: { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }) {
                        Toggle("Select " + item.displayName, isOn: Binding(get: { model.isSelected(item) }, set: { model.setSelected(item, $0) }))
                            .labelsHidden().disabled(!model.canEdit).accessibilityIdentifier("planItem-" + item.displayName)
                    }
                    Divider()
                }
            }.padding(.top, StillDesign.Space.sm)
        } label: {
            let noun = rule.contents != nil ? "file" : "item"
            Text(items.count == 1 ? "1 \(noun) · Choose items" : "\(items.count) \(noun)s · Choose items")
        }
    }
    private func detail(_ item: Candidate) -> String {
        let folder = item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        return item.lastUsed.map { folder + " · Last used " + $0.formatted(date: .abbreviated, time: .omitted) } ?? folder
    }
}

struct CatalogConfirmationSection: View {
    let review: CatalogReview
    let catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if review.approval.previewOnly {
                StatusRow(text: "Preview only is on. Still checks each item and records what it would do. Nothing on disk changes.", symbol: "eye", role: .neutral)
            }
            ForEach(catalog.rules.filter { rule in review.approval.candidates.contains { $0.ruleID == rule.id } }) { rule in
                let items = review.approval.candidates.filter { $0.ruleID == rule.id }
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    HStack {
                        CategoryBadge(category: rule.category.storageCategory)
                        Text((rule.action == .trash ? "Move to Trash: " : "Clear ") + rule.title).font(StillDesign.TypeStyle.section)
                        Spacer()
                        Text(catalogBytes(items.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) }, complete: items.allSatisfy(\.sizeComplete), upperBound: rule.estimateIsUpperBound,
                                          estimate: items.contains(where: \.sizeIsEstimate))).monospacedDigit()
                    }
                    Text(rule.consequence).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(items.count == 1 ? "1 item · Show files" : "\(items.count) items · Show files") {
                        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                            ForEach(items) { item in
                                // A tool item shows the exact command, e.g. `ollama rm llama3:latest`.
                                Text(rule.tool.flatMap { $0.itemPlaceholder == nil ? nil : $0.commandLine(for: item.itemName) } ?? item.url.path).font(.caption).textSelection(.enabled)
                                if let refusal = review.refusals[item.id] { StatusRow(text: "Will be skipped: " + refusal.reason, symbol: "exclamationmark.circle", role: .caution) }
                            }
                        }.padding(.top, StillDesign.Space.sm)
                    }
                }
            }
            Text("Each item is checked again just before Still acts on it. Changed items, or items whose app is running, are skipped and reported.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CatalogResultsSection: View {
    let result: CatalogExecutionResult
    let catalog: Catalog
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            if result.previewOnly {
                StatusRow(text: "Preview only · Nothing on disk changed and no space was freed. Below is what Still would have done.", symbol: "eye", role: .neutral, identifier: "catalogPreviewNotice")
            }
            SummarySurface {
                HStack(alignment: .top, spacing: StillDesign.Space.xl) {
                    metric(result.previewOnly ? "—" : result.measuredFreedBytes.map { catalogBytes($0) } ?? "Unknown", "Measured freed space")
                    let upperBound = result.records.contains { $0.ruleID.flatMap { catalog.rule($0)?.estimateIsUpperBound } == true }
                    metric(catalogBytes(result.estimatedBytes, upperBound: upperBound), upperBound ? "Estimated before cleanup · Upper bound" : "Estimated before cleanup")
                    if result.movedToTrashBytes > 0 { metric(catalogBytes(result.movedToTrashBytes), "Moved to Trash · Not yet freed") }
                }
            }
            ForEach(result.records) { record in
                HStack(alignment: .top, spacing: StillDesign.Space.md) {
                    let wouldAct = record.wasPreviewed
                    Image(systemName: record.state == .succeeded ? "checkmark.circle" : wouldAct ? "eye" : "exclamationmark.circle")
                        .foregroundStyle(record.state == .succeeded ? StatusRole.success.color : wouldAct ? StatusRole.neutral.color : StatusRole.caution.color)
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text(record.ruleID.flatMap { catalog.rule($0)?.title } ?? record.originalURL.lastPathComponent).font(.body.weight(.medium))
                        Text(record.originalURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(record.message).font(.caption).foregroundStyle(.secondary)
                        if let output = record.toolOutput {
                            DisclosureGroup("Tool output") {
                                Text(output).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.font(.caption).accessibilityIdentifier("toolOutput-" + (record.ruleID ?? ""))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: StillDesign.Space.xs) {
                        Text(record.outcomeTitle).font(.callout)
                        if record.state == .succeeded, let trashed = record.trashURL {
                            Button("Reveal in Trash") { NSWorkspace.shared.activateFileViewerSelecting([trashed]) }
                                .accessibilityLabel("Reveal \(record.originalURL.lastPathComponent) in Trash")
                        }
                    }
                }
            }
            if let failure = result.journalFailure { StatusRow(text: failure, symbol: "exclamationmark.triangle", role: .caution) }
            if result.movedToTrashBytes > 0 {
                StatusRow(text: "Items moved to Trash still use space until you empty the Trash. Still never empties it.", symbol: "trash", role: .neutral, identifier: "catalogTrashNotice")
            }
            Text("Measured freed space is the change in available space read right before and after each item. Downloads, snapshots and other activity can affect it, and it may differ from the estimate.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            Text(value).font(StillDesign.TypeStyle.value).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

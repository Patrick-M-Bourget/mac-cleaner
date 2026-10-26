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
    private(set) var selectedRuleIDs: Set<String> = []
    private(set) var selectionRevision: UInt64 = 0
    private(set) var isRunning = false
    private(set) var result: CatalogExecutionResult?
    private(set) var message: String?
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

    var rulesFound: [CleanupRule] { catalog.rules.filter { rule in candidates.contains { $0.ruleID == rule.id } } }
    func candidates(for rule: CleanupRule) -> [Candidate] { candidates.filter { $0.ruleID == rule.id } }
    func estimatedBytes(for rule: CleanupRule) -> Int64 { candidates(for: rule).reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) } }
    func sizeComplete(for rule: CleanupRule) -> Bool { candidates(for: rule).allSatisfy(\.sizeComplete) }
    var selectedCandidates: [Candidate] { candidates.filter { selectedRuleIDs.contains($0.ruleID) } }
    var selectedCount: Int { selectedCandidates.count }
    var estimatedBytes: Int64 { selectedCandidates.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) } }
    var canEdit: Bool { !isScanning && !isRunning && !AppLifecycleController.shared.operationInProgress && !AppLifecycleController.shared.maintenanceInProgress }
    var canReview: Bool { canEdit && selectedCount > 0 }
    func isSelected(_ rule: CleanupRule) -> Bool { selectedRuleIDs.contains(rule.id) }

    func scanIfNeeded() async { if !hasScanned { await scan() } }
    /// Read-only sizing of the catalog's known locations.
    func scan() async {
        guard canEdit else { return }
        isScanning = true; message = nil
        defer { isScanning = false; hasScanned = true }
        guard let home = Self.home else { candidates = []; return }
        let catalog = catalog
        candidates = await Task.detached(priority: .userInitiated) { catalog.discover(home: home) }.value
        let found = Set(candidates.map(\.ruleID))
        if !selectedRuleIDs.isSubset(of: found) { selectedRuleIDs.formIntersection(found); message = "Some categories are no longer on this Mac and were removed from your plan." }
        selectionRevision &+= 1
    }
    func setSelected(_ rule: CleanupRule, _ selected: Bool) {
        guard canEdit, !candidates(for: rule).isEmpty else { return }
        if selected { selectedRuleIDs.insert(rule.id) } else { selectedRuleIDs.remove(rule.id) }
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
            selectedRuleIDs = []; candidates = []; hasScanned = false; selectionRevision &+= 1
        } catch { message = "The cleanup journal is unavailable. Nothing was changed." }
    }
    func cancel() { executor?.cancel() }
    func endSession() {
        guard !isRunning else { return }
        selectedRuleIDs = []; result = nil; message = nil; selectionRevision &+= 1
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
        case .system, .models: .managed
        }
    }
}

func catalogBytes(_ value: Int64, complete: Bool = true) -> String {
    (complete ? "" : "At least ") + ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
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
                CategorySelectionHeader(category: rule.category.storageCategory, state: model.isSelected(rule) ? .checked : .unchecked,
                    title: rule.title, detail: rule.detail + " " + rule.consequence,
                    size: catalogBytes(model.estimatedBytes(for: rule), complete: model.sizeComplete(for: rule)),
                    enabled: model.canEdit, identifier: "planRule-" + rule.id) { model.setSelected(rule, !model.isSelected(rule)) }
            }
            if model.isScanning { ProgressView("Checking known locations…") }
            if !model.rulesFound.isEmpty || model.result != nil { PreviewOnlyToggle(model: model).padding(.leading, StillDesign.Space.xl) }
            if let message = model.message { StatusRow(text: message, symbol: "info.circle", role: .caution) }
        }
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
                        Text((rule.action == .delete ? "Clear " : "Move to Trash: ") + rule.title).font(StillDesign.TypeStyle.section)
                        Spacer()
                        Text(catalogBytes(items.reduce(0) { $0 + ($1.allocatedBytes ?? $1.logicalBytes) }, complete: items.allSatisfy(\.sizeComplete))).monospacedDigit()
                    }
                    Text(rule.consequence).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(items.count == 1 ? "1 item · Show files" : "\(items.count) items · Show files") {
                        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                            ForEach(items) { item in
                                Text(item.url.path).font(.caption).textSelection(.enabled)
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
                    metric(catalogBytes(result.estimatedBytes), "Estimated before cleanup")
                    if result.movedToTrashBytes > 0 { metric(catalogBytes(result.movedToTrashBytes), "Moved to Trash · Not yet freed") }
                }
            }
            ForEach(result.records) { record in
                HStack(alignment: .top, spacing: StillDesign.Space.md) {
                    let wouldAct = record.previewOnly == true && record.state == .skipped && record.message.hasPrefix("Preview")
                    Image(systemName: record.state == .succeeded ? "checkmark.circle" : wouldAct ? "eye" : "exclamationmark.circle")
                        .foregroundStyle(record.state == .succeeded ? StatusRole.success.color : wouldAct ? StatusRole.neutral.color : StatusRole.caution.color)
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text(record.ruleID.flatMap { catalog.rule($0)?.title } ?? record.originalURL.lastPathComponent).font(.body.weight(.medium))
                        Text(record.originalURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(record.message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(outcome(record)).font(.callout)
                }
            }
            if let failure = result.journalFailure { StatusRow(text: failure, symbol: "exclamationmark.triangle", role: .caution) }
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
    private func outcome(_ record: CleanupRecord) -> String {
        if record.previewOnly == true, record.state == .skipped, record.message.hasPrefix("Preview") { return record.action == "delete" ? "Would delete" : "Would move to Trash" }
        switch record.state {
        case .succeeded: return record.action == "delete" ? "Deleted" : "Moved to Trash"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        case .cancelled: return "Not started"
        case .unknown, .intent, .pending: return "Unresolved"
        }
    }
}

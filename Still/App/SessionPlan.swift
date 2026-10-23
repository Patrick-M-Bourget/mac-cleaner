import Foundation
import Observation
import StillCore
import SwiftUI

@MainActor @Observable final class SessionPlan {
    private(set) var draft = PlanDraft()
    private(set) var scans: [URL: ScanResult] = [:]
    private(set) var message: String?
    private(set) var isPreparing = false
    private(set) var approvedBatch: CleanupApproval?
    var mutationVersion: UInt64 { draft.mutationVersion }
    var canReview: Bool { !isPreparing && draft.selectedCount > 0 }
    var categoryState: CategorySelectionState {
        guard let downloads else { return .unchecked }
        return draft.categoryState(in: Array(scans.values), downloads: downloads)
    }
    var eligibleLogicalBytes: Int64 {
        var seen = Set<String>()
        return rows.filter { seen.insert($0.item.resourceID).inserted }.reduce(0) { $0 + ($1.item.logicalBytes ?? 0) }
    }
    private var downloads: DownloadsRoot?
    #if DEBUG
    private var requestedFixture: URL?
    #endif
    init() {
        let root = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        downloads = root.flatMap { try? DownloadsRoot(url: $0) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-downloads-root"),
           let path = ProcessInfo.processInfo.environment["STILL_TEST_DOWNLOADS_ROOT"] {
            requestedFixture = URL(fileURLWithPath: path)
        }
        #endif
    }
    struct Row: Identifiable {
        let item: FileObservation
        let scan: ScanResult
        var id: String { item.url.path + "|" + item.resourceID }
    }
    var rows: [Row] {
        var seen = Set<String>()
        return scans.values.sorted { $0.observedAt > $1.observedAt }.flatMap { scan in
            scan.observations.compactMap { item in
                let row = Row(item: item, scan: scan)
                return eligible(item, in: scan) && seen.insert(row.id).inserted ? row : nil
            }
        }.sorted { $0.item.url.path < $1.item.url.path }
    }
    func observe(_ scan: ScanResult) {
        #if DEBUG
        // Bind only after NSOpenPanel selected the exact fixture; never probe runner data at launch.
        if let requestedFixture, requestedFixture.standardizedFileURL.path == scan.scope.standardizedFileURL.path,
           let fixture = try? DownloadsRoot(url: scan.scope), fixture.url.lastPathComponent.hasPrefix("StillSelectionUI-") {
            let runnerTemp = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.patrickbourget.StillUITests.xctrunner/Data/tmp")
            let canonicalRunnerTemp: String? = runnerTemp.path
            let canonicalAppTemp = (try? DownloadsRoot(url: FileManager.default.temporaryDirectory))?.url.path
            let parent = fixture.url.deletingLastPathComponent().path
            if [canonicalRunnerTemp, canonicalAppTemp, "/private/tmp", "/tmp"].compactMap({ $0 }).contains(parent) { downloads = fixture }
        }
        #endif
        invalidateReview()
        scans[scan.scope] = scan
    }
    func eligible(_ item: FileObservation, in scan: ScanResult) -> Bool {
        guard let downloads else { return false }
        return PlanDraft.canConsider(item, in: scan, downloads: downloads)
    }
    func invalidateReview() { draft.invalidateReview(); approvedBatch = nil }
    func review() throws -> CleanupReview {
        guard canReview else { throw PlanSelectionError.ineligible }
        return try draft.review()
    }
    func approve(_ review: CleanupReview) throws {
        guard canReview else { throw PlanSelectionError.ineligible }
        approvedBatch = try draft.approve(review)
    }
    func toggleAll() async {
        guard !isPreparing else { return }
        if categoryState == .checked { draft.clear(); approvedBatch = nil; AppLifecycleController.shared.hasPendingPlan = false; return }
        guard let downloads else { return }
        invalidateReview()
        let version = mutationVersion, scans = Array(scans.values), current = draft
        isPreparing = true
        let result = await Task.detached(priority: .userInitiated) {
            var updated = current
            let skipped = updated.selectAll(in: scans, downloads: downloads)
            return (updated, skipped)
        }.value
        isPreparing = false
        guard mutationVersion == version else { message = "Findings changed during selection. Review the latest eligible items and try again."; return }
        draft = result.0
        message = result.1 > 0 ? "Some files changed or became unavailable; they were not added." : nil
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func set(_ item: FileObservation, in scan: ScanResult, selected: Bool) {
        guard !isPreparing else { return }
        approvedBatch = nil
        if !selected { draft.remove(item.url.path + "|" + item.resourceID + "|moveToTrash") }
        else {
            guard let downloads else { return }
            do { try draft.select(item, in: scan, downloads: downloads); message = nil }
            catch { message = "This target is no longer eligible. Recheck its selected Downloads scope." }
        }
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func remove(_ target: PlannedTarget) {
        guard !isPreparing else { return }
        approvedBatch = nil
        draft.remove(target.id)
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func endSession() { draft.clear(); scans.removeAll(); approvedBatch = nil; AppLifecycleController.shared.hasPendingPlan = false }
}

struct LiveCleanupPlanView: View {
    @Bindable var selection: SessionPlan
    @State private var search = ""
    @State private var review: CleanupReview?
    @State private var approvalError: String?
    @State private var reviewFocusRequest = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cleanup plan").font(.largeTitle.weight(.semibold))
            Text("Selected for Trash").font(.headline)
            Text("\(selection.draft.selectedCount) files selected · \(ByteCountFormatter.string(fromByteCount: selection.draft.logicalBytes, countStyle: .decimal)) logical bytes across unique storage identities")
                .accessibilityIdentifier("liveSelectionSummary")
            Text("Move to Trash · Space stays occupied until Finder empties Trash. Selection changes the plan only. Final approval is separate. No files are moved in this build.").foregroundStyle(.secondary)
            MacroCategoryCheckbox(state: selection.categoryState, label: "Select all \(selection.rows.count) eligible Downloads files · \(ByteCountFormatter.string(fromByteCount: selection.eligibleLogicalBytes, countStyle: .decimal)) logical", enabled: !selection.isPreparing && !selection.rows.isEmpty) { Task { await selection.toggleAll() } }
                .fixedSize(horizontal: true, vertical: false).frame(height: 26)
            if selection.isPreparing { ProgressView("Checking exact Downloads targets…") }
            if let approved = selection.approvedBatch { Text("Approved batch: \(approved.targets.count) files · No files moved.").foregroundStyle(.secondary) }
            ReviewCleanupButton(enabled: selection.canReview, focusRequest: reviewFocusRequest) {
                do { review = try selection.review(); approvalError = nil } catch { approvalError = "Recheck the selected targets before reviewing." }
            }.fixedSize()
            if let approvalError { Text(approvalError).foregroundStyle(.secondary) }
            TextField("Search Downloads items", text: $search)
            LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(selection.draft.selected) { target in
                HStack {
                    Toggle(isOn: Binding(get: { true }, set: { if !$0 { selection.remove(target) } })) { Text(target.url.lastPathComponent) }
                        .accessibilityLabel("Selected \(target.url.lastPathComponent)").disabled(selection.isPreparing)
                    Text(target.url.path).font(.caption).foregroundStyle(.secondary)
                }
            }
            }
            Divider()
            Text("Eligible Downloads files").font(.headline)
            if selection.scans.isEmpty { Text("Choose and scan Downloads or a folder inside it to add exact files. Nothing is preselected.").foregroundStyle(.secondary) }
            LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(selection.rows.filter { search.isEmpty || $0.item.url.path.localizedCaseInsensitiveContains(search) }) { row in
                Toggle(isOn: Binding(get: { selection.draft.contains(row.item) }, set: { selection.set(row.item, in: row.scan, selected: $0) })) {
                    VStack(alignment: .leading) { Text(row.item.url.lastPathComponent); Text(row.item.url.path).font(.caption).foregroundStyle(.secondary) }
                }.accessibilityLabel("Select \(row.item.url.lastPathComponent)").disabled(selection.isPreparing)
            }
            }
            if let message = selection.message { Text(message).foregroundStyle(.secondary) }
            Text("Hidden search results keep their selections. Hardlink aliases are separate exact paths; their storage bytes count once.").font(.caption).foregroundStyle(.secondary)

        }
        .sheet(item: $review, onDismiss: { reviewFocusRequest += 1 }) { snapshot in
            CleanupConfirmationView(review: snapshot, cancel: { review = nil }) {
                do { try selection.approve(snapshot); review = nil }
                catch { approvalError = "The plan changed. Review the latest exact targets before approving."; review = nil }
            }
        }
        .onChange(of: selection.mutationVersion) { _, _ in if review != nil { review = nil } }
    }
}

private struct MacroCategoryCheckbox: NSViewRepresentable {
    let state: CategorySelectionState
    let label: String
    let enabled: Bool
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: label, target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ view: NSButton, context: Context) {
        context.coordinator.action = action
        view.title = label; view.isEnabled = enabled
        view.setAccessibilityIdentifier("downloadsCategorySelection")
        view.setAccessibilityLabel(label)
        view.state = state == .checked ? .on : state == .mixed ? .mixed : .off
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
}

private struct CleanupConfirmationView: View {
    let review: CleanupReview
    let cancel: () -> Void
    let approve: () -> Void
    @State private var expanded = false
    private var logicalBytes: Int64 {
        var seen = Set<String>()
        return review.targets.filter { seen.insert($0.resourceID).inserted }.reduce(0) { $0 + $1.logicalBytes }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review Move to Trash").font(.title2.weight(.semibold))
            Text("\(review.targets.count) exact files · \(ByteCountFormatter.string(fromByteCount: logicalBytes, countStyle: .decimal)) logical bytes")
            Text("Space remains occupied until Finder empties Trash. Files may have separate Trash locations; folder structure and automatic restoration are not guaranteed.").foregroundStyle(.secondary)
            Text("Downloads scope · No folders or new discoveries will be included.").font(.callout)
            Text("Approval records this exact batch. No files will be moved in this build.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Selected scan locations").font(.headline)
                    ForEach(Array(Set(review.targets.map { $0.scope.path })).sorted(), id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    DisclosureGroup("Exact files (\(review.targets.count))", isExpanded: $expanded) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(review.targets) { target in
                                Text(target.url.pathComponents.dropFirst(target.downloadsRoot.url.pathComponents.count).joined(separator: "/"))
                                    .font(.callout).textSelection(.enabled)
                            }
                        }.padding(.top, 8)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Spacer(); Button("Approve Move to Trash", action: approve).buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 640, height: 520)
    }
}


/// Native first-responder restoration is explicit and one-shot after a sheet closes.
private struct ReviewCleanupButton: NSViewRepresentable {
    let enabled: Bool
    let focusRequest: Int
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> FocusButton {
        let view = FocusButton(title: "Review cleanup", target: context.coordinator, action: #selector(Coordinator.clicked))
        view.bezelStyle = .rounded
        view.setAccessibilityLabel("Review cleanup")
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ view: FocusButton, context: Context) {
        view.isEnabled = enabled
        context.coordinator.action = action
        if context.coordinator.appliedFocusRequest != focusRequest {
            context.coordinator.appliedFocusRequest = focusRequest
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window?.attachedSheet == nil else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        var appliedFocusRequest = 0
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
    @MainActor final class FocusButton: NSButton {
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if [" ", "\r"].contains(event.charactersIgnoringModifiers ?? ""), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                performClick(nil)
            } else { super.keyDown(with: event) }
        }
    }
}

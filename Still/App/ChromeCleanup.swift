import AppKit
import Darwin
import Foundation
import Observation
import StillCore
import SwiftUI

/// Live browser selection is group approval, never personal-file target authority.
@MainActor @Observable final class ChromeCleanupModel {
    private(set) var inspectionEnabled = false
    private(set) var inspection: ChromeCacheInspection?
    private(set) var selectedGroupIDs: Set<String> = []
    private(set) var selectionRevision: UInt64 = 0
    private(set) var isBusy = false
    private(set) var isRunning = false
    private(set) var message: String?
    private(set) var intentFeedback: String?
    private(set) var inspectionFailure: String?
    private(set) var result: ChromeCacheRun?
    private var service: ChromeCacheService?
    private var access: ChromeCacheAccess?
    private let injectedAccess: Bool
    private let initialAccess: ChromeCacheAccess?
    private var cancellation: CleanupCancellation?

    init(service: ChromeCacheService? = nil, access: ChromeCacheAccess? = nil) {
        self.service = service; self.access = access; initialAccess = access; injectedAccess = access != nil
        do {
            let file = try intentURL(create: false)
            if try validIntentFile(file) { inspectionEnabled = try String(contentsOf: file, encoding: .utf8) == "enabled\n" }
        } catch { intentFeedback = "Chrome inspection preference could not be read. Enable inspection explicitly for this session." }
    }

    var groups: [ChromeCacheGroup] { inspection?.groups ?? [] }
    var eligibleGroups: [ChromeCacheGroup] { groups.filter { $0.availability == .eligible && $0.estimatedBytes != nil } }
    var selectedGroups: [ChromeCacheGroup] { eligibleGroups.filter { selectedGroupIDs.contains($0.id) } }
    var selectedCount: Int { selectedGroups.count }
    var estimatedBytes: Int64? { total(selectedGroups) }
    var availableBytes: Int64? {
        guard let inspection, inspection.availability == .eligible || inspection.availability == .empty else { return nil }
        return total(groups)
    }
    var canEdit: Bool {
        !isBusy && !isRunning && !AppLifecycleController.shared.operationInProgress && !AppLifecycleController.shared.maintenanceInProgress
    }
    var canReview: Bool { canEdit && selectedCount > 0 && inspection?.availability == .eligible }
    var categoryState: CategorySelectionState {
        guard !eligibleGroups.isEmpty, selectedCount > 0 else { return .unchecked }
        return selectedCount == eligibleGroups.count ? .checked : .mixed
    }
    var rows: [ChromeCacheRow] {
        groups.map { .init(id: $0.id, profile: $0.profileIdentifier, estimatedBytes: $0.estimatedBytes,
                          observedAt: $0.observedAt, availability: $0.availability, selected: selectedGroupIDs.contains($0.id)) }
    }
    var statusText: String {
        if isRunning { return "Clearing selected Chrome cache groups…" }
        if isBusy { return "Checking Chrome and verified cache groups…" }
        if !inspectionEnabled { return "Chrome inspection is off" }
        if let inspectionFailure { return "Unavailable · " + inspectionFailure }
        if let inspection, let reason = inspection.unavailableReason {
            let state: String
            switch inspection.availability {
            case .running: state = "Running"
            case .denied: state = "Access unavailable"
            case .unsupported: state = "Unsupported version or layout"
            case .unknown: state = "Unknown"
            case .eligible, .empty: state = "Not available"
            }
            return state + " · " + reason
        }
        guard let inspection else { return "Not inspected · Choose Recheck Chrome to inspect manually." }
        if inspection.groups.isEmpty { return "No verified Chrome profiles found." }
        if eligibleGroups.isEmpty { return "No eligible downloaded asset caches found." }
        return "Closed · \(eligibleGroups.count) cache groups ready to review"
    }

    func enableInspection() async {
        guard canEdit else { return }
        inspectionEnabled = true
        do {
            let file = try intentURL(create: true)
            _ = try validIntentFile(file)
            try Data("enabled\n".utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            intentFeedback = nil
        } catch { intentFeedback = "Chrome inspection is enabled for this session. Its preference could not be saved." }
        await manualScan()
    }

    func manualScan() async {
        guard inspectionEnabled, canEdit else { return }
        isBusy = true; message = nil; result = nil; inspectionFailure = nil
        defer { isBusy = false }
        do {
            let service = try currentService()
            let access = try currentAccess()
            let previous = selectedGroupIDs
            let observed = await service.inspect(access)
            inspection = observed
            let eligible = Set(observed.groups.filter { $0.availability == .eligible && $0.estimatedBytes != nil }.map(\.id))
            selectedGroupIDs.formIntersection(eligible)
            selectionRevision &+= 1
            if !previous.subtracting(selectedGroupIDs).isEmpty {
                message = "Some selected cache groups are no longer eligible and were removed from your plan. Close Chrome or resolve the reported issue, then recheck explicitly. Newly found groups stay unchecked."
            }
        } catch {
            inspection = nil
            if !selectedGroupIDs.isEmpty { message = "Selected cache groups were removed because their access could not be verified. Recheck before choosing again." }
            selectedGroupIDs = []; selectionRevision &+= 1
            inspectionFailure = String(describing: error)
        }
    }
    func recheck() async { await manualScan() }
    func setSelected(_ id: String, selected: Bool) {
        guard canEdit, eligibleGroups.contains(where: { $0.id == id }) else { return }
        if selected { selectedGroupIDs.insert(id) } else { selectedGroupIDs.remove(id) }
        selectionRevision &+= 1
    }
    func toggleCategory() {
        guard canEdit else { return }
        if selectedCount == eligibleGroups.count { selectedGroupIDs = [] }
        else { selectedGroupIDs = Set(eligibleGroups.map(\.id)) }
        selectionRevision &+= 1
    }
    func prepareReview() async -> ChromeCacheApproval? {
        guard canReview else { return nil }
        do { return try await currentService().approve(groupIDs: selectedGroupIDs) }
        catch { message = "Chrome cache review could not be prepared: \(error). Recheck Chrome before continuing."; return nil }
    }
    func execute(_ approval: ChromeCacheApproval, cancellation externalCancellation: CleanupCancellation? = nil) async {
        guard !isRunning, !isBusy else { return }
        isRunning = true; let request = externalCancellation ?? CleanupCancellation(); cancellation = request
        defer { isRunning = false; cancellation = nil }
        do {
            result = try await currentService().execute(approval, cancellation: request)
            selectedGroupIDs = []; inspection = nil; selectionRevision &+= 1
        } catch { message = "Chrome cleanup could not start: \(error). No automatic retry will run." }
    }
    func records() async throws -> [ChromeCacheRun] { try await currentService().records() }
    func cancel() { cancellation?.cancel() }
    func invalidateReview() { selectionRevision &+= 1 }
    func endSession() {
        guard !isBusy, !isRunning else { return }
        selectedGroupIDs = []; inspection = nil; result = nil; message = nil; inspectionFailure = nil; selectionRevision &+= 1
    }

    /// Called only after the shared Reset flow has checked recovery and journal retention.
    func resetInspectionPreference() throws {
        guard !isBusy, !isRunning else { throw CocoaError(.fileWriteNoPermission) }
        try LocalStateLocation.removeKnownFile("chrome-inspection-intent.txt")
        inspectionEnabled = false
        access = injectedAccess ? initialAccess : nil
        intentFeedback = nil
        endSession()
    }

    /// Custom roots are always an explicit user choice and still require Core ownership validation.
    func chooseCustomLocation() async {
        guard inspectionEnabled, canEdit, !LocalStateLocation.isDisposableTest else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Chrome user-data folder"
        panel.message = "Choose the Chrome user-data folder containing Local State. Unknown, shared or redirected layouts remain unavailable."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Inspect Chrome location"
        guard panel.runModal() == .OK, let root = panel.url, canEdit else { return }
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            intentFeedback = "Google Chrome could not be located. No folder was inspected."; return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        let canonical = root.standardizedFileURL
        let cache: URL
        if canonical.path.hasPrefix(support.path + "/") {
            cache = home.appendingPathComponent("Library/Caches").appendingPathComponent(String(canonical.path.dropFirst(support.path.count + 1)))
        } else { cache = canonical }
        access = .init(applicationURL: application, dataRootURL: canonical, cacheRootURL: cache, customLocation: true)
        selectedGroupIDs = []; selectionRevision &+= 1
        let granted = root.startAccessingSecurityScopedResource()
        defer { if granted { root.stopAccessingSecurityScopedResource() } }
        await manualScan()
    }

    private func currentService() throws -> ChromeCacheService {
        if let service { return service }
        let instance = ChromeCacheService(journalURL: try LocalStateLocation.root(create: true).appendingPathComponent("chrome-cleanup.json"))
        service = instance; return instance
    }
    private func currentAccess() throws -> ChromeCacheAccess {
        if let access { return access }
        guard !LocalStateLocation.isDisposableTest || injectedAccess else { throw CocoaError(.fileReadNoPermission) }
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            throw ChromeInspectionFailure("Google Chrome could not be located. No profiles were inspected.")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let native = ChromeCacheAccess(applicationURL: application,
                                       dataRootURL: home.appendingPathComponent("Library/Application Support/Google/Chrome"),
                                       cacheRootURL: home.appendingPathComponent("Library/Caches/Google/Chrome"), customLocation: false)
        access = native; return native
    }
    private func intentURL(create: Bool) throws -> URL {
        try LocalStateLocation.root(create: create).appendingPathComponent("chrome-inspection-intent.txt")
    }
    private func validIntentFile(_ file: URL) throws -> Bool {
        var info = stat()
        guard lstat(file.path, &info) == 0 else { if errno == ENOENT { return false }; throw CocoaError(.fileReadUnknown) }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_size <= 64,
              file.path == file.resolvingSymlinksInPath().path else { throw CocoaError(.fileReadNoPermission) }
        return true
    }
    private func total(_ groups: [ChromeCacheGroup]) -> Int64? {
        var value: Int64 = 0
        for group in groups {
            guard let bytes = group.estimatedBytes else { return nil }
            let sum = value.addingReportingOverflow(bytes); guard !sum.overflow else { return nil }; value = sum.partialValue
        }
        return value
    }
}
private struct ChromeInspectionFailure: Error, CustomStringConvertible { let description: String; init(_ value: String) { description = value } }

struct ChromeCacheRow: Identifiable {
    let id: String
    let profile: String
    let estimatedBytes: Int64?
    let observedAt: Date
    let availability: ChromeCacheAvailability
    var selected = false
}

/// Pure shared browser group composition, also used by inert Gallery examples.
struct ChromeCacheGroupRows: View {
    let rows: [ChromeCacheRow]
    var enabled = true
    let select: (String, Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            HStack {
                CategoryBadge(category: .browser)
                Text("Google Chrome").font(StillDesign.TypeStyle.section)
                Spacer()
                Text("Downloaded asset caches").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: StillDesign.Space.md) {
                    Toggle(isOn: Binding(get: { row.selected }, set: { select(row.id, $0) })) {
                        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                            Text(row.profile).font(.body.weight(.medium))
                            Text(availability(row.availability)).font(.caption).foregroundStyle(.secondary)
                            Text("Observed \(row.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox)
                        .accessibilityLabel("Chrome \(row.profile) downloaded asset cache")
                        .accessibilityIdentifier("chromeGroupSelection-" + row.profile)
                        .disabled(!enabled || row.availability != .eligible || row.estimatedBytes == nil)
                    Spacer(minLength: StillDesign.Space.sm)
                    Text(chromeBytes(row.estimatedBytes)).monospacedDigit().font(.callout)
                }
                if row.id != rows.last?.id { Divider() }
            }
        }
    }
    private func availability(_ state: ChromeCacheAvailability) -> String {
        switch state {
        case .eligible: "Cached images and files · Ready to review"
        case .empty: "No downloaded asset cache files"
        case .running: "Running · Close Chrome, then recheck"
        case .denied: "Access unavailable"
        case .unsupported: "Unsupported version or layout"
        case .unknown: "Ownership or size unknown"
        }
    }
}

struct ChromeCacheProtectionNotice: View {
    var body: some View {
        StatusRow(text: "Cookies, website and offline storage, passwords, saved addresses, history, downloads and open-tab/session data are excluded. Pages may load more slowly while caches refill.", symbol: "shield.checkered", role: .neutral)
    }
}

struct ChromeCachePermanenceNotice: View {
    var body: some View {
        StatusRow(text: "These cache files do not go to Trash and cannot be restored by Still. Caches may refill. Downloads and other personal files keep their separate Trash confirmation.", symbol: "exclamationmark.triangle", role: .caution)
    }
}

struct BrowserReviewView: View {
    @Bindable var model: ChromeCleanupModel
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "Browser caches", subtitle: "Clear downloaded images and files. Keep logins and browsing data.")
            ChromeCacheProtectionNotice()
            SummarySurface {
                HStack {
                    VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                        Text("Selected cache groups").font(.caption).foregroundStyle(.secondary)
                        Text(model.selectedCount == 0 ? "Nothing selected" : chromeBytes(model.estimatedBytes)).font(StillDesign.TypeStyle.value).monospacedDigit()
                    }
                    Spacer()
                    Text("\(model.selectedCount) groups · Permanent removal").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.inspectionEnabled {
                Text("Enable Chrome inspection to check recognized profile cache groups. This starts one manual check; Still will not close Chrome for you.").foregroundStyle(.secondary)
                Button("Enable Chrome inspection") { Task { await model.enableInspection() } }.disabled(!model.canEdit)
            } else {
                HStack {
                    Button("Recheck Chrome") { Task { await model.recheck() } }.disabled(!model.canEdit)
                    Button("Choose another Chrome location…") { Task { await model.chooseCustomLocation() } }.disabled(!model.canEdit)
                }
            }
            StatusRow(text: model.statusText, symbol: model.inspection?.unavailableReason == nil ? "info.circle" : "exclamationmark.triangle", role: model.inspection?.unavailableReason == nil ? .neutral : .caution, identifier: "chromeInspectionStatus")
            if model.isBusy { ProgressView("Checking Chrome…") }
            if let message = model.message { StatusRow(text: message, symbol: "info.circle", identifier: "chromeSelectionFeedback") }
            if let feedback = model.intentFeedback { StatusRow(text: feedback, symbol: "exclamationmark.triangle", role: .caution) }
            if !model.rows.isEmpty {
                SummarySurface { ChromeCacheGroupRows(rows: model.rows, enabled: model.canEdit, select: model.setSelected) }
            }
            DisclosureGroup("What gets removed?") {
                Text("Only downloaded asset cache groups recognized by the qualified Chrome version and profile mapping. No whole-profile deletion, GPU or code caches. Estimates are observations; eligible contents in the approved group can change before execution. Close Chrome and its helpers, then recheck. Still never force-quits a browser.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, StillDesign.Space.sm)
            }
        }
    }
}

struct ChromePlanSection: View {
    @Bindable var model: ChromeCleanupModel
    let onReview: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            CategorySelectionHeader(category: .browser, state: model.categoryState, title: "Browser caches",
                detail: "Permanently clear selected downloaded assets. Logins and browsing data stay protected; caches may refill.",
                size: chromeBytes(model.availableBytes), enabled: !model.eligibleGroups.isEmpty && model.canEdit, action: model.toggleCategory)
            if model.rows.isEmpty {
                StatusRow(text: model.statusText, symbol: "info.circle")
                Button(model.inspectionEnabled ? "Review browser caches" : "Set up Chrome inspection", action: onReview)
                    .disabled(!model.canEdit)
            } else {
                DisclosureGroup("Choose browsers & profiles", isExpanded: $expanded) {
                    ChromeCacheGroupRows(rows: model.rows, enabled: model.canEdit, select: model.setSelected)
                        .padding(.top, StillDesign.Space.md)
                }.padding(.leading, StillDesign.Space.xl)
                HStack {
                    Button("Review browser caches", action: onReview)
                    Button("Recheck Chrome") { Task { await model.recheck() } }.disabled(!model.canEdit)
                }.padding(.leading, StillDesign.Space.xl)
            }
            if let message = model.message { StatusRow(text: message, symbol: "info.circle") }
        }
    }
}

struct ChromeConfirmationSection: View {
    let approval: ChromeCacheApproval
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
            Text("Permanently clear Chrome asset caches").font(.headline)
            ChromeCachePermanenceNotice()
            ForEach(approval.groups) { group in
                HStack {
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text("Chrome · \(group.profileIdentifier)")
                        Text("Downloaded asset cache · Observed \(group.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(chromeBytes(group.estimatedBytes)).monospacedDigit()
                }
            }
            Text("Only these approved groups are included. Eligible cache contents may change before cleanup. If Chrome starts or scope conflicts are detected, unstarted work stops; no automatic retry runs.").font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("chromePermanentConfirmation")
    }
}

struct ChromeResultsSection: View {
    let result: ChromeCacheRun
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            Text("Chrome cache results").font(.headline)
            ForEach(Array(result.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                    HStack {
                        Text("Chrome · \(group.profileIdentifier)")
                        Spacer()
                        Text(group.status.rawValue.capitalized)
                    }
                    Text("\(group.removedFiles) cache files permanently removed · \(chromeBytes(group.removedBytes)) observed bytes").font(.caption).foregroundStyle(.secondary)
                    if let reason = group.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if result.unresolved { StatusRow(text: "Some browser cache outcomes are unresolved. Recorded results are retained; no cleanup will resume automatically.", symbol: "exclamationmark.triangle", role: .caution) }
            Text("Cache removal has no Trash recovery or Undo. Caches may refill. Removed-byte counts are separate from observed available disk space.").font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("chromeCleanupResults")
    }
}

private func chromeBytes(_ value: Int64?) -> String {
    guard let value else { return "Unknown size" }
    return value == 0 ? "0 bytes" : ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
}

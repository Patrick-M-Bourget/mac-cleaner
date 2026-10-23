import Foundation
import Observation
import StillCore
import SwiftUI

@MainActor @Observable final class SessionPlan {
    private(set) var draft = PlanDraft()
    private(set) var scans: [URL: ScanResult] = [:]
    private(set) var message: String?
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
        scans[scan.scope] = scan
    }
    func eligible(_ item: FileObservation, in scan: ScanResult) -> Bool {
        guard let downloads else { return false }
        return PlanDraft.canConsider(item, in: scan, downloads: downloads)
    }
    func set(_ item: FileObservation, in scan: ScanResult, selected: Bool) {
        if !selected { draft.remove(item.url.path + "|" + item.resourceID + "|moveToTrash") }
        else {
            guard let downloads else { return }
            do { try draft.select(item, in: scan, downloads: downloads); message = nil }
            catch { message = "This target is no longer eligible. Recheck its selected Downloads scope." }
        }
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func remove(_ target: PlannedTarget) {
        draft.remove(target.id)
        AppLifecycleController.shared.hasPendingPlan = draft.selectedCount > 0
    }
    func endSession() { draft.clear(); scans.removeAll(); AppLifecycleController.shared.hasPendingPlan = false }
}

struct LiveCleanupPlanView: View {
    @Bindable var selection: SessionPlan
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cleanup plan").font(.largeTitle.weight(.semibold))
            Text("\(selection.draft.selectedCount) files selected · \(ByteCountFormatter.string(fromByteCount: selection.draft.logicalBytes, countStyle: .decimal)) logical bytes across unique storage identities")
                .accessibilityIdentifier("liveSelectionSummary")
            Text("Move to Trash · Space stays occupied until Finder empties Trash. Selection changes the plan only; no cleanup is available in this slice.").foregroundStyle(.secondary)
            TextField("Search Downloads items", text: $search)
            ForEach(selection.draft.selected) { target in
                HStack {
                    Toggle(isOn: Binding(get: { true }, set: { if !$0 { selection.remove(target) } })) { Text(target.url.lastPathComponent) }
                        .accessibilityLabel("Selected \(target.url.lastPathComponent)")
                    Text(target.url.path).font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Eligible Downloads files").font(.headline)
            if selection.scans.isEmpty { Text("Choose and scan Downloads or a folder inside it to add exact files. Nothing is preselected.").foregroundStyle(.secondary) }
            ForEach(selection.rows.filter { search.isEmpty || $0.item.url.path.localizedCaseInsensitiveContains(search) }) { row in
                Toggle(isOn: Binding(get: { selection.draft.contains(row.item) }, set: { selection.set(row.item, in: row.scan, selected: $0) })) {
                    VStack(alignment: .leading) { Text(row.item.url.lastPathComponent); Text(row.item.url.path).font(.caption).foregroundStyle(.secondary) }
                }.accessibilityLabel("Select \(row.item.url.lastPathComponent)")
            }
            if let message = selection.message { Text(message).foregroundStyle(.secondary) }
            Text("Hidden search results keep their selections. Hardlink aliases are separate exact paths; their storage bytes count once.").font(.caption).foregroundStyle(.secondary)
            Button("Review cleanup") {}.disabled(true)
        }
    }
}

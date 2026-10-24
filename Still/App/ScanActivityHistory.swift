import SwiftUI
import Observation
import StillCore

@MainActor @Observable final class ScanActivityHistory {
    static let shared = ScanActivityHistory()
    var records: [ScanActivity]?
    var loadError: String?
    var recordingWarning: String?
    private var archive: GrowthHistoryStore?
    func store() throws -> GrowthHistoryStore {
        if let archive { return archive }
        let value = GrowthHistoryStore(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Growth", isDirectory: true))
        archive = value; return value
    }
    func begin() async -> UUID? {
        do { return try await store().recordingEpoch() }
        catch { recordingWarning = "This scan could not be saved to History. Current results and choices remain available."; return nil }
    }
    func record(_ activity: ScanActivity, epoch: UUID?) async {
        guard let epoch else { return }
        do {
            let saved = try await store().recordActivity(activity, expectedEpoch: epoch)
            if saved { recordingWarning = nil; records = try await store().activities() }
        } catch { recordingWarning = "This scan could not be saved to History. Current results and choices remain available." }
    }
    func load(maintain: Bool = true) async {
        do { records = try await HistoryLoadCoordinator.load(lifecycle: AppLifecycleController.shared) { mayMaintain in
                try await self.store().activities(maintain: maintain && mayMaintain)
            }; loadError = nil }
        catch { records = nil; loadError = "Scan history is unavailable. Recorded scan activity could not be read." }
    }
}

struct ScanActivitySummary: View {
    let activity: ScanActivity
    @Binding var expanded: Bool
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                Label(title, systemImage: "viewfinder").font(StillDesign.TypeStyle.section)
                Text(activity.completedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text(activity.locations.map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", "))
                DisclosureGroup("Scan details", isExpanded: $expanded) {
                    ForEach(activity.locations) { location in
                        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                            Text(location.path).textSelection(.enabled)
                            Text("Complete scope logical size: " + bytes(location.logicalBytes)).font(.callout)
                            Text("Complete scope allocated size: " + bytes(location.allocatedBytes)).font(.callout)
                        }.padding(.leading, StillDesign.Space.xl)
                    }
                }
                Text("Recorded observations, not reclaimable or released space.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var title: String {
        switch activity.outcome { case .complete: "Completed scan"; case .partial: "Partial scan"; case .stopped: "Stopped scan"; case .failed: "Failed scan" }
    }
    private func bytes(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "Unknown" }
}

struct HistoryActivityFilterControl: View {
    @Binding var selection: HistoryActivityFilter
    var body: some View {
        Picker("Activity", selection: $selection) {
            ForEach(HistoryActivityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("History activity filter")
    }
}

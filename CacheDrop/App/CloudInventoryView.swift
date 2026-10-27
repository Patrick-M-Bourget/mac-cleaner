import CacheDropCore
import SwiftUI

struct CloudInventoryView: View {
    let report: CloudInventoryReport
    @State private var evidenceExpanded = false

    var body: some View {
        SummarySurface {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            HStack(spacing: CacheDropDesign.Space.sm) { CategoryBadge(category: .cloud); Text("iCloud in this scan").font(CacheDropDesign.TypeStyle.section) }
            Text("\(report.isComplete ? "Completed selected-scope observation" : "Partial selected-scope observation") · \(report.observedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            Text("Identified local downloaded allocation: \(bytes(report.localAllocatedBytes)) · \(report.localItemCount) files")
                .monospacedDigit()
            if !report.isComplete {
                Text("Observed local allocated subtotal: \(bytes(report.observedLocalAllocatedBytes)) · Uninspected cloud allocation: Unknown")
                    .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            }
            Text("Cloud-only: \(report.cloudOnlyItemCount) files · \(bytes(report.cloudOnlyLogicalBytes)) logical size")
            Text("Cloud-only allocated bytes: \(bytes(report.cloudOnlyAllocatedBytes))")
                .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            if report.unknownStateCount > 0 { Text("\(report.unknownStateCount) identified iCloud files have unknown local/download state.") }
            if report.unknownMembershipCount > 0 { Text("iCloud membership unknown for \(report.unknownMembershipCount) file identities.") }
            if report.isComplete && report.items.isEmpty && report.unknownMembershipCount == 0 {
                Text("No iCloud files identified in this selected scope.").foregroundStyle(.secondary)
            }
            Text("Pinning: Unknown — not established by this scan").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            Text("Sync safety remains unverified. Logical sizes and local allocations are not promised savings. Local eviction is unavailable until the validation gate passes.")
                .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            if !report.items.isEmpty {
                Button {
                    evidenceExpanded.toggle()
                } label: {
                    Label("Review iCloud evidence", systemImage: evidenceExpanded ? "chevron.down" : "chevron.right")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(evidenceExpanded ? "Expanded" : "Collapsed")
                if evidenceExpanded {
                    LazyVStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                        ForEach(report.items) { item in
                            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                                Text(item.url.lastPathComponent).font(.subheadline.weight(.medium))
                                Text("Download metadata: \(state(item.cloud.downloadState)) · locality: \(item.previewAvailability.rawValue)")
                                Text("Upload complete: \(flag(item.cloud.uploaded)) · uploading: \(flag(item.cloud.uploading)) · downloading: \(flag(item.cloud.downloading))")
                                Text("Conflicts: \(flag(item.cloud.conflicts)) · Pinning: Unknown")
                            }.font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        }
    }

    private func flag(_ value: Bool?) -> String {
        guard let value else { return "Unknown" }
        return value ? "Yes" : "No"
    }
    private func state(_ value: CloudDownloadState) -> String {
        switch value {
        case .current: "Current local version reported"
        case .downloaded: "Downloaded version may be stale"
        case .notDownloaded: "Not downloaded"
        case .unknown: "Unknown"
        }
    }
    private func bytes(_ value: Int64?) -> String {
        guard let value else { return "Unknown" }
        return value < 1_000 ? "\(value) bytes" : ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
}

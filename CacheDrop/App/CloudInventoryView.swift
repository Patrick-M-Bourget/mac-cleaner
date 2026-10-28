import CacheDropCore
import SwiftUI

/// Overview's iCloud summary for a scanned folder: two plain lines (#312), plus why the total is Unknown (#331).
struct CloudInventoryView: View {
    let report: CloudInventoryReport

    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                HStack(spacing: CacheDropDesign.Space.sm) { CategoryBadge(category: .cloud); Text("iCloud in this scan").font(CacheDropDesign.TypeStyle.section) }
                if report.isComplete && report.items.isEmpty && report.unknownMembershipCount == 0 {
                    Text("No iCloud files in this folder.").foregroundStyle(.secondary)
                } else {
                    Text(report.localAllocatedBytes.map { (report.isComplete ? "" : "At least ") + bytes($0) + " of iCloud files are downloaded to this Mac · " + files(report.localItemCount) }
                         ?? files(report.localItemCount) + " from iCloud are downloaded to this Mac")
                        .monospacedDigit()
                    Text(files(report.cloudOnlyItemCount) + " only in iCloud, taking no space here.")
                        .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    // Why the row's total reads "Unknown": counts only, no per-file list (#331).
                    if let reason = report.unknownReason {
                        Text(reason).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("overviewCloudUnknownReason")
                    }
                }
            }
        }
    }

    private func files(_ count: Int) -> String { count == 1 ? "1 file" : "\(count) files" }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
}

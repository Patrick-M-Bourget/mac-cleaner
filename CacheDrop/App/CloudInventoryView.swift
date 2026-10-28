import CacheDropCore
import SwiftUI

/// Overview's iCloud summary for a scanned folder: two plain lines (#312).
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
                }
            }
        }
    }

    private func files(_ count: Int) -> String { count == 1 ? "1 file" : "\(count) files" }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
}

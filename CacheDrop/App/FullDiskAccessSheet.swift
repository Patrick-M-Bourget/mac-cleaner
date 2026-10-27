import AppKit
import CacheDropCore
import SwiftUI

/// The shared Full Disk Access explanation (#161), following the prototype's "Broader access is optional" sheet:
/// a badge and title, a two-line explanation, the coverage table, one note on how to turn it on, and two buttons.
/// Coming back from System Settings checks again by itself, and #124 rescans, so there is no "Check again".
struct FullDiskAccessSheet: View {
    let model: FullDiskAccessModel
    let close: () -> Void
    var body: some View {
        let granted = model.status == .granted
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            HStack(spacing: CacheDropDesign.Space.md) {
                CategoryBadge(symbol: "lock.shield", color: CacheDropDesign.blue)
                Text(FullDiskAccessGuide.title).font(CacheDropDesign.TypeStyle.sheet).accessibilityAddTraits(.isHeader)
                Spacer(minLength: CacheDropDesign.Space.md)
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.borderless)
                    .foregroundStyle(.secondary).accessibilityIdentifier("dismissFullDiskAccess")
            }
            Text(FullDiskAccessGuide.summary).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("fullDiskAccessSummary")
            RecommendationGroup {
                ForEach(Array(FullDiskAccessGuide.coverage(model.status).enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.horizontal, CacheDropDesign.Space.lg) }
                    HStack(spacing: CacheDropDesign.Space.md) {
                        Image(systemName: row.included ? "checkmark.circle" : "minus.circle")
                            .foregroundStyle(row.included ? StatusRole.success.color : StatusRole.neutral.color)
                            .frame(width: CacheDropDesign.Size.rowIcon).accessibilityHidden(true)
                        Text(row.title)
                        Spacer(minLength: CacheDropDesign.Space.md)
                        Text(row.value).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier(index == 0 ? "fullDiskAccessCoverage" : "fullDiskAccessSheetStatus")
                    }
                    .padding(.horizontal, CacheDropDesign.Space.lg).padding(.vertical, CacheDropDesign.Space.md)
                }
            }
            if !granted {
                StatusRow(text: FullDiskAccessGuide.howToTurnOn, identifier: "fullDiskAccessHowTo")
            }
            Divider()
            HStack(spacing: CacheDropDesign.Space.sm) {
                Spacer()
                if granted {
                    Button("Done", action: close).keyboardShortcut(.defaultAction).accessibilityIdentifier("closeFullDiskAccess")
                } else {
                    Button("Not now", action: close).keyboardShortcut(.cancelAction).accessibilityIdentifier("closeFullDiskAccess")
                    Button("Open System Settings") { model.openSettings() }.buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction).accessibilityIdentifier("openFullDiskAccessSettings")
                }
            }
        }
        .padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading)
        .task { await model.refresh() }
        // Coming back from System Settings: check again without being asked.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refresh() } }
    }
}

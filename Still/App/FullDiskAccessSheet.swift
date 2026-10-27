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
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            HStack(spacing: StillDesign.Space.md) {
                CategoryBadge(symbol: "lock.shield", color: StillDesign.blue)
                Text(FullDiskAccessGuide.title).font(StillDesign.TypeStyle.sheet).accessibilityAddTraits(.isHeader)
                Spacer(minLength: StillDesign.Space.md)
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.borderless)
                    .foregroundStyle(.secondary).accessibilityIdentifier("dismissFullDiskAccess")
            }
            Text(FullDiskAccessGuide.summary).font(StillDesign.TypeStyle.note).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("fullDiskAccessSummary")
            RecommendationGroup {
                ForEach(Array(FullDiskAccessGuide.coverage(model.status).enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.horizontal, StillDesign.Space.lg) }
                    HStack(spacing: StillDesign.Space.md) {
                        Image(systemName: row.included ? "checkmark.circle" : "minus.circle")
                            .foregroundStyle(row.included ? StatusRole.success.color : StatusRole.neutral.color)
                            .frame(width: StillDesign.Size.rowIcon).accessibilityHidden(true)
                        Text(row.title)
                        Spacer(minLength: StillDesign.Space.md)
                        Text(row.value).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier(index == 0 ? "fullDiskAccessCoverage" : "fullDiskAccessSheetStatus")
                    }
                    .padding(.horizontal, StillDesign.Space.lg).padding(.vertical, StillDesign.Space.md)
                }
            }
            if !granted {
                StatusRow(text: FullDiskAccessGuide.howToTurnOn, identifier: "fullDiskAccessHowTo")
            }
            Divider()
            HStack(spacing: StillDesign.Space.sm) {
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
        .padding(StillDesign.Space.xl).frame(width: StillDesign.Size.sheetNarrow).background(StillDesign.reading)
        .task { await model.refresh() }
        // Coming back from System Settings: check again without being asked.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refresh() } }
    }
}

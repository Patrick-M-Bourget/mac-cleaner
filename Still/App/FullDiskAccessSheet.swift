import AppKit
import StillCore
import SwiftUI

struct FullDiskAccessSheet: View {
    let model: FullDiskAccessModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            PageHeader(title: FullDiskAccessGuide.title, subtitle: FullDiskAccessGuide.summary)
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                ForEach(FullDiskAccessGuide.points, id: \.self) { point in StatusRow(text: point, symbol: "circle.fill") }
            }
            StatusRow(text: "Current state: " + (model.status.map(FullDiskAccessGuide.statusText) ?? "Checking…"),
                      symbol: "lock.shield", role: model.status == .granted ? .success : .neutral, identifier: "fullDiskAccessSheetStatus")
            if model.status != .granted {
                Text("In System Settings, turn on CacheDrop under Privacy & Security → Full Disk Access. If CacheDrop still shows Not granted, quit and reopen it.")
                    .font(StillDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Open System Settings") { model.openSettings() }.accessibilityIdentifier("openFullDiskAccessSettings")
                Button("Check again") { Task { await model.refresh() } }
                Spacer()
                Button(model.status == .granted ? "Done" : "Continue with limited access", action: close)
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("closeFullDiskAccess")
            }
        }
        .padding(StillDesign.Space.xl).frame(width: StillDesign.Size.sheetNarrow).background(StillDesign.reading)
        .task { await model.refresh() }
        // Coming back from System Settings: check again without being asked.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refresh() } }
    }
}

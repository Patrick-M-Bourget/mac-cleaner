import CacheDropCore
import SwiftUI

/// Optional system access, using the same guidance and probe as the contextual sheet (#527).
struct SystemAccessView: View {
    @State private var model = FullDiskAccessModel()
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "System access", subtitle: "Optional · CacheDrop works without it")
            HStack(spacing: CacheDropDesign.Space.md) {
                Label("Full Disk Access", systemImage: "lock.shield").font(CacheDropDesign.TypeStyle.section)
                Spacer(minLength: CacheDropDesign.Space.md)
                Text(model.status.map(FullDiskAccessGuide.statusText) ?? "Checking…")
                    .foregroundStyle(model.status == .granted ? StatusRole.success.color : StatusRole.neutral.color)
                    .accessibilityLabel("Full Disk Access · " + (model.status.map(FullDiskAccessGuide.statusText) ?? "Checking…"))
                    .accessibilityIdentifier("fullDiskAccessStatus")
            }
            FullDiskAccessDetails(status: model.status)
            if model.status != .granted {
                // A page body's action is a regular capsule (Decision 65 rule 2), as in the Full Disk Access sheet.
                Button("Open System Settings") { model.openSettings() }.accessibilityIdentifier("systemAccessOpenSettings")
            }
        }.task { await model.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refresh() } }
    }
}

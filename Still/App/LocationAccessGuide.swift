import AppKit
import Observation
import StillCore
import SwiftUI

/// Contextual education only; this view does not inspect folders or request permissions.
struct LocationAccessGuide: View {
    @Binding var expanded: Bool

    var body: some View {
        DisclosureGroup("About folder access", isExpanded: $expanded) {
            SettingsRow(title: "Your chosen folders", detail: "Still can inspect folders you explicitly choose. macOS may restrict protected locations; uninspected bytes remain unknown.") {
                FullDiskAccessSetting()
            }
        }
        .padding(.leading, StillDesign.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Full Disk Access state for an access surface, checked when it is shown. Catalog scans probe too, the one at
/// launch included (`CatalogCleanupModel.scan`). Checking never asks for access (`FullDiskAccessProbe`).
@MainActor @Observable final class FullDiskAccessModel {
    /// Nil until the first check.
    private(set) var status: FullDiskAccessStatus?
    private let detector: (any FullDiskAccessDetecting)?

    /// The probe runs against the catalog's home, so a debug UI test's fixture home stands in for the real one.
    init(detector: (any FullDiskAccessDetecting)? = CatalogCleanupModel.home.map { FullDiskAccessProbe(home: $0) }) { self.detector = detector }

    func refresh() async {
        guard let detector else { status = .unknown; return }
        status = await Task.detached { detector.status() }.value
    }
    /// Only ever from a button the user pressed.
    func openSettings() { NSWorkspace.shared.open(FullDiskAccessGuide.settingsURL) }
}

/// The Locations & access row: current state plus the shared explanation.
struct FullDiskAccessSetting: View {
    @State private var model = FullDiskAccessModel()
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
            StatusRow(text: "Full Disk Access · " + (model.status.map(FullDiskAccessGuide.statusText) ?? "Checking…"),
                      symbol: "lock.shield", role: model.status == .granted ? .success : .neutral, identifier: "fullDiskAccessStatus")
            Text("Optional. Broad access can include sensitive Mail and Messages data.")
                .font(StillDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FullDiskAccessLink(model: model)
        }.task { await model.refresh() }
    }
}

/// A row for something Still couldn't read, such as a rule that declares `requiresFullDiskAccess`.
/// It always offers the same explanation.
struct NotAccessibleRow: View {
    let title: String
    var detail = "macOS protects this location. You can continue without it."
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
            HStack {
                Text(title).font(StillDesign.TypeStyle.section)
                Spacer()
                Text("Not accessible").font(StillDesign.TypeStyle.note).foregroundStyle(.secondary)
            }
            Text(detail).font(StillDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FullDiskAccessLink(title: "Review access options")
        }.accessibilityElement(children: .contain)
    }
}

/// Opens the shared Full Disk Access explanation. Every "not accessible" place uses this.
struct FullDiskAccessLink: View {
    var title = "Learn about broader access"
    var model: FullDiskAccessModel?
    @State private var showing = false
    var body: some View {
        Button(title, systemImage: "lock.shield") { showing = true }
            .buttonStyle(.link)
            .accessibilityIdentifier("fullDiskAccessLink")
            .sheet(isPresented: $showing) { FullDiskAccessSheet(model: model ?? FullDiskAccessModel()) { showing = false } }
    }
}

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
                Text("In System Settings, turn on Still under Privacy & Security → Full Disk Access. If Still still shows Not granted, quit and reopen it.")
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

import SwiftUI

@main
struct StillApp: App {
    var body: some Scene {
        WindowGroup("Still") {
            WorkspaceView()
                .frame(minWidth: 900, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 760)
    }
}

private enum Destination: String, CaseIterable, Identifiable {
    case alerts = "Storage alerts"
    case overview = "Overview", plan = "Cleanup plan", history = "History", locations = "Locations & access"
    var id: String { rawValue }
    var shortcut: KeyEquivalent {
        switch self {
        case .alerts: "5"
        case .overview: "1"
        case .plan: "2"
        case .history: "3"
        case .locations: "4"
        }
    }
    var symbol: String {
        switch self {
        case .alerts: "bell"
        case .overview: "internaldrive"
        case .plan: "checklist"
        case .history: "clock"
        case .locations: "folder.badge.gearshape"
        }
    }
}

private struct FixtureItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let size: String
    static let downloads = [
        FixtureItem(id: "trip", name: "Summer trip.mov", path: "Downloads/Trips/Summer trip.mov", size: "1.6 GB"),
        FixtureItem(id: "installer", name: "Editor installer.dmg", path: "Downloads/Editor installer.dmg", size: "420 MB"),
        FixtureItem(id: "guide", name: "Camera guide.pdf", path: "Downloads/Camera guide.pdf", size: "8 MB")
    ]
}

private struct WorkspaceView: View {
    @StateObject private var alerts = StorageAlertsController()
    @State private var destination = Destination.overview
    @State private var inspecting = false
    @State private var inspected = FixtureItem.downloads[0]
    @State private var appearance = "Automatic"
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Still", systemImage: "sparkle").font(.title2.weight(.semibold)).padding(.bottom, 24)
                Text("Storage").font(.caption).foregroundStyle(.secondary)
                ForEach(Destination.allCases.filter { $0 != .locations && $0 != .alerts }) { navigation($0) }
                Text("Settings").font(.caption).foregroundStyle(.secondary).padding(.top, 20)
                navigation(.locations)
                if StorageAlertsController.futureEnabled { navigation(.alerts) }
                Spacer()
                Text("M0 · Fixture workspace").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 200)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Synthetic data — no personal files accessed", systemImage: "testtube.2")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if inspecting { inspection }
                        else {
                            switch destination {
                            case .alerts: StorageAlertsView(controller: alerts)
                            case .overview: overview
                            case .plan: plan
                            case .history: history
                            case .locations: locations
                            }
                        }
                    }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(for: .stillAlertOpened)) { _ in destination = .overview; inspecting = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await alerts.activated() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in Task { await alerts.activated() } }
        .toolbar {
            Picker("Appearance", selection: $appearance) {
                Text("Automatic").tag("Automatic")
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
            }.frame(width: 140).accessibilityLabel("Appearance")
        }
        .preferredColorScheme(appearance == "Automatic" ? nil : appearance == "Dark" ? .dark : .light)
    }

    private func navigation(_ value: Destination) -> some View {
        Button {
            destination = value
            inspecting = false
        } label: {
            Label(value.rawValue, systemImage: value.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7).padding(.horizontal, 8)
                .background(destination == value ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(value.rawValue)
            .keyboardShortcut(value.shortcut, modifiers: .command)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Your storage", "Understand what is stored locally before choosing what to clean.")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("42.8 GB").font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("available of 512 GB").foregroundStyle(.secondary)
                }
                ProgressView(value: 469.2, total: 512).tint(.blue)
                Text("Synthetic startup volume · Fixture observation").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Storage findings").font(.title3.weight(.semibold))
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.circle.fill").font(.title).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Downloads").font(.headline)
                    Text("3 example files · 2.028 GB logical size").foregroundStyle(.secondary)
                    Text("Moving files to Trash keeps their space occupied until Trash is emptied.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review Downloads") { inspecting = true }
            }
            Text("Other storage categories are introduced as their adapters are validated. This build displays fixtures only.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var inspection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Back to Overview", systemImage: "chevron.left") { inspecting = false; destination = .overview }
            heading("Downloads inspection", "Names inspect files. Selection arrives in the next milestone.")
            ForEach(FixtureItem.downloads) { item in
                HStack {
                    Button { inspected = item } label: {
                        Label(item.name, systemImage: "doc").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Inspect \(item.name)")
                    Text(item.size).monospacedDigit().foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                Divider()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(inspected.name).font(.headline)
                Text(inspected.path).textSelection(.enabled)
                Text("Logical size: \(inspected.size)")
                Text("Example ordinary file · Proposed action: Move to Trash. No action is enabled in this fixture workspace.")
                    .foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("Nothing selected").foregroundStyle(.secondary)
                Spacer()
                Button("View cleanup plan") { destination = .plan; inspecting = false }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Cleanup plan", "Review categories and their consequences before any action.")
            Text("Selected for Trash").font(.headline)
            Text("Nothing selected").font(.title2).foregroundStyle(.secondary)
            Text("Space remains occupied until Finder empties Trash.").foregroundStyle(.secondary)
            Divider()
            Label("Downloads · 3 eligible fixture files · 2.028 GB", systemImage: "arrow.down.circle").font(.headline)
            Button {
                expanded.toggle()
            } label: {
                Label("Choose items", systemImage: expanded ? "chevron.down" : "chevron.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(spacing: 12) {
                    ForEach(FixtureItem.downloads) { item in
                        HStack { Text(item.name); Spacer(); Text(item.size).foregroundStyle(.secondary) }
                    }
                }
            }
            Text("Selection and cleanup are unavailable in this native-shell milestone.").font(.callout).foregroundStyle(.secondary)
            Button("Review cleanup") {}.disabled(true)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("History", "Completed cleanup results will appear here.")
            Label("No cleanup has run", systemImage: "clock").font(.title3)
            Text("This fixture workspace cannot modify files.").foregroundStyle(.secondary)
        }
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Locations & access", "Review scan coverage and access in one place.")
            Label("Downloads · Synthetic fixture", systemImage: "folder")
            Text("No folders have been opened and no permissions are requested. User-selected folder scanning is a later ticket.").foregroundStyle(.secondary)
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

import AppKit
import SwiftUI
import StillCore

/// Shared native presentation vocabulary. See docs/DESIGN-SYSTEM.md before adding UI.
enum StillDesign {
    enum Space { static let xs: CGFloat = 4; static let sm: CGFloat = 8; static let md: CGFloat = 12; static let lg: CGFloat = 16; static let xl: CGFloat = 24; static let page: CGFloat = 32 }
    enum Radius { static let row: CGFloat = 8; static let surface: CGFloat = 12 }
    enum TypeStyle { static let page = Font.system(size: 26, weight: .medium); static let value = Font.system(size: 24, weight: .medium); static let section = Font.headline.weight(.medium) }
    static var reading: Color { Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1) : .white }) }
    static var summary: Color { Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.135, green: 0.135, blue: 0.15, alpha: 1) : NSColor(srgbRed: 0.965, green: 0.968, blue: 0.976, alpha: 1) }) }
    static func files(_ count: Int) -> String { "\(count) \(count == 1 ? "file" : "files")" }
    static var capacityFill: Color { Color(nsColor: .secondaryLabelColor) }
    static var capacityTrack: Color { Color(nsColor: .quaternaryLabelColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
}
enum StorageCategory {
    case cloud, developer, downloads, browser, managed
    var color: Color { switch self { case .cloud: .blue; case .developer: .purple; case .downloads: .orange; case .browser: .teal; case .managed: .indigo } }
    var symbol: String { switch self { case .cloud: "icloud"; case .developer: "hammer"; case .downloads: "shippingbox"; case .browser: "globe"; case .managed: "square.stack.3d.up" } }
}
private struct OpaqueChromeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var stillOpaqueChrome: Bool { get { self[OpaqueChromeKey.self] } set { self[OpaqueChromeKey.self] = newValue } }
}
enum ChromeRole { case chrome, sidebar }
struct ChromeSurface: View {
    var role: ChromeRole = .chrome
    @Environment(\.colorScheme) private var appearance
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.stillOpaqueChrome) private var forcedOpaque
    var body: some View {
        Group {
            if role == .sidebar && appearance == .light { Color.white }
            else if reduced || forcedOpaque { Color(nsColor: .windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
        }
    }
}
struct CategoryBadge: View {
    let category: StorageCategory
    var body: some View {
        Image(systemName: category.symbol).font(.system(size: 16, weight: .regular))
            .foregroundStyle(category.color).frame(width: 32, height: 32)
            .background(category.color.opacity(0.10), in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
            .accessibilityHidden(true)
    }
}
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            Text(title).font(StillDesign.TypeStyle.page)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct SummarySurface<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(StillDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            .background(StillDesign.summary, in: RoundedRectangle(cornerRadius: StillDesign.Radius.surface))
            .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.surface).strokeBorder(StillDesign.separator, lineWidth: contrast == .increased ? 1 : 0.5) }
    }
}
struct SelectionSummary: View {
    let value: String
    let detail: String
    var identifier = ""
    var body: some View {
        SummarySurface {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    Text("Selected for Trash").font(.caption).foregroundStyle(.secondary)
                    Text(value).font(StillDesign.TypeStyle.value).monospacedDigit()
                }
                Spacer(minLength: StillDesign.Space.lg)
                Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing).accessibilityIdentifier(identifier)
            }
        }
    }
}
enum StatusRole {
    case neutral, success, caution, failure
    var color: Color { switch self { case .neutral: .secondary; case .success: .green; case .caution: .orange; case .failure: .red } }
}
struct StatusRow: View {
    let text: String
    var symbol = "info.circle"
    var role: StatusRole = .neutral
    var identifier: String = ""
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(identifier) } icon: { Image(systemName: symbol).foregroundStyle(role.color) }
            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct SettingsRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
            Text(title).font(StillDesign.TypeStyle.section)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            content()
        }.padding(.vertical, StillDesign.Space.sm).frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct FindingRow<Accessory: View>: View {
    let category: StorageCategory
    let title: String
    let detail: String
    var consequence: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    var body: some View {
        HStack(alignment: .top, spacing: StillDesign.Space.lg) {
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                Text(title).font(StillDesign.TypeStyle.section)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if let consequence { Text(consequence).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }.padding(.vertical, StillDesign.Space.md)
    }
}
struct EmptyState: View {
    let title: String
    let detail: String
    var symbol = "tray"
    var body: some View {
        HStack(alignment: .top, spacing: StillDesign.Space.lg) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                Text(title).font(StillDesign.TypeStyle.section)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, StillDesign.Space.xl)
    }
}
struct ActionStrip<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: StillDesign.Space.lg) {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: StillDesign.Space.sm)
                actions()
            }.padding(.horizontal, StillDesign.Space.page).padding(.vertical, StillDesign.Space.lg)
        }.background(StillDesign.reading)
    }
}
struct CapacityMeter: View {
    let available: Int64?
    let total: Int64?
    var compact = false
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            if let available, let total, total > 0, available >= 0, available <= total {
                if compact { Text("\(bytes(available)) available of \(bytes(total))").font(.caption).foregroundStyle(.secondary) }
                else {
                    HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.sm) {
                        Text(bytes(available)).font(.system(size: 34, weight: .medium)).monospacedDigit()
                        Text("available of \(bytes(total))").foregroundStyle(.secondary)
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StillDesign.capacityTrack)
                        Capsule().fill(StillDesign.capacityFill).frame(width: geometry.size.width * CGFloat(Double(total - available) / Double(total)))
                    }
                }.frame(height: 4).accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bytes(available)) available of \(bytes(total))")
            } else { Text("Capacity not observed").font(compact ? .caption : .callout).foregroundStyle(.secondary) }
        }
    }
}
struct StillSidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, StillDesign.Space.sm).padding(.horizontal, StillDesign.Space.sm)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MacroCategoryCheckbox: NSViewRepresentable {
    let state: CategorySelectionState
    let label: String
    let enabled: Bool
    let action: () -> Void
    var identifier = "downloadsCategorySelection"
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: label, target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ view: NSButton, context: Context) {
        context.coordinator.action = action
        view.title = label; view.isEnabled = enabled
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel(label)
        view.state = state == .checked ? .on : state == .mixed ? .mixed : .off
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
}


/// Native first-responder restoration is explicit and one-shot after a sheet closes.
struct ReviewCleanupButton: NSViewRepresentable {
    let enabled: Bool
    let focusRequest: Int
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> FocusButton {
        let view = FocusButton(title: "Review cleanup", target: context.coordinator, action: #selector(Coordinator.clicked))
        view.bezelStyle = .rounded
        view.bezelColor = .controlAccentColor
        view.setAccessibilityLabel("Review cleanup")
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ view: FocusButton, context: Context) {
        view.isEnabled = enabled
        view.bezelColor = enabled ? .controlAccentColor : nil
        context.coordinator.action = action
        if context.coordinator.appliedFocusRequest != focusRequest {
            context.coordinator.appliedFocusRequest = focusRequest
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window?.attachedSheet == nil else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        var appliedFocusRequest = 0
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
    @MainActor final class FocusButton: NSButton {
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if [" ", "\r"].contains(event.charactersIgnoringModifiers ?? ""), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                performClick(nil)
            } else { super.keyDown(with: event) }
        }
    }
}

struct InspectableItemRow<Selection: View>: View {
    let name: String
    let detail: String
    let size: String
    let symbol: String
    let inspected: Bool
    let inspect: () -> Void
    @ViewBuilder var selection: () -> Selection
    var body: some View {
        HStack(alignment: .center, spacing: StillDesign.Space.md) {
            selection()
            Button(action: inspect) {
                HStack(spacing: StillDesign.Space.md) {
                    Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text(name).foregroundStyle(.primary)
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(size).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Inspect " + name)
        }.padding(StillDesign.Space.md)
            .background(inspected ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
    }
}

/// Enforce the outer-window minimum independently of a destination's intrinsic content size.
struct NativeWindowContract: NSViewRepresentable {
    func makeNSView(context: Context) -> ContractView { ContractView() }
    func updateNSView(_ nsView: ContractView, context: Context) {}
    @MainActor final class ContractView: NSView {
        private var applied = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !applied else { return }
            applied = true
            DispatchQueue.main.async {
                guard let screen = window.screen ?? NSScreen.main else { return }
                var visible = screen.visibleFrame
                var requested = window.frame
                #if DEBUG
                // Inject only an available-frame boundary; never change macOS display settings.
                if ProcessInfo.processInfo.arguments.contains("--design-constrained-screen") {
                    visible.size.width = min(visible.width, 1024)
                    visible.size.height = min(visible.height, 720)
                }
                if ProcessInfo.processInfo.arguments.contains("--design-minimum") {
                    requested.size = NSSize(width: 900, height: 640)
                } else if ProcessInfo.processInfo.arguments.contains("--design-initial-size") {
                    requested.size = NSSize(width: 1120, height: 760)
                }
                #endif
                let minimum = NSSize(width: min(900, visible.width), height: min(640, visible.height))
                window.minSize = minimum
                let size = NSSize(width: max(minimum.width, min(requested.width, visible.width)), height: max(minimum.height, min(requested.height, visible.height)))
                let origin = NSPoint(x: min(max(requested.minX, visible.minX), visible.maxX - size.width), y: min(max(requested.minY, visible.minY), visible.maxY - size.height))
                let fitted = NSRect(origin: origin, size: size)
                if window.frame != fitted { window.setFrame(fitted, display: true) }
            }
        }
    }
}

/// Bounded preliminary evidence; never offers selection or execution controls.
struct ScanProgressSummary: View {
    let inspectedEntries: Int
    let logicalSubtotal: String
    let recentNames: [String]
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                ProgressView("Reading file metadata…")
                StatusRow(text: "\(inspectedEntries) entries inspected so far · Preliminary observations", identifier: "scanProgressSummary")
                Text("Known logical subtotal: \(logicalSubtotal) · Coverage incomplete")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(recentNames.prefix(5).enumerated()), id: \.offset) { _, name in
                    Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }
}

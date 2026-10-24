import AppKit
import SwiftUI
import StillCore

/// Shared native presentation vocabulary. See docs/DESIGN-SYSTEM.md before adding UI.
enum StillDesign {
    enum Space { static let xs: CGFloat = 4; static let sm: CGFloat = 8; static let md: CGFloat = 12; static let lg: CGFloat = 16; static let xl: CGFloat = 24; static let page: CGFloat = 32 }
    enum Radius { static let row: CGFloat = 8; static let surface: CGFloat = 12 }
    enum TypeStyle { static let page = Font.system(size: 26, weight: .medium); static let value = Font.system(size: 22, weight: .medium); static let section = Font.system(size: 13, weight: .medium) }
    /// Reference colours belong here, never in individual screens. Keep system text/focus colours.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static var reading: Color { adaptive(light: 0xFFFFFF, dark: 0x171719) }
    static var summary: Color { adaptive(light: 0xF7F8FA, dark: 0x232328) }
    static var sidebar: Color { adaptive(light: 0xFFFFFF, dark: 0x242428) }
    static var selection: Color { adaptive(light: 0xE5EDFA, dark: 0x353E51) }
    static var highlight: Color { adaptive(light: 0xFFFFFF, dark: 0xFFFFFF).opacity(0.08) }
    static var blue: Color { adaptive(light: 0x0877ED, dark: 0x60A9FF) }
    static var purple: Color { adaptive(light: 0x9360D8, dark: 0xB290ED) }
    static var teal: Color { adaptive(light: 0x349A9B, dark: 0x61C3C2) }
    static var orange: Color { adaptive(light: 0xBD7527, dark: 0xE2A35E) }
    static func files(_ count: Int) -> String { "\(count) \(count == 1 ? "file" : "files")" }
    static var capacityFill: Color { adaptive(light: 0x969BA7, dark: 0x858997) }
    static var capacityTrack: Color { adaptive(light: 0xECEEF2, dark: 0x33343D) }
    static var separator: Color { Color(nsColor: .separatorColor) }
}
enum StorageCategory {
    case cloud, developer, downloads, browser, managed
    var color: Color { switch self { case .cloud: StillDesign.blue; case .developer: StillDesign.purple; case .downloads: StillDesign.orange; case .browser: StillDesign.teal; case .managed: .indigo } }
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
            else if reduced || forcedOpaque { role == .sidebar ? StillDesign.sidebar : StillDesign.summary }
            else {
                Rectangle().fill(.regularMaterial)
                    .overlay { if role == .sidebar { StillDesign.sidebar.opacity(0.65) } }
                    .overlay { LinearGradient(colors: [StillDesign.highlight, .clear], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }
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
            Text(title).font(StillDesign.TypeStyle.page).tracking(-0.6)
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
    var consequence: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
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
        if let consequence { Text(consequence).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
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
/// One quiet review group: category colors identify storage, never cleanup safety.
struct RecommendationGroup<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .background(StillDesign.reading, in: RoundedRectangle(cornerRadius: StillDesign.Radius.surface))
            .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.surface).strokeBorder(StillDesign.separator, lineWidth: contrast == .increased ? 1 : 0.5) }
    }
}
struct StorageReviewRow: View {
    let category: StorageCategory
    let title: String
    let detail: String
    let value: String
    let meaning: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var identifier = ""
    var body: some View {
        Group {
        if let action {
            Button(action: action) { contents }.buttonStyle(.plain)
                .accessibilityLabel(actionTitle ?? title)
                .accessibilityValue("\(title) · \(detail) · \(value) · \(meaning)")
        }
        else {
            contents.accessibilityElement(children: .combine).accessibilityLabel(title)
                .accessibilityValue("\(detail) · \(value) · \(meaning)")
        }
        }.accessibilityIdentifier(identifier)
    }
    private var contents: some View {
        HStack(spacing: StillDesign.Space.lg) {
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                Text(title).font(StillDesign.TypeStyle.section)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: StillDesign.Space.xs) {
                Text(value).font(StillDesign.TypeStyle.section).monospacedDigit()
                Text(meaning).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.multilineTextAlignment(.trailing)
            if action != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }.padding(StillDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
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
        }.background(StillDesign.reading).controlSize(.large).buttonBorderShape(.capsule)
    }
}
struct CapacityMeter: View {
    let available: Int64?
    let total: Int64?
    var compact = false
    var showsValue = true
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            if let available, let total, total > 0, available >= 0, available <= total {
                if compact { Text("\(bytes(available)) available of \(bytes(total))").font(.caption).foregroundStyle(.secondary) }
                else if showsValue {
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
                }.frame(height: compact ? 4 : 8).accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bytes(available)) available of \(bytes(total))")
            } else { Text("Capacity not observed").font(compact ? .caption : .callout).foregroundStyle(.secondary) }
        }
    }
}

struct VolumeSummary: View {
    let available: Int64?
    let total: Int64?
    let observation: String
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
                HStack(spacing: StillDesign.Space.md) {
                    Image(systemName: "internaldrive").font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).background(StillDesign.reading.gradient, in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
                        .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.row).strokeBorder(StillDesign.separator, lineWidth: 0.5) }
                        .accessibilityHidden(true)
                    Text("This Mac · Startup volume").font(StillDesign.TypeStyle.section)
                    Spacer(minLength: StillDesign.Space.sm)
                    if let available, let total, total > 0, available >= 0, available <= total {
                        VStack(alignment: .trailing, spacing: StillDesign.Space.xs) {
                            Text(ByteCountFormatter.string(fromByteCount: available, countStyle: .decimal)).font(StillDesign.TypeStyle.value).monospacedDigit()
                            Text("available of " + ByteCountFormatter.string(fromByteCount: total, countStyle: .decimal)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                CapacityMeter(available: available, total: total, showsValue: false)
                Text(observation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
struct StillSidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var accent: Color = StillDesign.blue
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label { Text(title).foregroundStyle(selected ? .primary : .secondary) } icon: { Image(systemName: symbol).foregroundStyle(accent) }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, StillDesign.Space.sm).padding(.horizontal, StillDesign.Space.sm)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: StillDesign.Radius.row).fill(StillDesign.selection)
                            .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.row).fill(LinearGradient(colors: [StillDesign.highlight, .clear], startPoint: .top, endPoint: .bottom)) }
                            .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.row).strokeBorder(StillDesign.highlight, lineWidth: 1) }
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MacroCategoryCheckbox: View {
    let state: CategorySelectionState
    let label: String
    let enabled: Bool
    let action: () -> Void
    var identifier = "downloadsCategorySelection"
    var showsTitle = true
    var body: some View {
        NativeCategoryCheckbox(state: state, label: label, enabled: enabled, action: action,
            identifier: identifier, showsTitle: showsTitle).disabled(!enabled)
    }
}

private struct NativeCategoryCheckbox: NSViewRepresentable {

    let state: CategorySelectionState
    let label: String
    let enabled: Bool
    let action: () -> Void
    var identifier = "downloadsCategorySelection"
    var showsTitle = true
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: label, target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ view: NSButton, context: Context) {
        context.coordinator.action = action
        view.title = showsTitle ? label : ""; view.isEnabled = enabled && context.environment.isEnabled
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

/// Selection stays on the native checkbox; the badge/title never become extra toggles.
struct CategorySelectionHeader: View {
    let category: StorageCategory
    let state: CategorySelectionState
    let title: String
    let detail: String
    let size: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: StillDesign.Space.md) {
            MacroCategoryCheckbox(state: state, label: title, enabled: enabled, action: action, showsTitle: false)
                .fixedSize().padding(.top, StillDesign.Space.sm)
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                Text(title).font(StillDesign.TypeStyle.section)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(size).font(.callout).monospacedDigit().fixedSize()
        }
    }
}

struct AppBrand: View {
    var body: some View {
        HStack(spacing: StillDesign.Space.md) {
            Image(systemName: "square.3.layers.3d").foregroundStyle(.white).font(.system(size: 17))
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: [Color(red: 0.565, green: 0.741, blue: 1), Color(red: 0.329, green: 0.518, blue: 0.910), Color(red: 0.455, green: 0.427, blue: 0.882)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
                .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.row).strokeBorder(.white.opacity(0.3), lineWidth: 0.5) }
                .accessibilityHidden(true)
            Text("Still").font(.system(size: 17, weight: .medium)).tracking(-0.4)
        }
    }
}


/// Native first-responder restoration is explicit and one-shot after a sheet closes.
struct ReviewCleanupButton: View {
    let enabled: Bool
    let focusRequest: Int
    let action: () -> Void
    var body: some View {
        NativeReviewCleanupButton(enabled: enabled, focusRequest: focusRequest, action: action)
            .disabled(!enabled)
    }
}

private struct NativeReviewCleanupButton: NSViewRepresentable {
    let enabled: Bool
    let focusRequest: Int
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> FocusButton {
        let view = FocusButton(title: "Review cleanup", target: context.coordinator, action: #selector(Coordinator.clicked))
        view.bezelStyle = .rounded
        view.controlSize = .large
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
    #if DEBUG
    var onCaptureFit: (() -> Void)? = nil
    #endif
    func makeNSView(context: Context) -> ContractView {
        let view = ContractView()
        #if DEBUG
        view.onCaptureFit = onCaptureFit
        #endif
        return view
    }
    func updateNSView(_ nsView: ContractView, context: Context) {}
    @MainActor final class ContractView: NSView {
        private var applied = false
        #if DEBUG
        var onCaptureFit: (() -> Void)?
        private weak var captureWindow: NSWindow?
        @objc private func captureWindowUpdated(_ notification: Notification) {
            guard !applied, let window = captureWindow,
                  notification.object as? NSWindow === window,
                  NSApp.isActive, window.isKeyWindow, window.isVisible else { return }
            // Remove before setFrame: fitting can itself generate native update events.
            NotificationCenter.default.removeObserver(self, name: NSWindow.didUpdateNotification, object: window)
            captureWindow = nil
            applied = true
            fit(window)
        }
        #endif
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !applied else { return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: {
                ["--design-minimum", "--design-initial-size"].contains($0)
            }) {
                if captureWindow !== window {
                    if let previous = captureWindow {
                        NotificationCenter.default.removeObserver(self, name: NSWindow.didUpdateNotification, object: previous)
                    }
                    captureWindow = window
                    NotificationCenter.default.addObserver(self, selector: #selector(captureWindowUpdated(_:)), name: NSWindow.didUpdateNotification, object: window)
                }
                return
            }
            #endif
            applied = true
            DispatchQueue.main.async { self.fit(window) }
        }
        private func fit(_ window: NSWindow) {
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
                // Use approved capture presets rather than a fluctuating maximum height.
                // The normal production fit below continues to use the actual window frame.
                requested.size = NSSize(width: 1120, height: visible.height >= 760 ? 760 : 640)
            }
            #endif
            let minimum = NSSize(width: min(900, visible.width), height: min(640, visible.height))
            window.minSize = minimum
            let size = NSSize(width: max(minimum.width, min(requested.width, visible.width)), height: max(minimum.height, min(requested.height, visible.height)))
            var origin = NSPoint(x: min(max(requested.minX, visible.minX), visible.maxX - size.width), y: min(max(requested.minY, visible.minY), visible.maxY - size.height))
            #if DEBUG
            // Explicit captures use the visible top-left corner, independent of native
            // restored/cascaded positions. Ordinary launches retain their fitted origin.
            if ProcessInfo.processInfo.arguments.contains(where: {
                ["--design-minimum", "--design-initial-size"].contains($0)
            }) { origin = NSPoint(x: visible.minX, y: visible.maxY - size.height) }
            #endif
            let fitted = NSRect(origin: origin, size: size)
            if window.frame != fitted { window.setFrame(fitted, display: true) }
            #if DEBUG
            // Capture controls become visible only after this launch's explicit fit.
            // Their layout was retained while hidden; ordinary launches are unaffected.
            if ProcessInfo.processInfo.arguments.contains(where: {
                ["--design-minimum", "--design-initial-size"].contains($0)
            }) { self.onCaptureFit?() }
            #endif
        }
        #if DEBUG
        deinit { NotificationCenter.default.removeObserver(self) }
        #endif
    }
}

/// Bounded preliminary evidence; never offers selection or execution controls.
struct ScanProgressSummary: View {
    let inspectedEntries: Int
    let logicalSubtotal: String
    let recentNames: [String]
    var phaseMessage = "Reading file metadata…"
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                HStack(spacing: StillDesign.Space.sm) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(phaseMessage).accessibilityIdentifier("scanPhase")
                }
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

/// Shared current-build scope guidance; the shortcut still requires native folder approval.
struct CleanupScopeNotice: View {
    var enabled = true
    var compact = false
    let chooseDownloads: () -> Void
    var body: some View {
        if compact {
            HStack(spacing: StillDesign.Space.md) {
                Text("Cleanup currently supports files in Downloads only. Other folders are inspection only.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("cleanupScopeNotice")
                Button("Choose Downloads…", action: chooseDownloads).disabled(!enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                StatusRow(text: "Cleanup currently supports files in Downloads only. Other folders are inspection only.", symbol: "info.circle", identifier: "cleanupScopeNotice")
                Button("Choose Downloads…", action: chooseDownloads).disabled(!enabled)
            }
        }
    }
}

/// A category remains recognizable before it has usable scan evidence.
struct CategoryPrerequisite: View {
    let title: String
    let detail: String
    let actionTitle: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
            CategorySelectionHeader(category: .downloads, state: .unchecked, title: "Downloads", detail: detail,
                                    size: title, enabled: false, action: {})
            Button(actionTitle, action: action).disabled(!enabled)
                .padding(.leading, StillDesign.Space.xl)
        }
    }
}

/// Shared across destinations; stopping or finishing a scan never changes the route.
struct ToolbarScanStatus: View {
    let location: String
    var phase = "Reading metadata…"
    var inspectedEntries: Int? = nil
    var returnToScan: (() -> Void)?
    let stop: () -> Void
    var body: some View {
        HStack(spacing: StillDesign.Space.sm) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 0) {
                Text(phase).font(.caption).lineLimit(1).accessibilityIdentifier("scanPhase")
                Text(inspectedEntries.map { "\($0) entries inspected · " + location } ?? "Scanning " + location)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("scanProgressSummary")
            }.frame(maxWidth: 240, alignment: .leading)
            Button("Stop scan", action: stop).controlSize(.small)
            if let returnToScan { Button("Return to scan", action: returnToScan).controlSize(.small) }
        }.accessibilityElement(children: .contain)
    }
}

struct LocationScopeRow<Actions: View>: View {
    let name: String
    let path: String
    let status: String
    @Binding var included: Bool
    let enabled: Bool
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        HStack(alignment: .top, spacing: StillDesign.Space.md) {
            Toggle("Include " + name, isOn: $included).labelsHidden().disabled(!enabled)
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                Label(name, systemImage: "folder").font(StillDesign.TypeStyle.section)
                Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled).help(path)
                StatusRow(text: status, symbol: "info.circle")
            }.frame(maxWidth: .infinity, alignment: .leading)
            actions().disabled(!enabled)
        }.padding(.vertical, StillDesign.Space.md)
    }
}

/// Restores a destination on insertion only. Selection-only changes never request scrolling.
struct DestinationViewport: NSViewRepresentable {
    @Binding var offset: CGPoint
    func makeNSView(context: Context) -> Viewport { Viewport() }
    func updateNSView(_ view: Viewport, context: Context) {
        view.onOffset = { offset = $0 }
        let saved = offset
        DispatchQueue.main.async { [weak view] in view?.attach(saved: saved) }
    }
    @MainActor final class Viewport: NSView {
        var onOffset: ((CGPoint) -> Void)?
        private weak var clip: NSClipView?
        private var restored = false
        func attach(saved: CGPoint) {
            guard let scroll = enclosingScrollView else { return }
            if clip !== scroll.contentView {
                NotificationCenter.default.removeObserver(self)
                clip = scroll.contentView; clip?.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSView.boundsDidChangeNotification, object: clip)
            }
            if !restored {
                restored = true
                scroll.layoutSubtreeIfNeeded()
                clip?.scroll(to: saved); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        @objc private func moved() { if restored, let clip { onOffset?(clip.bounds.origin) } }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

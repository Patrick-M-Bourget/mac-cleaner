import AppKit
import SwiftUI
import StillCore

/// Shared native presentation vocabulary. Reuse these components and tokens before adding UI; docs/visual/preview.html is the visual reference.
enum StillDesign {
    enum Space { static let xs: CGFloat = 4; static let sm: CGFloat = 8; static let md: CGFloat = 12; static let lg: CGFloat = 16; static let xl: CGFloat = 24; static let page: CGFloat = 32 }
    enum Radius { static let row: CGFloat = 8; static let surface: CGFloat = 12 }
    /// Fixed sizes: the capacity bar's heights (sidebar, card, prominent card) and the device card's icon tile.
    enum Size { static let meterCompact: CGFloat = 4; static let meter: CGFloat = 8; static let meterProminent: CGFloat = 12; static let deviceIcon: CGFloat = 44; static let sheetNarrow: CGFloat = 480; static let numberField: CGFloat = 64
        /// A category badge's square tile.
        static let badge: CGFloat = 32
        /// The CacheDrop mark in the sidebar header (#156).
        static let brandMark: CGFloat = 24
        /// The surface gap between a meter's segments, and the narrowest segment it draws (#164).
        static let meterGap: CGFloat = 2; static let meterSegmentMinimum: CGFloat = 3 }
    /// How strongly a colour tints a surface behind its symbol, as in a category badge.
    enum Opacity { static let badgeTint: Double = 0.10
        /// A meter segment's part that Smart clean wouldn't free (#164).
        static let meterDimmed: Double = 0.30 }
    enum TypeStyle {
        /// The app name in the sidebar header.
        static let brand = Font.system(size: 17, weight: .medium)
        static let page = Font.system(size: 26, weight: .medium); static let value = Font.system(size: 22, weight: .medium); static let section = Font.system(size: 13, weight: .medium)
        /// A sheet's title beside its badge, smaller than a page title ("Broader access is optional").
        static let sheet = Font.system(size: 18, weight: .medium)
        /// The symbol in the device card's icon tile.
        static let deviceIcon = Font.system(size: 16, weight: .light)
        /// The symbol in a category badge.
        static let badgeIcon = Font.system(size: 16, weight: .regular)
        /// A list row's name, explanations under a heading, captions and secondary lines, and command or tool output.
        static let rowTitle = Font.body.weight(.medium); static let note = Font.callout; static let caption = Font.caption; static let code = Font.caption.monospaced()
    }
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
    /// Light teal is a step darker than the prototype's 0x349A9B so a meter segment keeps 3:1 against the track (#164).
    static var teal: Color { adaptive(light: 0x2C8C8D, dark: 0x61C3C2) }
    static var orange: Color { adaptive(light: 0xBD7527, dark: 0xE2A35E) }
    /// App-managed storage and the catalog categories that share its colour: the system indigo, a step lighter in dark
    /// mode so a meter segment keeps 3:1 against the track (#164).
    static var indigo: Color { adaptive(light: 0x5856D6, dark: 0x8583F5) }
    static func files(_ count: Int) -> String { "\(count) \(count == 1 ? "file" : "files")" }
    static func items(_ count: Int) -> String { "\(count) \(count == 1 ? "item" : "items")" }
    static var capacityFill: Color { adaptive(light: 0x969BA7, dark: 0x858997) }
    static var capacityTrack: Color { adaptive(light: 0xECEEF2, dark: 0x33343D) }
    /// The meter's "Other reclaimable" segment: a slate, 5:1 against the track in light and 6:1 in dark (#164).
    static var meterOther: Color { adaptive(light: 0x5F6577, dark: 0xB4B8C5) }
    /// The meter's "In Trash" segment: subtle, between the used fill and the track (#164).
    static var meterTrash: Color { adaptive(light: 0xC4C8D1, dark: 0x5A5D69) }
    /// The sidebar meter's one "Reclaimable" segment.
    static var meterReclaimable: Color { .accentColor }
    static var separator: Color { Color(nsColor: .separatorColor) }
}
enum StorageCategory {
    /// `files`: files from folders the user picked, shown as the prototype shows a chosen folder.
    case cloud, developer, downloads, browser, managed, files
    /// Catalog categories that share the app-managed colour but each have their own symbol.
    case appCaches, models, appUpdates, logs
    /// App-managed storage rows (SPEC section 3): each place keeps the app-managed colour with its own symbol.
    case deviceBackups, mail, messages, photos, timeMachine, xcodeArchives, audioPlugIns
    var color: Color {
        switch self {
        case .cloud, .files: StillDesign.blue
        case .developer: StillDesign.purple
        case .downloads: StillDesign.orange
        case .browser: StillDesign.teal
        case .managed, .appCaches, .models, .appUpdates, .logs, .deviceBackups, .mail, .messages, .photos, .timeMachine, .xcodeArchives, .audioPlugIns: StillDesign.indigo
        }
    }
    var symbol: String {
        switch self {
        case .cloud: "icloud"
        case .developer: "hammer"
        case .downloads: "shippingbox"
        case .browser: "globe"
        case .managed: "square.stack.3d.up"
        case .files: "folder"
        case .appCaches: "app.dashed"
        case .models: "cpu"
        case .appUpdates: "arrow.down.app"
        case .logs: "doc.text"
        case .deviceBackups: "iphone"
        case .mail: "envelope"
        case .messages: "message"
        case .photos: "photo.on.rectangle"
        case .timeMachine: "clock.arrow.circlepath"
        case .xcodeArchives: "archivebox"
        case .audioPlugIns: "pianokeys"
        }
    }
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
    let symbol: String
    let color: Color
    init(category: StorageCategory) { symbol = category.symbol; color = category.color }
    /// A badge for something other than a storage category, such as a review sheet's consequence group.
    init(symbol: String, color: Color) { self.symbol = symbol; self.color = color }
    var body: some View {
        Image(systemName: symbol).font(StillDesign.TypeStyle.badgeIcon)
            .foregroundStyle(color).frame(width: StillDesign.Size.badge, height: StillDesign.Size.badge)
            .background(color.opacity(StillDesign.Opacity.badgeTint), in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
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
    var title = "Selected for Trash"
    var consequenceIdentifier = ""
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
        SummarySurface {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    Text(title).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    Text(value).font(StillDesign.TypeStyle.value).monospacedDigit()
                }
                Spacer(minLength: StillDesign.Space.lg)
                Text(detail).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing).accessibilityIdentifier(identifier)
            }
        }
        if let consequence { Text(consequence).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(consequenceIdentifier) }
        }
    }
}
enum StatusRole {
    case neutral, success, caution, failure
    var color: Color { switch self { case .neutral: .secondary; case .success: .green; case .caution: .orange; case .failure: .red } }
}
/// A disclosure group whose title opens it too ("Choose items", "Show files", "About folder access"). On macOS only a
/// DisclosureGroup's chevron toggles it. `isExpanded` lets the owner keep the state; otherwise the group keeps its own.
struct ActionDisclosureGroup<Content: View>: View {
    let title: String
    var isExpanded: Binding<Bool>?
    @ViewBuilder var content: () -> Content
    @State private var expanded = false
    init(_ title: String, isExpanded: Binding<Bool>? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.isExpanded = isExpanded; self.content = content
    }
    var body: some View {
        let expanded = isExpanded ?? $expanded
        DisclosureGroup(isExpanded: expanded, content: content) {
            Button(title) { expanded.wrappedValue.toggle() }.buttonStyle(.plain)
        }
    }
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
                if let consequence { Text(consequence).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
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
/// An empty `detail` or `meaning` draws no line. `mutedValue` draws the value as a secondary note, such as "Needs access".
struct StorageReviewRow: View {
    let category: StorageCategory
    let title: String
    let detail: String
    let value: String
    var meaning = ""
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var identifier = ""
    var mutedValue = false
    var body: some View {
        Group {
        if let action {
            Button(action: action) { contents }.buttonStyle(.plain)
                .accessibilityLabel(actionTitle ?? title)
                .accessibilityValue(spoken([title, detail, value, meaning]))
        }
        else {
            contents.accessibilityElement(children: .combine).accessibilityLabel(title)
                .accessibilityValue(spoken([detail, value, meaning]))
        }
        }.accessibilityIdentifier(identifier)
    }
    private func spoken(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: " · ") }
    private var contents: some View {
        HStack(spacing: StillDesign.Space.lg) {
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                Text(title).font(StillDesign.TypeStyle.section)
                if !detail.isEmpty { Text(detail).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: StillDesign.Space.xs) {
                Text(value).font(mutedValue ? StillDesign.TypeStyle.caption : StillDesign.TypeStyle.section).monospacedDigit()
                    .foregroundStyle(mutedValue ? .secondary : .primary)
                if !meaning.isEmpty { Text(meaning).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.multilineTextAlignment(.trailing)
            if action != nil { Image(systemName: "chevron.right").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary) }
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
/// A bottom bar: a leading note or control, then the actions.
struct ActionStrip<Leading: View, Actions: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: StillDesign.Space.lg) {
                leading()
                Spacer(minLength: StillDesign.Space.sm)
                actions()
            }.padding(.horizontal, StillDesign.Space.page).padding(.vertical, StillDesign.Space.lg)
        }.background(StillDesign.reading).controlSize(.large).buttonBorderShape(.capsule)
    }
}
extension ActionStrip where Leading == ActionStripMessage {
    /// Only for notes that report state, such as a running cleanup (Decision 25); nil leaves the actions alone.
    init(message: String?, @ViewBuilder actions: @escaping () -> Actions) { self.init(leading: { ActionStripMessage(text: message) }, actions: actions) }
}
/// A bottom bar's note; nothing when there is none.
struct ActionStripMessage: View {
    let text: String?
    var body: some View { if let text { Text(text).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
}
struct CapacityMeter: View {
    let available: Int64?
    let total: Int64?
    var compact = false
    var showsValue = true
    /// The taller bar of the Overview device card.
    var prominent = false
    /// What CacheDrop found, drawn inside the used space (#164); nil draws used space alone.
    var breakdown: StorageBreakdown? = nil
    /// Opens a segment's category in the Cleanup plan.
    var open: ((StorageBreakdown.Part) -> Void)? = nil
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    /// The total, when it and the available space are a consistent whole-disk reading.
    static func validTotal(available: Int64?, total: Int64?) -> Int64? {
        guard let available, let total, total > 0, available >= 0, available <= total else { return nil }
        return total
    }
    private func bytes(_ value: Int64) -> String { Self.bytes(value) }
    private var validTotal: Int64? { Self.validTotal(available: available, total: total) }
    private var amountText: String {
        guard let available, available >= 0 else { return "Capacity unavailable" }
        if let total = validTotal { return "\(bytes(available)) available of \(bytes(total))" }
        return "\(bytes(available)) available · Total capacity unavailable"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            if compact {
                Text(amountText).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(2)
                    .frame(height: 30, alignment: .topLeading).accessibilityIdentifier("sidebarCapacityAmount")
            } else if showsValue {
                Text(amountText).font(.callout).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                if let breakdown, validTotal != nil {
                    MeterSegments(breakdown: breakdown, reclaimableOnly: compact, open: open)
                } else if let available, let total = validTotal {
                    ZStack(alignment: .leading) {
                        Capsule().fill(StillDesign.capacityTrack)
                        Capsule().fill(StillDesign.capacityFill).frame(width: geometry.size.width * CGFloat(Double(total - available) / Double(total)))
                    }
                } else { Color.clear }
            }.frame(height: compact ? StillDesign.Size.meterCompact : prominent ? StillDesign.Size.meterProminent : StillDesign.Size.meter)
                .accessibilityElement(children: breakdown == nil || validTotal == nil ? .ignore : .contain)
                .accessibilityLabel(validTotal == nil ? "Capacity meter unavailable" : amountText)
        }
    }
}

/// The prototype's device card: the whole disk, used against available, with what CacheDrop found inside the used space (#164).
struct VolumeSummary: View {
    let available: Int64?
    let total: Int64?
    let observation: String
    var status = ""
    var refreshTitle = "Refresh capacity"
    var refreshing = false
    var refresh: (() -> Void)? = nil
    var name = StartupVolumeCapacity.name ?? "This Mac"
    var breakdown: StorageBreakdown? = nil
    var open: ((StorageBreakdown.Part) -> Void)? = nil
    private func bytes(_ value: Int64) -> String { CapacityMeter.bytes(value) }
    private var used: Int64? {
        guard let available, let total = CapacityMeter.validTotal(available: available, total: total) else { return nil }
        return total - available
    }
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
                HStack(alignment: .top, spacing: StillDesign.Space.md) {
                    Image(systemName: "internaldrive").font(StillDesign.TypeStyle.deviceIcon).foregroundStyle(.secondary)
                        .frame(width: StillDesign.Size.deviceIcon, height: StillDesign.Size.deviceIcon).background(StillDesign.reading.gradient, in: RoundedRectangle(cornerRadius: StillDesign.Radius.row))
                        .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.row).strokeBorder(StillDesign.separator, lineWidth: 0.5) }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text(name).font(StillDesign.TypeStyle.section)
                        Text("Startup volume · " + (total.map(bytes) ?? "Total capacity unavailable")).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    }.frame(height: StillDesign.Size.deviceIcon)
                    Spacer(minLength: StillDesign.Space.sm)
                    VStack(alignment: .trailing, spacing: StillDesign.Space.xs) {
                        if let available, available >= 0 {
                            Text(bytes(available)).font(StillDesign.TypeStyle.value).monospacedDigit().accessibilityIdentifier("startupCapacityAmount")
                            Text("available").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        } else {
                            Text("—").font(StillDesign.TypeStyle.value)
                            Text(refreshing ? "Checking capacity…" : "Available space unavailable").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                CapacityMeter(available: available, total: total, showsValue: false, prominent: true, breakdown: breakdown, open: open)
                HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.md) {
                    Text(used.map { bytes($0) + " used" } ?? "Used space unknown").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: StillDesign.Space.sm)
                    Text("Whole-disk capacity").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        .help(observation).accessibilityValue(observation).accessibilityIdentifier("capacityObservation")
                }
                if !status.isEmpty {
                    HStack(spacing: StillDesign.Space.md) {
                        Text(status).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("capacityRefreshStatus")
                        Spacer(minLength: StillDesign.Space.sm)
                        if let refresh, !refreshing {
                            Button(refreshTitle, action: refresh).accessibilityIdentifier("refreshCapacity")
                        }
                    }
                }
            }
        }
    }
}
struct StillSidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var accent: Color = StillDesign.blue
    var selectedCategories: Int? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: StillDesign.Space.sm) {
                Label { Text(title).foregroundStyle(selected ? .primary : .secondary) } icon: { Image(systemName: symbol).foregroundStyle(accent) }
                Spacer(minLength: 0)
                if let count = selectedCategories {
                    Text(String(max(0, count))).font(.caption2.weight(.medium)).monospacedDigit()
                        .frame(width: 18, height: 18).background(StillDesign.summary, in: Capsule())
                        .opacity(count > 0 ? 1 : 0).accessibilityHidden(true)
                }
            }.font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, StillDesign.Space.sm).padding(.horizontal, StillDesign.Space.sm)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: StillDesign.Radius.row).fill(StillDesign.selection)
                            .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.row).fill(LinearGradient(colors: [StillDesign.highlight, .clear], startPoint: .top, endPoint: .bottom)) }
                            .overlay { RoundedRectangle(cornerRadius: StillDesign.Radius.row).strokeBorder(StillDesign.highlight, lineWidth: 1) }
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(accessibleTitle).accessibilityIdentifier(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var accessibleTitle: String {
        guard let count = selectedCategories, count > 0 else { return title }
        return "\(title), \(count) \(count == 1 ? "category" : "categories") selected"
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

extension StillDesign.Size {
    /// A category badge and the gap after it: content under a badged header lines up with its title.
    static let badgeIndent: CGFloat = 32 + StillDesign.Space.md
    /// A checkbox, then a badge: content under a `CategorySelectionHeader` lines up with its title.
    static let categoryContentIndent: CGFloat = 16 + StillDesign.Space.md + badgeIndent
}
/// Selection stays on the native checkbox; the badge/title never become extra toggles.
struct CategorySelectionHeader: View {
    let category: StorageCategory
    let state: CategorySelectionState
    let title: String
    let detail: String
    let size: String
    let enabled: Bool
    var identifier: String? = nil
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: StillDesign.Space.md) {
            MacroCategoryCheckbox(state: state, label: title, enabled: enabled, action: action, identifier: identifier ?? (category == .downloads ? "downloadsCategorySelection" : "\(category)-CategorySelection"), showsTitle: false)
                .fixedSize().padding(.top, StillDesign.Space.sm)
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                Text(title).font(StillDesign.TypeStyle.section)
                Text(detail).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).help(detail)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(size).font(.callout).monospacedDigit().fixedSize()
        }
    }
}

/// The sidebar header: the CacheDrop mark (the app icon's drop and check, #156) and the name.
struct AppBrand: View {
    var body: some View {
        HStack(spacing: StillDesign.Space.sm) {
            Image("BrandMark").resizable().scaledToFit()
                .frame(width: StillDesign.Size.brandMark, height: StillDesign.Size.brandMark)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text("CacheDrop").font(StillDesign.TypeStyle.brand).tracking(-0.4)
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
    var detailLineLimit = 2
    @ViewBuilder var selection: () -> Selection
    var body: some View {
        HStack(alignment: .center, spacing: StillDesign.Space.md) {
            selection()
            Button(action: inspect) {
                HStack(spacing: StillDesign.Space.md) {
                    Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text(name).foregroundStyle(.primary)
                        // An empty detail makes it a one-line row (Smart clean, #141).
                        if !detail.isEmpty { Text(detail).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(detailLineLimit) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(size).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Inspect " + name)
                // The button hides its texts from accessibility; keep the detail (e.g. when it was last used) and size readable.
                .accessibilityValue(detail.isEmpty ? size : detail + ", " + size)
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
            // #162: the sidebar header shows the logo and name, so the title bar doesn't repeat it. The window keeps its
            // title for accessibility, Mission Control and the Window menu; the traffic lights and dragging are unchanged.
            window.titleVisibility = .hidden
            DispatchQueue.main.async { self.fit(window) }
        }
        private func fit(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let requested = window.frame
            let minimum = NSSize(width: min(900, visible.width), height: min(640, visible.height))
            window.minSize = minimum
            let size = NSSize(width: max(minimum.width, min(requested.width, visible.width)), height: max(minimum.height, min(requested.height, visible.height)))
            let origin = NSPoint(x: min(max(requested.minX, visible.minX), visible.maxX - size.width), y: min(max(requested.minY, visible.minY), visible.maxY - size.height))
            let fitted = NSRect(origin: origin, size: size)
            if window.frame != fitted { window.setFrame(fitted, display: true) }
        }
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
                    .font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                ForEach(Array(recentNames.prefix(5).enumerated()), id: \.offset) { _, name in
                    Text(name).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }
}

/// A category before it has usable scan evidence: still recognizable, with the action that gets the evidence.
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
                Text(phase).font(StillDesign.TypeStyle.caption).lineLimit(1).accessibilityIdentifier("scanPhase")
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
    var overlap: String? = nil
    @Binding var included: Bool
    let enabled: Bool
    @ViewBuilder let actions: () -> Actions
    private var identity: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            Label(name, systemImage: "folder").font(StillDesign.TypeStyle.section)
            Text(PathDisplay.shortLocation(of: path) + " · " + status).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
            if let overlap { Text(overlap).font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        HStack(alignment: .top, spacing: StillDesign.Space.md) {
            Toggle("Include " + name, isOn: $included).labelsHidden().disabled(!enabled)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: StillDesign.Space.md) {
                    identity.frame(minWidth: 240, idealWidth: 240, maxWidth: .infinity)
                    actions().fixedSize(horizontal: true, vertical: false).disabled(!enabled)
                }
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    identity
                    actions().fixedSize(horizontal: true, vertical: false).disabled(!enabled)
                }
            }
        }.padding(.vertical, StillDesign.Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("locationScope:" + path)
    }
}

/// Restores a destination on insertion only. Selection-only changes never request scrolling.
struct DestinationViewport: NSViewRepresentable {
    @Binding var offset: CGPoint?
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
        func attach(saved: CGPoint?) {
            guard let scroll = enclosingScrollView else { return }
            if clip !== scroll.contentView {
                NotificationCenter.default.removeObserver(self)
                clip = scroll.contentView; clip?.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSView.boundsDidChangeNotification, object: clip)
            }
            if !restored {
                restored = true
                // A new destination has no saved viewport. Its native top can be
                // negative because of automatic content insets; zero is not a
                // valid substitute. Only returning navigation restores an offset.
                if let saved {
                    scroll.layoutSubtreeIfNeeded()
                    clip?.scroll(to: saved); scroll.reflectScrolledClipView(scroll.contentView)
                }
                onOffset?(scroll.contentView.bounds.origin)
            }
        }
        @objc private func moved() { if restored, let clip { onOffset?(clip.bounds.origin) } }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

extension StillDesign.Size {
    /// The leading symbol column of a compact list row (History).
    static let rowIcon: CGFloat = 24
}

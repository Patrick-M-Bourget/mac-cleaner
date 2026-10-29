import AppKit
import SwiftUI
import CacheDropCore

/// Shared native presentation vocabulary. Reuse these components and tokens before adding UI; docs/visual/preview.html is the visual reference.
enum CacheDropDesign {
    enum Space { static let xs: CGFloat = 4; static let sm: CGFloat = 8; static let md: CGFloat = 12; static let lg: CGFloat = 16; static let xl: CGFloat = 24; static let page: CGFloat = 32 }
    enum Radius { static let row: CGFloat = 8; static let surface: CGFloat = 12 }
    /// Fixed sizes: the capacity bar's heights (sidebar, card, prominent card) and the device card's icon tile.
    enum Size { static let meterCompact: CGFloat = 4; static let meter: CGFloat = 8; static let meterProminent: CGFloat = 12; static let deviceIcon: CGFloat = 44; static let sheetNarrow: CGFloat = 480; static let numberField: CGFloat = 64
        /// A category badge's square tile.
        static let badge: CGFloat = 32
        /// The CacheDrop mark in the sidebar header (#156).
        static let brandMark: CGFloat = 24
        /// The surface gap between a meter's segments, and the narrowest segment it draws (#164).
        static let meterGap: CGFloat = 2; static let meterSegmentMinimum: CGFloat = 3
        /// The bottom bar's row: a large button's height, so the bar is the same with or without buttons or progress (#220).
        static let actionStripRow: CGFloat = 32
        /// A page's search field (#295), under its header's description (#352), as wide as the prototype's.
        static let searchField: CGFloat = 210
        /// A skeleton row's title and detail bars (#308), about the height of the text they stand in for.
        static let skeletonTitle: CGFloat = 11; static let skeletonDetail: CGFloat = 8
        /// How much wider a skeleton row's detail bar is than its title bar, as a share of the column (#308).
        static let skeletonDetailExtra: CGFloat = 0.22
        /// A hairline: the least height a spacer needs to keep its width in a row.
        static let hairline: CGFloat = 1
        /// The cleanup confirmation sheet (#334).
        static let sheetWide = CGSize(width: 640, height: 520)
        /// The storage explorer's inspector: its width beside the list once the page is at least `explorerWide` wide, and
        /// below the list otherwise, at most `inspectorStacked` tall or `inspectorStackedShare` of the page (#320).
        static let explorerWide: CGFloat = 800; static let inspector: CGFloat = 280; static let inspectorStacked: CGFloat = 220
        static let inspectorStackedShare: CGFloat = 0.35 }
    /// How strongly a colour tints a surface behind its symbol, as in a category badge.
    enum Opacity { static let badgeTint: Double = 0.10
        /// Rows from the last scan while a rescan runs: visible, plainly not live (#308).
        static let waiting: Double = 0.45
        /// The skeleton shimmer's band at its brightest (#308).
        static let shimmer: Double = 0.6 }
    /// How long motion takes: the skeleton's shimmer crossing once, and rows dimming as a rescan starts or ends (#308).
    /// How far a one-line caption may shrink before it truncates, so it stays one line at larger text sizes (#353).
    enum Scale { static let oneLineCaption: CGFloat = 0.75 }
    enum Motion { static let shimmer: Double = 2.4; static let waiting: Double = 0.2 }
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
    /// A skeleton row's placeholder bars and tiles (#308): the meter's track grey.
    static var skeleton: Color { capacityTrack }
    /// The skeleton's shimmer, low-contrast in both appearances (#308).
    static var skeletonShimmer: Color { adaptive(light: 0xFFFFFF, dark: 0x4A4B55) }
}
enum StorageCategory {
    /// `files`: files from folders the user picked, shown as the prototype shows a chosen folder.
    case cloud, developer, downloads, browser, managed, files
    /// Catalog categories that share the app-managed colour but each have their own symbol.
    case appCaches, models, appUpdates, logs
    /// Files from deleted apps (#173), and the apps themselves on the Applications page (#267).
    case leftovers, apps
    /// App-managed storage rows (SPEC section 3): each place keeps the app-managed colour with its own symbol.
    case deviceBackups, mail, messages, photos, timeMachine, xcodeArchives, audioPlugIns
    var color: Color {
        switch self {
        case .cloud, .files: CacheDropDesign.blue
        case .developer: CacheDropDesign.purple
        case .downloads: CacheDropDesign.orange
        case .browser: CacheDropDesign.teal
        case .managed, .appCaches, .models, .appUpdates, .logs, .deviceBackups, .mail, .messages, .photos, .timeMachine, .xcodeArchives, .audioPlugIns, .leftovers, .apps: CacheDropDesign.indigo
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
        case .leftovers: "square.dashed"
        case .apps: "macwindow"
        }
    }
}
private struct OpaqueChromeKey: EnvironmentKey { static let defaultValue = false }
/// The bar's background work line, with a folder scan's Stop scan and, away from where it started, Return to scan (#235).
struct BackgroundWorkStatus {
    let line: BackgroundWork.Line
    var stop: (() -> Void)? = nil
    var returnToScan: (() -> Void)? = nil
}
private struct BackgroundWorkKey: EnvironmentKey { static var defaultValue: BackgroundWorkStatus? { nil } }
extension EnvironmentValues {
    var cacheDropOpaqueChrome: Bool { get { self[OpaqueChromeKey.self] } set { self[OpaqueChromeKey.self] = newValue } }
    /// The app-wide background work every bottom bar reports while it runs (Decision 46).
    var cacheDropBackgroundWork: BackgroundWorkStatus? { get { self[BackgroundWorkKey.self] } set { self[BackgroundWorkKey.self] = newValue } }
}
enum ChromeRole { case chrome, sidebar }
struct ChromeSurface: View {
    var role: ChromeRole = .chrome
    @Environment(\.colorScheme) private var appearance
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.cacheDropOpaqueChrome) private var forcedOpaque
    var body: some View {
        Group {
            if role == .sidebar && appearance == .light { Color.white }
            else if reduced || forcedOpaque { role == .sidebar ? CacheDropDesign.sidebar : CacheDropDesign.summary }
            else {
                Rectangle().fill(.regularMaterial)
                    .overlay { if role == .sidebar { CacheDropDesign.sidebar.opacity(0.65) } }
                    .overlay { LinearGradient(colors: [CacheDropDesign.highlight, .clear], startPoint: .topLeading, endPoint: .bottomTrailing) }
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
        Image(systemName: symbol).font(CacheDropDesign.TypeStyle.badgeIcon)
            .foregroundStyle(color).frame(width: CacheDropDesign.Size.badge, height: CacheDropDesign.Size.badge)
            .background(color.opacity(CacheDropDesign.Opacity.badgeTint), in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row))
            .accessibilityHidden(true)
    }
}
/// A page's title and optional subtitle, with its back button just above the title when another page leads here (Decision 47).
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var back: BackButton? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            if let back { back }
            Text(title).font(CacheDropDesign.TypeStyle.page).tracking(-0.6)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// A page's one search field (#295), just under its header's description (#352): a rounded field with a plain prompt.
struct PageSearchField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    let identifier: String
    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt)).labelsHidden().textFieldStyle(.roundedBorder)
            .frame(width: CacheDropDesign.Size.searchField).accessibilityIdentifier(identifier)
    }
}
/// A list's column header, as Explore storage's "Name … On disk" (#352): the name column's label, then, right-aligned, the
/// value column's label or a control in its place, such as the list's `SortMenu`; a divider closes it. `insets` line the
/// labels up with the rows' own columns.
struct ColumnHeader<Trailing: View>: View {
    let leading: String
    var insets = EdgeInsets(top: 0, leading: CacheDropDesign.Space.md, bottom: 0, trailing: CacheDropDesign.Space.md)
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CacheDropDesign.Space.md) {
                Text(leading)
                Spacer(minLength: CacheDropDesign.Space.md)
                trailing()
            }.font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                .padding(insets).padding(.bottom, CacheDropDesign.Space.sm)
            Divider()
        }
    }
}
extension ColumnHeader where Trailing == Text {
    /// A header whose value column has a plain label, such as "On disk".
    init(_ leading: String, trailing: String,
         insets: EdgeInsets = EdgeInsets(top: 0, leading: CacheDropDesign.Space.md, bottom: 0, trailing: CacheDropDesign.Space.md)) {
        self.init(leading: leading, insets: insets) { Text(trailing) }
    }
}
/// A list's Sort (#352), right-aligned in its `ColumnHeader` rather than a separate control: a small menu, "Sort by <order>".
struct SortMenu<Order: Hashable & CaseIterable & RawRepresentable<String>>: View where Order.AllCases: RandomAccessCollection {
    @Binding var order: Order
    let identifier: String
    var body: some View {
        Picker("Sort by", selection: $order) {
            ForEach(Order.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).controlSize(.small).fixedSize().accessibilityIdentifier(identifier)
    }
}
/// The one back button (Decision 47): small, borderless and secondary, just above the page title, reading
/// "‹ <destination>". Its accessibility label says "Back to <destination>", so it never shares a name with a sidebar row.
struct BackButton: View {
    let destination: String
    var identifier: String? = nil
    var enabled = true
    let action: () -> Void
    init(destination: String, identifier: String? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.destination = destination; self.identifier = identifier; self.enabled = enabled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: CacheDropDesign.Space.xs) {
                Image(systemName: "chevron.left").imageScale(.small)
                Text(destination)
            }
        }.buttonStyle(.plain).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            .accessibilityLabel("Back to " + destination).disabled(!enabled)
            .modifier(OptionalIdentifier(identifier: identifier))
    }
}
/// Sets an accessibility identifier only when there is one, so the element keeps its default otherwise.
private struct OptionalIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}
struct SummarySurface<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(CacheDropDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            .background(CacheDropDesign.summary, in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface))
            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface).strokeBorder(CacheDropDesign.separator, lineWidth: contrast == .increased ? 1 : 0.5) }
    }
}
struct SelectionSummary: View {
    let value: String
    let detail: String
    var identifier = ""
    var consequence: String? = nil
    var title = "Selected for Trash"
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
        SummarySurface {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    Text(title).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    Text(value).font(CacheDropDesign.TypeStyle.value).monospacedDigit().accessibilityIdentifier(identifier.isEmpty ? "" : identifier + "Value")
                }
                Spacer(minLength: CacheDropDesign.Space.lg)
                Text(detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing).accessibilityIdentifier(identifier)
            }
        }
        if let consequence { Text(consequence).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
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
/// A link that fixes a status row's problem in place, such as "Choose again…" (#223, #311).
struct StatusAction {
    let title: String
    var identifier = ""
    let action: () -> Void
}
struct StatusRow: View {
    let text: String
    var symbol = "info.circle"
    var role: StatusRole = .neutral
    var identifier: String = ""
    var action: StatusAction? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.sm) {
            Label { Text(text).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(identifier) } icon: { Image(systemName: symbol).foregroundStyle(role.color) }
                .font(.callout).foregroundStyle(.secondary)
            if let action { Button(action.title, action: action.action).buttonStyle(.link).accessibilityIdentifier(action.identifier) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct SettingsRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
            Text(title).font(CacheDropDesign.TypeStyle.section)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            content()
        }.padding(.vertical, CacheDropDesign.Space.sm).frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// One quiet review group: category colors identify storage, never cleanup safety.
struct RecommendationGroup<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .background(CacheDropDesign.reading, in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface))
            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface).strokeBorder(CacheDropDesign.separator, lineWidth: contrast == .increased ? 1 : 0.5) }
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
        HStack(spacing: CacheDropDesign.Space.lg) {
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                Text(title).font(CacheDropDesign.TypeStyle.section)
                if !detail.isEmpty { Text(detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: CacheDropDesign.Space.xs) {
                Text(value).font(mutedValue ? CacheDropDesign.TypeStyle.caption : CacheDropDesign.TypeStyle.section).monospacedDigit()
                    .foregroundStyle(mutedValue ? .secondary : .primary)
                if !meaning.isEmpty { Text(meaning).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.multilineTextAlignment(.trailing)
            if action != nil { Image(systemName: "chevron.right").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
        }.padding(CacheDropDesign.Space.lg).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

/// An empty state's one way forward (#321): a button that leads where the user can act.
struct EmptyStateAction {
    let title: String
    let perform: () -> Void
    init(_ title: String, perform: @escaping () -> Void) { self.title = title; self.perform = perform }
}

/// The one empty state (#321): what's true, then at most one action that leads where the user can act. While a page's
/// content isn't known yet it shows `SkeletonRows` instead, never this. The action is `identifier` + "Action".
struct EmptyState: View {
    let title: String
    var detail = ""
    var symbol = "tray"
    var action: EmptyStateAction? = nil
    var identifier = "emptyState"
    var body: some View {
        HStack(alignment: .top, spacing: CacheDropDesign.Space.lg) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: CacheDropDesign.Size.badge).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                Text(title).font(CacheDropDesign.TypeStyle.section)
                if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let action {
                    Button(action.title, action: action.perform).accessibilityIdentifier(identifier + "Action").padding(.top, CacheDropDesign.Space.xs)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, CacheDropDesign.Space.xl)
            .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}
/// The bottom bar every screen has, always the same height (Decision 46): a leading note or control, then the actions.
/// While background work runs, its one quiet progress line takes the note's place. Notes are one line (#234).
struct ActionStrip<Leading: View, Actions: View>: View {
    /// False keeps the note in place while work runs, as the running cleanup's Stop strip does.
    var showsBackgroundWork = true
    /// Only the running cleanup's Stop strip lets its note wrap, so that bar alone may grow (#234).
    var wrapsNote = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var actions: () -> Actions
    @Environment(\.cacheDropBackgroundWork) private var work
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: CacheDropDesign.Space.lg) {
                if showsBackgroundWork, let work { BackgroundWorkLine(status: work) } else { leading() }
                Spacer(minLength: CacheDropDesign.Space.sm)
                actions()
            }.frame(minHeight: CacheDropDesign.Size.actionStripRow, maxHeight: wrapsNote ? nil : CacheDropDesign.Size.actionStripRow)
                .padding(.horizontal, CacheDropDesign.Space.page).padding(.vertical, CacheDropDesign.Space.lg)
        }.background(CacheDropDesign.reading).controlSize(.large)
            .accessibilityElement(children: .contain).accessibilityIdentifier("actionStrip")
    }
}
extension ActionStrip where Leading == ActionStripMessage {
    /// Only for notes that report state, such as a running cleanup (Decision 25); nil leaves the actions alone.
    init(message: String?, showsBackgroundWork: Bool = true, wrapsNote: Bool = false, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(showsBackgroundWork: showsBackgroundWork, wrapsNote: wrapsNote, leading: { ActionStripMessage(text: message, wraps: wrapsNote) }, actions: actions)
    }
}
extension ActionStrip where Leading == ActionStripMessage, Actions == EmptyView {
    /// A bar with no buttons: empty, or the progress of work running in the background.
    init() { self.init(message: nil) { EmptyView() } }
}
/// Background work as one quiet line: a small spinner and "Checking <location>… 4 of 31", plus "+1 more" (Decisions 25, 46).
/// A folder scan adds its phase and count, and small Stop scan and Return to scan buttons (#235).
struct BackgroundWorkLine: View {
    let status: BackgroundWorkStatus
    var body: some View {
        HStack(spacing: CacheDropDesign.Space.sm) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            HStack(spacing: CacheDropDesign.Space.xs) {
                ForEach(Array(status.line.parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 { Text("·").accessibilityHidden(true) }
                    Text(part.text).accessibilityIdentifier(part.id)
                }
            }.font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).truncationMode(.middle)
                .help(status.line.text)
            // The bar's work line holds links, never bordered buttons (#311).
            if let stop = status.stop { Button("Stop scan", action: stop).buttonStyle(.link) }
            if let returnToScan = status.returnToScan { Button("Return to scan", action: returnToScan).buttonStyle(.link) }
        }.font(CacheDropDesign.TypeStyle.caption)
    }
}
/// A bottom bar's note; nothing when there is none. One line, truncated, with the full text in a tooltip (#234), unless it
/// may wrap (only the Stop strip's).
struct ActionStripMessage: View {
    let text: String?
    var wraps = false
    var body: some View {
        if let text {
            Group {
                if wraps { Text(text).fixedSize(horizontal: false, vertical: true) }
                else { Text(text).lineLimit(1).truncationMode(.tail).help(text) }
            }.font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("actionStripNote")
        }
    }
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
    /// A short tag riding the tip of the used space, such as "12.4 GB freed" while a cleanup shaves it (#355). An empty
    /// one keeps its place; the caller passes none with Reduce Motion and says it elsewhere.
    var tipLabel: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    /// The total, when it and the available space are a consistent whole-disk reading.
    static func validTotal(available: Int64?, total: Int64?) -> Int64? {
        SidebarCapacityText.validTotal(available: available, total: total)
    }
    private var validTotal: Int64? { Self.validTotal(available: available, total: total) }
    private var capacityText: SidebarCapacityText { SidebarCapacityText(available: available, total: total) }
    /// The full wording ("312 GB available of 1 TB"), for labels, tooltips and the non-compact value.
    private var amountText: String { capacityText.description }
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            if compact {
                // One line, "312 GB free of 1 TB"; "available" is in the label and tooltip (#353).
                Text(capacityText.line).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(CacheDropDesign.Scale.oneLineCaption).truncationMode(.tail)
                    .help(amountText).accessibilityLabel(amountText).accessibilityIdentifier("sidebarCapacityAmount")
            } else if showsValue {
                Text(amountText).font(.callout).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                if let breakdown, validTotal != nil {
                    MeterSegments(breakdown: breakdown, reclaimableOnly: compact, open: open)
                } else if let available, let total = validTotal {
                    ZStack(alignment: .leading) {
                        Capsule().fill(CacheDropDesign.capacityTrack)
                        Capsule().fill(CacheDropDesign.capacityFill).frame(width: geometry.size.width * CGFloat(Double(total - available) / Double(total)))
                    }
                } else { Color.clear }
            }.frame(height: compact ? CacheDropDesign.Size.meterCompact : prominent ? CacheDropDesign.Size.meterProminent : CacheDropDesign.Size.meter)
                .accessibilityElement(children: breakdown == nil || validTotal == nil ? .ignore : .contain)
                .accessibilityLabel(validTotal == nil ? "Capacity meter unavailable" : amountText)
                .overlay(alignment: .topLeading) { tip }
                // Only a cleanup's bar eases as it shaves; every other meter changes as it always did.
                .animation(reduceMotion || tipLabel == nil ? nil : .easeOut(duration: CacheDropDesign.Motion.waiting), value: available)
        }
    }
}

extension CapacityMeter {
    /// The tip tag, above the bar, ending at the tip of the used space (kept inside the bar's width).
    @ViewBuilder fileprivate var tip: some View {
        if let tipLabel, !tipLabel.isEmpty, !reduceMotion, let available, let total = validTotal {
            GeometryReader { geometry in
                let tipX = geometry.size.width * CGFloat(Double(total - available) / Double(total))
                // Ends at the tip, never past either end of the bar; a long tag shrinks rather than spill.
                let width = min(CacheDropDesign.Size.tipTag, geometry.size.width)
                Text(tipLabel).font(CacheDropDesign.TypeStyle.caption).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(CacheDropDesign.Scale.oneLineCaption)
                    .frame(width: width, alignment: .trailing)
                    .offset(x: min(max(0, tipX - width), geometry.size.width - width), y: -CacheDropDesign.Size.tipTagRise)
                    .accessibilityIdentifier("meterTipTag")
            }
        }
    }
}
extension CacheDropDesign.Size {
    /// The tip tag's width, and how far above the bar it sits (#355).
    static let tipTag: CGFloat = 180
    static let tipTagRise: CGFloat = 18
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
    /// The bar's tip tag, while a cleanup shaves it (#355).
    var tipLabel: String? = nil
    private func bytes(_ value: Int64) -> String { CapacityMeter.bytes(value) }
    private var used: Int64? {
        guard let available, let total = CapacityMeter.validTotal(available: available, total: total) else { return nil }
        return total - available
    }
    var body: some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
                HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
                    Image(systemName: "internaldrive").font(CacheDropDesign.TypeStyle.deviceIcon).foregroundStyle(.secondary)
                        .frame(width: CacheDropDesign.Size.deviceIcon, height: CacheDropDesign.Size.deviceIcon).background(CacheDropDesign.reading.gradient, in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row))
                        .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).strokeBorder(CacheDropDesign.separator, lineWidth: 0.5) }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                        Text(name).font(CacheDropDesign.TypeStyle.section)
                        Text("Startup volume · " + (total.map(bytes) ?? "Total capacity unavailable")).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    }.frame(height: CacheDropDesign.Size.deviceIcon)
                    Spacer(minLength: CacheDropDesign.Space.sm)
                    VStack(alignment: .trailing, spacing: CacheDropDesign.Space.xs) {
                        if let available, available >= 0 {
                            Text(bytes(available)).font(CacheDropDesign.TypeStyle.value).monospacedDigit().accessibilityIdentifier("startupCapacityAmount")
                            Text("available").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        } else {
                            Text("—").font(CacheDropDesign.TypeStyle.value)
                            Text(refreshing ? "Checking capacity…" : "Available space unavailable").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                CapacityMeter(available: available, total: total, showsValue: false, prominent: true, breakdown: breakdown, open: open, tipLabel: tipLabel)
                    // Room for the tag from the run's start, so the card never jumps when it appears (#355).
                    .padding(.top, tipLabel == nil ? 0 : CacheDropDesign.Size.tipTagRise)
                HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.md) {
                    Text(used.map { bytes($0) + " used" } ?? "Used space unknown").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: CacheDropDesign.Space.sm)
                    Text(observation).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        .help(observation).accessibilityValue(observation).accessibilityIdentifier("capacityObservation")
                }
                if !status.isEmpty {
                    HStack(spacing: CacheDropDesign.Space.md) {
                        Text(status).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("capacityRefreshStatus")
                        Spacer(minLength: CacheDropDesign.Space.sm)
                        if let refresh, !refreshing {
                            Button(refreshTitle, action: refresh).buttonStyle(.link).accessibilityIdentifier("refreshCapacity")
                        }
                    }
                }
            }
        }
    }
}
struct CacheDropSidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var accent: Color = CacheDropDesign.blue
    var selectedCategories: Int? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: CacheDropDesign.Space.sm) {
                Label { Text(title).foregroundStyle(selected ? .primary : .secondary) } icon: { Image(systemName: symbol).foregroundStyle(accent) }
                Spacer(minLength: 0)
                if let count = selectedCategories {
                    Text(String(max(0, count))).font(.caption2.weight(.medium)).monospacedDigit()
                        .frame(width: 18, height: 18).background(CacheDropDesign.summary, in: Capsule())
                        .opacity(count > 0 ? 1 : 0).accessibilityHidden(true)
                }
            }.font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, CacheDropDesign.Space.sm).padding(.horizontal, CacheDropDesign.Space.sm)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).fill(CacheDropDesign.selection)
                            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).fill(LinearGradient(colors: [CacheDropDesign.highlight, .clear], startPoint: .top, endPoint: .bottom)) }
                            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).strokeBorder(CacheDropDesign.highlight, lineWidth: 1) }
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
        context.coordinator.state = Self.buttonState(state)
        view.title = showsTitle ? label : ""; view.isEnabled = enabled && context.environment.isEnabled
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel(label)
        view.state = Self.buttonState(state)
    }
    static func buttonState(_ state: CategorySelectionState) -> NSControl.StateValue { state == .checked ? .on : state == .mixed ? .mixed : .off }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        var state: NSControl.StateValue = .off
        init(_ action: @escaping () -> Void) { self.action = action }
        /// AppKit advances the button's own state on a click; put the model's back, since a click that only lists the
        /// category's items (#240) changes no selection and so never redraws it. A changed selection redraws over this.
        @objc func clicked(_ sender: NSButton) { action(); sender.state = state }
    }
}

extension CacheDropDesign.Size {
    /// A category badge and the gap after it: content under a badged header lines up with its title.
    static let badgeIndent: CGFloat = CacheDropDesign.Size.badge + CacheDropDesign.Space.md
    /// A checkbox, then a badge: content under a `CategorySelectionHeader` lines up with its title.
    static let categoryContentIndent: CGFloat = checkbox + CacheDropDesign.Space.md + badgeIndent
    /// A category checkbox's width, kept as a gap when a row has none (#267, #270).
    static let checkbox: CGFloat = 16
}
/// The native checkbox ticks the row, and so does a click anywhere else on it (#348): the same toggle, never a second one, and
/// links in `below` keep their own clicks. A nil `state` draws no checkbox and takes no click, for a row that can't be chosen
/// (Decision 51), and the identifier then names the row. `below` goes under the title and detail, in their column (#298).
struct CategorySelectionHeader<Below: View>: View {
    let category: StorageCategory
    let state: CategorySelectionState?
    let title: String
    let detail: String
    let size: String
    let enabled: Bool
    var identifier: String? = nil
    let action: () -> Void
    @ViewBuilder var below: () -> Below
    /// A parent's `.disabled` (a scan dimming the rows), which the native checkbox follows too.
    @Environment(\.isEnabled) private var environmentEnabled
    var body: some View {
        let row = HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
            if let state {
                MacroCategoryCheckbox(state: state, label: title, enabled: enabled, action: action, identifier: identifier ?? (category == .downloads ? "downloadsCategorySelection" : "\(category)-CategorySelection"), showsTitle: false)
                    .fixedSize().padding(.top, CacheDropDesign.Space.sm)
            }
            clickable
        }
        if state == nil, let identifier { row.accessibilityElement(children: .contain).accessibilityIdentifier(identifier) } else { row }
    }
    /// Everything right of the checkbox: a click here toggles the row as the checkbox does (#348).
    private var clickable: some View {
        HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
            // Without a checkbox, the badge keeps its place, so titles line up with the rows that have one.
            CategoryBadge(category: category).padding(.leading, state == nil ? CacheDropDesign.Size.checkbox + CacheDropDesign.Space.md : 0)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                Text(title).font(CacheDropDesign.TypeStyle.section)
                // No detail (an app with no maker) leaves no empty line (#298).
                if !detail.isEmpty {
                    Text(detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).help(detail)
                }
                below()
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(size).font(.callout).monospacedDigit().fixedSize()
        }.contentShape(Rectangle()).onTapGesture { if state != nil && enabled && environmentEnabled { action() } }
    }
}
extension CategorySelectionHeader where Below == EmptyView {
    init(category: StorageCategory, state: CategorySelectionState?, title: String, detail: String, size: String, enabled: Bool, identifier: String? = nil,
         action: @escaping () -> Void) {
        self.init(category: category, state: state, title: title, detail: detail, size: size, enabled: enabled, identifier: identifier, action: action) { EmptyView() }
    }
}

/// A category in the Cleanup plan or Smart clean (Decision 48): the header, whose checkbox ticks the whole category, then
/// an optional notice and the items behind "Choose items · N", or "Choose items · N · M stay(s)" when `staying` parts are listed
/// that can't be chosen (#290). A nil `itemCount` draws no "Choose items". Each screen
/// keeps its own selection and its own open/closed state.
struct CategoryRow<Notice: View, Items: View>: View {
    let category: StorageCategory
    /// Nil for a row that can't be chosen: no checkbox (Decision 51).
    let state: CategorySelectionState?
    let title: String
    let detail: String
    let size: String
    let enabled: Bool
    let identifier: String
    let itemCount: Int?
    var staying = 0
    @Binding var expanded: Bool
    let toggle: () -> Void
    @ViewBuilder var notice: () -> Notice
    @ViewBuilder var items: () -> Items
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            // With no detail (an app with no maker), the notice takes the detail's place, right under the title, rather than
            // below the badge (#298).
            CategorySelectionHeader(category: category, state: state, title: title, detail: detail, size: size, enabled: enabled,
                                    identifier: identifier, action: toggle) {
                if detail.isEmpty { notice() }
            }
            if !detail.isEmpty { notice().padding(.leading, CacheDropDesign.Size.categoryContentIndent) }
            if let itemCount {
                ActionDisclosureGroup("Choose items · \(itemCount)" + (staying == 1 ? " · 1 stays" : staying > 1 ? " · \(staying) stay" : ""), isExpanded: $expanded) {
                    items().padding(.top, CacheDropDesign.Space.sm)
                }.padding(.leading, CacheDropDesign.Size.categoryContentIndent)
            }
        }
    }
}

/// The sidebar header: the CacheDrop mark (the app icon's drop and check, #156) and the name.
struct AppBrand: View {
    var body: some View {
        HStack(spacing: CacheDropDesign.Space.sm) {
            Image("BrandMark").resizable().scaledToFit()
                .frame(width: CacheDropDesign.Size.brandMark, height: CacheDropDesign.Size.brandMark)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text("CacheDrop").font(CacheDropDesign.TypeStyle.brand).tracking(-0.4)
        }
    }
}


/// Native first-responder restoration is explicit and one-shot after a sheet closes.
struct ReviewCleanupButton: View {
    let enabled: Bool
    let focusRequest: Int
    /// Why it is disabled, such as `CacheDropDesign.waitForScanHelp` (#308).
    var tooltip: String? = nil
    let action: () -> Void
    var body: some View {
        NativeReviewCleanupButton(enabled: enabled, focusRequest: focusRequest, tooltip: tooltip, action: action)
            .disabled(!enabled)
    }
}

private struct NativeReviewCleanupButton: NSViewRepresentable {
    let enabled: Bool
    let focusRequest: Int
    let tooltip: String?
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> FocusButton {
        let view = FocusButton(title: "Review cleanup", target: context.coordinator, action: #selector(Coordinator.clicked))
        view.bezelStyle = .rounded
        view.controlSize = .large
        if #available(macOS 26, *) { view.borderShape = .capsule }
        view.bezelColor = .controlAccentColor
        view.setAccessibilityLabel("Review cleanup")
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ view: FocusButton, context: Context) {
        view.isEnabled = enabled
        view.toolTip = tooltip
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
    /// What clicking the row does: ticks a choosable item (Decision 72), or inspects one in Explore storage. Nil makes the row
    /// inert, for what can't be chosen or a rule of items ticked one by one (#356, #367).
    let inspect: (() -> Void)?
    var detailLineLimit = 2
    /// What VoiceOver says the click does, when it isn't inspecting the item ("Select <name>").
    var actionLabel: String? = nil
    /// Shows the item in Finder: its own "Reveal in Finder" link after the size, never a row click (Decision 72).
    var reveal: (() -> Void)? = nil
    var revealIdentifier = ""
    @ViewBuilder var selection: () -> Selection
    private var summary: String { detail.isEmpty ? size : detail + ", " + size }
    var body: some View {
        HStack(alignment: .center, spacing: CacheDropDesign.Space.md) {
            selection()
            if let inspect {
                Button(action: inspect) { content }.buttonStyle(.plain).accessibilityLabel(actionLabel ?? "Inspect " + name)
                    // The button hides its texts from accessibility; keep the detail (e.g. when it was last used) and size readable.
                    .accessibilityValue(summary)
            } else {
                content.accessibilityElement(children: .combine)
            }
            if let reveal {
                // An inert row's link is its one control, so it carries the detail and size too (#207).
                Button("Reveal in Finder", action: reveal).buttonStyle(.link).font(CacheDropDesign.TypeStyle.caption)
                    .accessibilityLabel("Reveal \(name) in Finder").accessibilityValue(inspect == nil ? summary : "")
                    .accessibilityIdentifier(revealIdentifier)
            }
        }.padding(CacheDropDesign.Space.md)
            .background(inspected ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row))
    }
    private var content: some View {
        HStack(spacing: CacheDropDesign.Space.md) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                Text(name).foregroundStyle(.primary)
                // An empty detail makes it a one-line row (Smart clean, #141).
                if !detail.isEmpty { Text(detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(detailLineLimit) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(size).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }.contentShape(Rectangle())
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
            var requested = window.frame
            let minimum = NSSize(width: min(900, visible.width), height: min(640, visible.height))
            window.minSize = minimum
            #if DEBUG
            // A disposable UI test can open the window at its minimum size (#234) without saving that frame for later launches.
            if LocalStateLocation.isDisposableTest, ProcessInfo.processInfo.environment["CACHEDROP_TEST_MINIMUM_WINDOW"] == "1" {
                window.setFrameAutosaveName("")
                requested.size = minimum
            }
            #endif
            let size = NSSize(width: max(minimum.width, min(requested.width, visible.width)), height: max(minimum.height, min(requested.height, visible.height)))
            let origin = NSPoint(x: min(max(requested.minX, visible.minX), visible.maxX - size.width), y: min(max(requested.minY, visible.minY), visible.maxY - size.height))
            let fitted = NSRect(origin: origin, size: size)
            if window.frame != fitted { window.setFrame(fitted, display: true) }
        }
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
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            Label(name, systemImage: "folder").font(CacheDropDesign.TypeStyle.section)
            Text(PathDisplay.shortLocation(of: path) + " · " + status).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
            if let overlap { Text(overlap).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
            Toggle("Include " + name, isOn: $included).labelsHidden().disabled(!enabled)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
                    identity.frame(minWidth: 240, idealWidth: 240, maxWidth: .infinity)
                    actions().fixedSize(horizontal: true, vertical: false).disabled(!enabled)
                }
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                    identity
                    actions().fixedSize(horizontal: true, vertical: false).disabled(!enabled)
                }
            }
        }.padding(.vertical, CacheDropDesign.Space.md)
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

extension CacheDropDesign.Size {
    /// The leading symbol column of a compact list row (History).
    static let rowIcon: CGFloat = 24
}

// MARK: - Waiting for a scan (#308)

/// Which page layout a skeleton stands in for, so the page keeps its shape while its content isn't known yet.
enum SkeletonLayout {
    /// A `CategoryRow`: the checkbox's gap, a badge, title and detail, the size. The plan, Smart clean and Applications.
    case category
    /// A `StorageReviewRow` in a `RecommendationGroup`: Overview and App-managed storage.
    case review
    /// A plain list row, title and detail then the size: Storage trends, History and Recovery.
    case line
}

/// What a page shows while its content isn't known yet, the first scan or right after a cleanup (#308): grey placeholder
/// rows in the page's own layout, with no checkboxes, nothing clickable and every size "—", under a slow, calm shimmer
/// (none with Reduce Motion). Never a blank page. `identifier` names the whole group; VoiceOver hears "Loading".
struct SkeletonRows: View {
    let layout: SkeletonLayout
    var count = 3
    var identifier = "skeleton"
    init(_ layout: SkeletonLayout, count: Int = 3, identifier: String = "skeleton") { self.layout = layout; self.count = count; self.identifier = identifier }
    var body: some View {
        Group {
            if layout == .review {
                RecommendationGroup { rows(divider: { Divider().padding(.horizontal, CacheDropDesign.Space.lg) }) }
            } else {
                VStack(alignment: .leading, spacing: 0) { rows(divider: { Divider().padding(.vertical, layout == .category ? CacheDropDesign.Space.md : 0) }) }
            }
        }.skeletonShimmer()
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading").accessibilityIdentifier(identifier)
    }
    @ViewBuilder private func rows(divider: @escaping () -> some View) -> some View {
        ForEach(0..<count, id: \.self) { index in
            // The plan's rows each end with a divider; listed rows only sit between them.
            if layout != .category && index > 0 { divider() }
            SkeletonRow(layout: layout, width: Self.widths[index % Self.widths.count])
            if layout == .category { divider() }
        }
    }
    /// Each row's title width, as a share of its column, so the rows don't look stamped.
    private static let widths: [CGFloat] = [0.46, 0.32, 0.4, 0.28]
}

/// One skeleton row; `SkeletonRows` lays them out.
private struct SkeletonRow: View {
    let layout: SkeletonLayout
    let width: CGFloat
    var body: some View {
        HStack(alignment: layout == .category ? .top : .center, spacing: layout == .review ? CacheDropDesign.Space.lg : CacheDropDesign.Space.md) {
            if layout == .category { Color.clear.frame(width: CacheDropDesign.Size.checkbox, height: CacheDropDesign.Size.hairline) }
            if layout != .line {
                RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).fill(CacheDropDesign.skeleton)
                    .frame(width: CacheDropDesign.Size.badge, height: CacheDropDesign.Size.badge)
            }
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    bar(geometry.size.width * width, CacheDropDesign.Size.skeletonTitle)
                    bar(geometry.size.width * (width + CacheDropDesign.Size.skeletonDetailExtra), CacheDropDesign.Size.skeletonDetail)
                }.frame(maxHeight: .infinity, alignment: .center)
            }.frame(height: CacheDropDesign.Size.badge)
            Text("—").font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
        }.padding(layout == .review ? CacheDropDesign.Space.lg : 0).padding(.vertical, layout == .line ? CacheDropDesign.Space.sm : 0)
    }
    private func bar(_ width: CGFloat, _ height: CGFloat) -> some View {
        Capsule().fill(CacheDropDesign.skeleton).frame(width: max(0, width), height: height)
    }
}

/// The skeleton's shimmer: one soft band crossing slowly, low-contrast. Off with Reduce Motion (#308).
private struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = 0
    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, CacheDropDesign.skeletonShimmer.opacity(CacheDropDesign.Opacity.shimmer), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width / 3)
                        .offset(x: -geometry.size.width / 3 + travel * geometry.size.width * 4 / 3)
                }.mask(content).allowsHitTesting(false).accessibilityHidden(true)
                    .onAppear { withAnimation(.linear(duration: CacheDropDesign.Motion.shimmer).repeatForever(autoreverses: false)) { travel = 1 } }
            }
        }
    }
}
extension View {
    fileprivate func skeletonShimmer() -> some View { modifier(SkeletonShimmer()) }
    /// Rows from the last scan while a rescan runs (#308): they stay where they are, dimmed, and can't be clicked until it
    /// ends. Never rows that look final but ignore clicks.
    func waitingForScan(_ waiting: Bool) -> some View {
        disabled(waiting).opacity(waiting ? CacheDropDesign.Opacity.waiting : 1).allowsHitTesting(!waiting)
            .animation(.easeInOut(duration: CacheDropDesign.Motion.waiting), value: waiting)
    }
}

extension CacheDropDesign {
    /// What a disabled Review cleanup or Clean up says while a scan runs (#308).
    static let waitForScanHelp = "Wait for the scan to finish"
    /// The tooltip on the Cleanup plan's and Smart clean's selection totals (#370).
    static let selectionEstimateHelp = "Sizes are estimates from the scan, not guaranteed space freed. Linked files count once. Each item is checked again just before CacheDrop acts on it."
}

/// A bar's main action while its click-time checks run (#308): a small spinner beside it, and the action ignores more
/// clicks until they end.
struct BusyAction<Content: View>: View {
    let busy: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: CacheDropDesign.Space.sm) {
            if busy { ProgressView().controlSize(.small).accessibilityLabel("Checking") }
            content().disabled(busy)
        }
    }
}

/// What Overview, Smart clean and the plan show when a finished scan found nothing to clean (#308), as the one empty
/// state (#321). Overview and the plan lead on to Explore storage; Smart clean has its "Not included" links instead.
struct NothingToCleanUp: View {
    var identifier = "nothingToCleanUp"
    var action: EmptyStateAction? = nil
    var body: some View {
        EmptyState(title: "Nothing to clean up right now", symbol: "checkmark.circle", action: action, identifier: identifier)
    }
}

/// The one button rule (#311). 1: every bordered button is a capsule, set once per root (the workspace window, each sheet,
/// the Settings form) with `cacheDropButtonRule()`. 2: large in the bottom bar (`ActionStrip`) and sheet footers
/// (`SheetFooter`), regular in page bodies, never small and bordered. 3: anything inside a row, status line, breadcrumb or
/// the bar's work line is a link (`.buttonStyle(.link)`). 4: a sheet's footer is right-aligned, Cancel then the primary
/// button; its one close style is `CloseButton`.
extension View {
    func cacheDropButtonRule() -> some View { buttonBorderShape(.capsule) }
}
/// A sheet's footer (#311): an optional leading note, then its buttons right-aligned and large, Cancel then the primary one.
struct SheetFooter<Leading: View, Actions: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        HStack(spacing: CacheDropDesign.Space.sm) {
            leading()
            Spacer(minLength: CacheDropDesign.Space.md)
            actions()
        }.controlSize(.large).accessibilityElement(children: .contain).accessibilityIdentifier("sheetFooter")
    }
}
extension SheetFooter where Leading == EmptyView {
    init(@ViewBuilder actions: @escaping () -> Actions) { self.init(leading: { EmptyView() }, actions: actions) }
}
/// The one close style (#311): a borderless xmark in secondary text, at a sheet's or panel's top trailing corner.
struct CloseButton: View {
    var label = "Close"
    var identifier: String? = nil
    let action: () -> Void
    var body: some View {
        Button(label, systemImage: "xmark", action: action).labelStyle(.iconOnly).buttonStyle(.borderless)
            .foregroundStyle(.secondary).modifier(OptionalIdentifier(identifier: identifier))
    }
}

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
        /// The sidebar's icon column (#424).
        static let sidebarIcon: CGFloat = 20
        /// The prototype's search field: 7 points above and below its text.
        static let searchFieldHeight: CGFloat = 28
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
        static let inspectorStackedShare: CGFloat = 0.35
        /// The workspace's default content size and minimum outer-window size.
        static let defaultWindow = CGSize(width: 1120, height: 760)
        static let minimumWindow = CGSize(width: 900, height: 640)
        /// Sidebar width, its two fixed caption slots and the selected-category count badge.
        static let sidebarWidth: CGFloat = 190
        static let sidebarCaptionHeight: CGFloat = 14
        static let sidebarCountBadge: CGFloat = 18
        /// The icon column of an inspectable item and the location row's identity column.
        static let itemIcon: CGFloat = 20
        static let locationIdentity: CGFloat = 240
        /// The tip tag's width, and how far above the bar it sits (#355).
        static let tipTag: CGFloat = 180
        static let tipTagRise: CGFloat = 18
        /// A category badge and the gap after it; a checkbox has its own gap beside that badge.
        static let badgeIndent: CGFloat = badge + CacheDropDesign.Space.md
        static let categoryContentIndent: CGFloat = checkbox + CacheDropDesign.Space.md + badgeIndent
        static let checkbox: CGFloat = 16
        /// The leading symbol column of a compact list row (History).
        static let rowIcon: CGFloat = 24
    }
    /// How strongly a colour tints a surface behind its symbol, as in a category badge.
    enum Opacity { static let badgeTint: Double = 0.10
        /// Rows from the last scan while a rescan runs: visible, plainly not live (#308).
        static let waiting: Double = 0.45
        /// The skeleton shimmer's band at its brightest (#308).
        static let shimmer: Double = 0.6
        /// Opaque sidebar chrome and the inspected item's accent tint.
        static let opaqueSidebar: Double = 0.65
        static let inspectedItem: Double = 0.06
    }
    enum Stroke {
        static let fine: CGFloat = 0.5
        static let regular: CGFloat = 1
        static func surface(_ contrast: ColorSchemeContrast) -> CGFloat { contrast == .increased ? regular : fine }
    }
    /// How far a one-line caption may shrink before it truncates, so it stays one line at larger text sizes (#353).
    enum Scale { static let oneLineCaption: CGFloat = 0.75 }
    /// How long motion takes: the skeleton's shimmer crossing once, and rows dimming as a rescan starts or ends (#308).
    enum Motion { static let shimmer: Double = 2.4; static let waiting: Double = 0.2 }
    enum TypeStyle {
        /// The app name in the sidebar header.
        static let brand = Font.system(size: 17, weight: .medium)
        /// The sidebar's compact capacity observation and status lines.
        static let sidebarNote = Font.caption2
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
    static func items(_ count: Int) -> String { "\(count) \(count == 1 ? "item" : "items")" }
    /// The muted dash for a value not known yet or with nothing to show (Decision 62): never empty, never zero.
    static let noValue = "—"
    static var capacityFill: Color { adaptive(light: 0x969BA7, dark: 0x858997) }
    static var capacityTrack: Color { adaptive(light: 0xECEEF2, dark: 0x33343D) }
    /// The meter's "Other reclaimable" segment: a slate, 5:1 against the track in light and 6:1 in dark (#164).
    static var meterOther: Color { adaptive(light: 0x5F6577, dark: 0xB4B8C5) }
    /// The meter's "In Trash" segment: subtle, between the used fill and the track (#164).
    static var meterTrash: Color { adaptive(light: 0xC4C8D1, dark: 0x5A5D69) }
    /// The sidebar meter's one "Reclaimable" segment.
    static var meterReclaimable: Color { .accentColor }
    static var separator: Color { Color(nsColor: .separatorColor) }
    /// System accent follows the user's choice for focus rings and inspected rows.
    static var focus: Color { .accentColor }
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
/// The bar's background work line, with a folder scan's Stop scan x (#364) and, away from where it started, Return to scan (#235).
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
                    .overlay { if role == .sidebar { CacheDropDesign.sidebar.opacity(CacheDropDesign.Opacity.opaqueSidebar) } }
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
    /// A page's one search, on the right of the title and level with its description, so the header is one band and the
    /// page keeps one left edge (Applications).
    var search: PageSearchField? = nil
    var body: some View {
        HStack(alignment: .bottom, spacing: CacheDropDesign.Space.lg) {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                if let back { back }
                Text(title).font(CacheDropDesign.TypeStyle.page).tracking(-0.6)
                if let subtitle { Text(subtitle).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let search { search }
        }
    }
}
/// A page's one search field (#295): under its header's description (#352), or on the header's right (`PageHeader.search`). 210 wide,
/// a capsule, a 1-point border and room around the text. As a Mac search field: a magnifying glass, a clear button
/// once something is typed, and Esc clears it. The accent ring shows while typing in it. Clicking anywhere in it types there.
struct PageSearchField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    let identifier: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: CacheDropDesign.Space.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(label, text: $text, prompt: Text(prompt)).labelsHidden().textFieldStyle(.plain).focused($focused)
                .onExitCommand { text = "" }.accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search").accessibilityIdentifier(identifier + "Clear")
            }
        }
        // A capsule, like the capsule buttons beside it (Decision 77, #464); the wider inset keeps the icon off the curve.
        .padding(.horizontal, CacheDropDesign.Space.md).frame(width: CacheDropDesign.Size.searchField, height: CacheDropDesign.Size.searchFieldHeight)
        .background(CacheDropDesign.reading, in: Capsule())
        .overlay { Capsule().strokeBorder(focused ? CacheDropDesign.focus : CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.regular) }
        .contentShape(Capsule()).onTapGesture { focused = true }
    }
}
/// A list's sortable column header (#352, #373), as Explore storage's "Name … On disk": the name column's label, then,
/// right-aligned, the size column's; a divider closes it. Clicking the active column flips its direction, clicking the
/// other switches to it (names A to Z, sizes largest first), and a chevron sits on the active one. Each label is a button
/// identified `<identifier>-name` or `<identifier>-size`. `insets` line the labels up with the rows' own columns.
struct ColumnHeader: View {
    /// The name column's title, such as "Name".
    let nameTitle: String
    /// The size column's title, such as "Size" or "On disk".
    let sizeTitle: String
    @Binding var sort: ListSort
    let identifier: String
    var insets = EdgeInsets(top: 0, leading: CacheDropDesign.Space.md, bottom: 0, trailing: CacheDropDesign.Space.md)
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CacheDropDesign.Space.md) {
                SortButton(title: nameTitle, column: .name, sort: $sort, identifier: identifier)
                Spacer(minLength: CacheDropDesign.Space.md)
                SortButton(title: sizeTitle, column: .size, sort: $sort, identifier: identifier)
            }.font(CacheDropDesign.TypeStyle.caption)
                .padding(insets).padding(.bottom, CacheDropDesign.Space.sm)
            Divider()
        }
    }
}
/// One sortable label (#352, Decision 77): clicking the active one flips its direction, clicking the other switches to it,
/// and a chevron sits on the active one. Identified `<identifier>-name` or `<identifier>-size`.
struct SortButton: View {
    let title: String
    let column: ListSort.Column
    @Binding var sort: ListSort
    let identifier: String
    var body: some View {
        let active = sort.column == column
        Button { sort.select(column) } label: {
            HStack(spacing: CacheDropDesign.Space.xs) {
                Text(title)
                if active { Image(systemName: sort.ascending ? "chevron.up" : "chevron.down").imageScale(.small).accessibilityHidden(true) }
            }.foregroundStyle(active ? .primary : .secondary).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Sort by " + title)
            .accessibilityLabel(title).accessibilityValue(active ? sort.directionText : "")
            .accessibilityAddTraits(active ? .isSelected : []).accessibilityIdentifier(identifier + "-" + column.rawValue)
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
            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface).strokeBorder(CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.surface(contrast)) }
    }
}
struct SelectionSummary: View {
    let value: String
    let detail: String
    var identifier = ""
    let title: String
    /// What's selected on another page, as a link there after the detail: "· 1 on Applications" (#481, Decision 65 rule 3).
    var elsewhere: (title: String, open: () -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
        SummarySurface {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    Text(title).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    Text(value).font(CacheDropDesign.TypeStyle.value).monospacedDigit().accessibilityIdentifier(identifier.isEmpty ? "" : identifier + "Value")
                }
                Spacer(minLength: CacheDropDesign.Space.lg)
                HStack(spacing: CacheDropDesign.Space.xs) {
                    Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.trailing).accessibilityIdentifier(identifier)
                    if let elsewhere {
                        Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                        Button(elsewhere.title, action: elsewhere.open).buttonStyle(.link)
                            .accessibilityIdentifier(identifier.isEmpty ? "" : identifier + "Elsewhere")
                    }
                }.font(CacheDropDesign.TypeStyle.caption)
            }
        }
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
    /// Dimmed while its work runs, such as the review's "Quitting…" (#377).
    var isDisabled = false
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
                .font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
            if let action { Button(action.title, action: action.action).buttonStyle(.link).disabled(action.isDisabled).accessibilityIdentifier(action.identifier) }
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
            if let detail { Text(detail).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary) }
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
            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface).strokeBorder(CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.surface(contrast)) }
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
/// `compact` is one status line with the action as a link, above a list that stays in place (Overview, #372).
struct EmptyState: View {
    let title: String
    var detail = ""
    var symbol = "tray"
    var action: EmptyStateAction? = nil
    var identifier = "emptyState"
    var compact = false
    /// In a list of category rows, a section's empty state takes the rows' columns: its symbol where their icons are, its
    /// text on their titles' line (Applications).
    var inList = false
    var body: some View {
        if compact {
            StatusRow(text: title, symbol: symbol, action: action.map { StatusAction(title: $0.title, identifier: identifier + "Action", action: $0.perform) })
                .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        } else {
            full
        }
    }
    private var full: some View {
        HStack(alignment: .top, spacing: inList ? CacheDropDesign.Space.md : CacheDropDesign.Space.lg) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: CacheDropDesign.Size.badge).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                Text(title).font(CacheDropDesign.TypeStyle.section)
                if !detail.isEmpty { Text(detail).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let action {
                    Button(action.title, action: action.perform).accessibilityIdentifier(identifier + "Action").padding(.top, CacheDropDesign.Space.xs)
                }
            }
        }.padding(.leading, inList ? CacheDropDesign.Size.checkbox + CacheDropDesign.Space.md : 0)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, inList ? CacheDropDesign.Space.md : CacheDropDesign.Space.xl)
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
/// A folder scan adds its phase and count (#235); every folder scan, the automatic recheck too, adds a quiet `CloseButton` x
/// labelled "Stop scan", and away from its screen a Return to scan link (#364).
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
            // The bar's work line holds a quiet x and links, never bordered buttons (#311, #364).
            if let stop = status.stop { CloseButton(label: "Stop scan", action: stop) }
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
                Text(amountText).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
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
                        .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).strokeBorder(CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.fine) }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                        Text(name).font(CacheDropDesign.TypeStyle.section)
                        Text("Startup volume · " + (total.map { SizeFormatter.text($0) } ?? "Total capacity unavailable")).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    }.frame(height: CacheDropDesign.Size.deviceIcon)
                    Spacer(minLength: CacheDropDesign.Space.sm)
                    VStack(alignment: .trailing, spacing: CacheDropDesign.Space.xs) {
                        if let available, available >= 0 {
                            Text(SizeFormatter.text(available)).font(CacheDropDesign.TypeStyle.value).monospacedDigit().accessibilityIdentifier("startupCapacityAmount")
                            Text("free").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        } else {
                            Text(CacheDropDesign.noValue).font(CacheDropDesign.TypeStyle.value)
                            Text(refreshing ? "Checking capacity…" : "Free space unknown").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                CapacityMeter(available: available, total: total, showsValue: false, prominent: true, breakdown: breakdown, open: open, tipLabel: tipLabel)
                    // Room for the tag from the run's start, so the card never jumps when it appears (#355).
                    .padding(.top, tipLabel == nil ? 0 : CacheDropDesign.Size.tipTagRise)
                HStack(alignment: .firstTextBaseline, spacing: CacheDropDesign.Space.md) {
                    Text(used.map { SizeFormatter.text($0) + " used" } ?? "Used space unknown").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit()
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
                // One icon column, so every label starts at the same place whatever the symbol's width (#424).
                Label { Text(title).foregroundStyle(selected ? .primary : .secondary) } icon: {
                    Image(systemName: symbol).foregroundStyle(accent).frame(width: CacheDropDesign.Size.sidebarIcon)
                }
                Spacer(minLength: 0)
                if let count = selectedCategories {
                    Text(String(max(0, count))).font(CacheDropDesign.TypeStyle.sidebarNote.weight(.medium)).monospacedDigit()
                        .frame(width: CacheDropDesign.Size.sidebarCountBadge, height: CacheDropDesign.Size.sidebarCountBadge).background(CacheDropDesign.summary, in: Capsule())
                        .opacity(count > 0 ? 1 : 0).accessibilityHidden(true)
                }
            }.font(CacheDropDesign.TypeStyle.note)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, CacheDropDesign.Space.sm).padding(.horizontal, CacheDropDesign.Space.sm)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).fill(CacheDropDesign.selection)
                            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).fill(LinearGradient(colors: [CacheDropDesign.highlight, .clear], startPoint: .top, endPoint: .bottom)) }
                            .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row).strokeBorder(CacheDropDesign.highlight, lineWidth: CacheDropDesign.Stroke.regular) }
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

struct NativeCategoryCheckbox: NSViewRepresentable {

    let state: CategorySelectionState
    let label: String
    let enabled: Bool
    let action: () -> Void
    let identifier: String
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
    var icon: NSImage? = nil
    let action: () -> Void
    @ViewBuilder var below: () -> Below
    /// A parent's `.disabled` (a scan dimming the rows), which the native checkbox follows too.
    @Environment(\.isEnabled) private var environmentEnabled
    var body: some View {
        let row = HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
            if let state {
                NativeCategoryCheckbox(state: state, label: title, enabled: enabled, action: action, identifier: identifier ?? (category == .downloads ? "downloadsCategorySelection" : "\(category)-CategorySelection"), showsTitle: false)
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
            Group {
                if let icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: CacheDropDesign.Size.badge, height: CacheDropDesign.Size.badge).accessibilityHidden(true) }
                else { CategoryBadge(category: category) }
            }.padding(.leading, state == nil ? CacheDropDesign.Size.checkbox + CacheDropDesign.Space.md : 0)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                Text(title).font(CacheDropDesign.TypeStyle.section)
                // No detail (an app with no maker) leaves no empty line (#298).
                if !detail.isEmpty {
                    Text(detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1).help(detail)
                }
                below()
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(size).font(CacheDropDesign.TypeStyle.note).monospacedDigit().fixedSize()
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
/// that can't be chosen (#290). A nil `itemCount` draws no "Choose items". Selection is shared (Decision 67);
/// each screen keeps its own open/closed state.
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
    /// An app's own icon, in the badge's place (Applications).
    var icon: NSImage? = nil
    @Binding var expanded: Bool
    let toggle: () -> Void
    @ViewBuilder var notice: () -> Notice
    @ViewBuilder var items: () -> Items
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            // With no detail (an app with no maker), the notice takes the detail's place, right under the title, rather than
            // below the badge (#298).
            CategorySelectionHeader(category: category, state: state, title: title, detail: detail, size: size, enabled: enabled,
                                    identifier: identifier, icon: icon, action: toggle) {
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
            .background(inspected ? CacheDropDesign.focus.opacity(CacheDropDesign.Opacity.inspectedItem) : .clear, in: RoundedRectangle(cornerRadius: CacheDropDesign.Radius.row))
    }
    private var content: some View {
        HStack(spacing: CacheDropDesign.Space.md) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: CacheDropDesign.Size.itemIcon)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                Text(name).foregroundStyle(.primary)
                // An empty detail makes it a one-line row (Smart clean, #141).
                if !detail.isEmpty { Text(detail).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(detailLineLimit) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(size).font(CacheDropDesign.TypeStyle.note).monospacedDigit().foregroundStyle(.secondary)
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
            var screen = window.screen ?? NSScreen.main
            #if DEBUG
            let visualCapture = LocalStateLocation.isDisposableTest && ProcessInfo.processInfo.environment["CACHEDROP_TEST_VISUAL_WINDOW"] == "1"
            if visualCapture { screen = NSScreen.screens.first }
            #endif
            guard let screen else { return }
            let visible = screen.visibleFrame
            var requested = window.frame
            let minimum = NSSize(width: min(CacheDropDesign.Size.minimumWindow.width, visible.width), height: min(CacheDropDesign.Size.minimumWindow.height, visible.height))
            window.minSize = minimum
            #if DEBUG
            // Window-only captures must start on the primary display; XCTest cannot reliably drag across displays.
            if visualCapture {
                window.setFrameAutosaveName("")
                requested = NSRect(x: visible.minX + 40, y: visible.maxY - 800, width: 1000, height: 760)
            }
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
    /// Always included, such as built-in Downloads (#342): its checkbox is shown ticked and can't be changed.
    var fixed = false
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
            // Always included: no checkbox to grey out, its place kept so the rows line up (Decision 51, #426).
            if fixed { Color.clear.frame(width: CacheDropDesign.Size.checkbox, height: CacheDropDesign.Size.hairline).accessibilityHidden(true) }
            else { Toggle("Include " + name, isOn: $included).labelsHidden().disabled(!enabled) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
                    identity.frame(minWidth: CacheDropDesign.Size.locationIdentity, idealWidth: CacheDropDesign.Size.locationIdentity, maxWidth: .infinity)
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
            Text(CacheDropDesign.noValue).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
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
    var compact = false
    var action: EmptyStateAction? = nil
    var body: some View {
        EmptyState(title: "Nothing to clean up right now", symbol: "checkmark.circle", action: action, identifier: identifier, compact: compact)
    }
}

/// The one button rule (#311). 1: every bordered button is a capsule, set once per root (the workspace window, each sheet,
/// the Settings form) with `cacheDropButtonRule()`. 2: large in the bottom bar (`ActionStrip`) and sheet footers
/// (`SheetFooter`), regular in page bodies, never small and bordered. 3: anything inside a row, status line, breadcrumb or
/// the bar's work line is a link (`.buttonStyle(.link)`), except the work line's Stop scan x (#364). 4: a sheet's footer
/// is right-aligned, Cancel then the primary button; its one close style is `CloseButton`.
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
/// The one close style (#311): a borderless xmark in secondary text, at a sheet's or panel's top trailing corner, and
/// the bar's Stop scan (#364). Its label is also its tooltip.
struct CloseButton: View {
    var label = "Close"
    var identifier: String? = nil
    let action: () -> Void
    var body: some View {
        Button(label, systemImage: "xmark", action: action).labelStyle(.iconOnly).buttonStyle(.borderless)
            .foregroundStyle(.secondary).help(label).modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// One native linear bar with the current phase below it (#478).
struct ScanPreparationProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    var fraction: Double? = nil
    var identifier = ""
    /// False keeps the line's height but shows nothing under the bar, when a heading already says the same (#546).
    var showsText = true
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            ProgressView(value: fraction).progressViewStyle(.linear).controlSize(.small)
                .accessibilityLabel(text).accessibilityValue(text).accessibilityIdentifier(identifier)
                .animation(reduceMotion ? nil : .easeInOut(duration: CacheDropDesign.Motion.waiting), value: fraction)
            Text(text).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                .lineLimit(2).frame(minHeight: CacheDropDesign.Space.xl, alignment: .topLeading)
                .opacity(showsText ? 1 : 0).accessibilityHidden(!showsText)
        }
    }
}

/// Keeps unfinished workspace content quiet behind onboarding, then reveals it when the flow closes (#478).
struct OnboardingBackdrop: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .blur(radius: active ? CacheDropDesign.Space.sm : 0)
            .overlay {
                CacheDropDesign.reading.opacity(active ? CacheDropDesign.Opacity.waiting : 0).allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: CacheDropDesign.Motion.waiting), value: active)
    }
}

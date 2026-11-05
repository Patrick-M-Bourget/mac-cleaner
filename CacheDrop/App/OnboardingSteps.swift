import AppKit
import SwiftUI
import CacheDropCore

/// Onboarding's two steps (#783): Welcome shows what CacheDrop looks at, and one sheet then scans, lighting each category's
/// badge as it finishes, and shows what it found. Plain inputs, designed in the Design gallery; `FirstRunWelcomeView` drives them (#784).

/// The cleanable categories' badges, each over its short name, in rows of five (#783, #784). Welcome shows them all lit;
/// while scanning, a category still being read stays dimmed and lights up when it finishes, at once with Reduce Motion.
struct CategoryBadgeRow: View {
    let categories: [CatalogCategory]
    /// The categories finished so far; nil lights them all.
    var finished: Set<CatalogCategory>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ten badges with their names don't fit one row of the narrow sheet.
    private static let perRow = 5
    var body: some View {
        VStack(spacing: CacheDropDesign.Space.md) {
            ForEach(Array(stride(from: 0, to: categories.count, by: Self.perRow)), id: \.self) { start in
                HStack(alignment: .top, spacing: CacheDropDesign.Space.sm) {
                    ForEach(categories[start..<min(start + Self.perRow, categories.count)], id: \.self) { category in
                        badge(category)
                    }
                    // A short last row keeps the columns of the rows above.
                    ForEach(0..<(Self.perRow - min(Self.perRow, categories.count - start)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(categories.map(\.overviewTitle).joined(separator: ", "))
        .accessibilityIdentifier("welcomeCategories")
    }
    private func badge(_ category: CatalogCategory) -> some View {
        let lit = finished?.contains(category) ?? true
        return VStack(spacing: CacheDropDesign.Space.xs) {
            CategoryBadge(category: category.storageCategory)
            Text(category.shortTitle).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(lit ? 1 : CacheDropDesign.Opacity.waiting)
        .animation(reduceMotion ? nil : .easeInOut(duration: CacheDropDesign.Motion.waiting), value: lit)
        .help(category.overviewTitle)
    }
}

/// Step 1: what CacheDrop cleans, what it never touches, and one button to start.
struct OnboardingWelcomeStep: View {
    let categories: [CatalogCategory]
    let onStart: () -> Void
    let onClose: () -> Void
    var body: some View {
        OnboardingSheet(onClose: onClose) {
            OnboardingIdentity(categories: categories, finished: nil)
            VStack(spacing: CacheDropDesign.Space.sm) {
                Text("Never touches: Photos · Mail · Messages · passwords")
                    .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier("welcomeNeverTouches")
                Text("Nothing is cleaned until you review it")
                    .font(CacheDropDesign.TypeStyle.note).accessibilityIdentifier("welcomeSubtitle")
            }.multilineTextAlignment(.center)
        } footer: {
            Button("Start scan", action: onStart).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcomeStartScan")
        }
    }
}

/// Step 2, one sheet: scanning lights up the badges, then Ready shows what was found and leads into Smart clean.
struct OnboardingScanStep: View {
    /// A category Ready lists among the largest, with what it found.
    struct Found: Identifiable {
        let category: CatalogCategory
        let estimate: SizeEstimate
        var id: CatalogCategory { category }
    }
    enum Phase {
        /// `found` is the running total; `finished` the categories read so far.
        case scanning(found: Int64, finished: Set<CatalogCategory>)
        /// `top` is the largest categories, largest first (three are shown). No storage bar (owner, 2026-11-05).
        case ready(found: Int64, top: [Found])
        case nothingFound
    }
    let categories: [CatalogCategory]
    let phase: Phase
    @Binding var sharesSetupProgress: Bool
    let onStartSmartClean: () -> Void
    let onViewOverview: () -> Void
    let onClose: () -> Void

    var body: some View {
        switch phase {
        case .scanning(let found, let finished):
            // No footer while scanning (Decision 108): no disabled button waits for the scan.
            OnboardingSheet(onClose: onClose) {
                OnboardingIdentity(categories: categories, finished: finished)
                // The bar's own spinner, so a long category never reads as frozen; the total shows once something is found.
                HStack(spacing: CacheDropDesign.Space.sm) {
                    ProgressView().controlSize(.small).accessibilityIdentifier("welcomeScanProgress") // VoiceOver hears it busy
                    if found > 0 {
                        Text("Found " + SizeFormatter.text(found) + " so far").font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                            .monospacedDigit().accessibilityIdentifier("welcomeFoundSoFar")
                    }
                }
            } footer: { EmptyView() }
        case .ready(let found, let top):
            OnboardingSheet(onClose: onClose) {
                Text("Found " + SizeFormatter.text(found) + " you can clean").font(CacheDropDesign.TypeStyle.value).monospacedDigit()
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader).accessibilityIdentifier("welcomeFound")
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                    ForEach(top.prefix(3)) { row in
                        HStack(spacing: CacheDropDesign.Space.md) {
                            CategoryBadge(category: row.category.storageCategory)
                            Text(row.category.overviewTitle).font(CacheDropDesign.TypeStyle.note).lineLimit(1)
                            Spacer(minLength: CacheDropDesign.Space.sm)
                            Text(row.estimate.text).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("welcomeTopCategories")
            } footer: {
                Button("Start Smart clean", action: onStartSmartClean).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("welcomeStartSmartClean")
            } aboveFooter: {
                // The opt-in moves here from Welcome (#783): asked once something worth sharing has happened.
                Toggle(isOn: $sharesSetupProgress) {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                        Text(SetupProgressSharing.title)
                        Text(SetupProgressSharing.explanation).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.checkbox).accessibilityIdentifier("welcomeShareSetupProgress")
            }
        case .nothingFound:
            OnboardingSheet(onClose: onClose) {
                OnboardingIdentity(categories: categories, finished: nil)
                NothingToCleanUp(identifier: "welcomeNothingFound", compact: true).fixedSize() // Centred, as the rest of the sheet
            } footer: {
                Button("View Overview", action: onViewOverview).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("welcomeViewOverview")
            }
        }
    }
}

/// The large app icon over the category badges, captioned: Welcome's top, kept in place while scanning so the badges light
/// up where they were shown.
private struct OnboardingIdentity: View {
    let categories: [CatalogCategory]
    let finished: Set<CatalogCategory>?
    var body: some View {
        VStack(spacing: CacheDropDesign.Space.xl) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
                .frame(width: CacheDropDesign.Size.onboardingIcon, height: CacheDropDesign.Size.onboardingIcon)
                .accessibilityHidden(true)
            VStack(spacing: CacheDropDesign.Space.md) {
                Text("What CacheDrop cleans").font(CacheDropDesign.TypeStyle.section).accessibilityAddTraits(.isHeader)
                CategoryBadgeRow(categories: categories, finished: finished)
            }
        }
    }
}

/// Onboarding's sheet: the narrow sheet's width and padding, Close at the top trailing corner on every step (Decision 108),
/// centred content, and a footer only when the step has a button.
private struct OnboardingSheet<Content: View, Footer: View, AboveFooter: View>: View {
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @ViewBuilder var aboveFooter: () -> AboveFooter
    var body: some View {
        VStack(spacing: CacheDropDesign.Space.xl) {
            VStack(spacing: CacheDropDesign.Space.xl) { content() }.frame(maxWidth: .infinity)
            if Footer.self != EmptyView.self {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
                    if AboveFooter.self != EmptyView.self { aboveFooter().frame(maxWidth: .infinity, alignment: .leading) }
                    Divider()
                    SheetFooter { footer() }
                }
            }
        }
        // Content starts at the top edge, under Close, so the icon isn't pushed down by Close's row.
        .padding(.top, CacheDropDesign.Space.lg)
        .overlay(alignment: .topTrailing) { CloseButton(identifier: "welcomeCancel", action: onClose) }
        .padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading).cacheDropButtonRule()
    }
}
extension OnboardingSheet where AboveFooter == EmptyView {
    init(onClose: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.init(onClose: onClose, content: content, footer: footer, aboveFooter: { EmptyView() })
    }
}

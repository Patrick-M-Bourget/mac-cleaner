import SwiftUI
import CacheDropCore

#if DEBUG
/// Explicit development surface; never appears in product navigation or release builds.
struct DesignGallery: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var appearance = AppearanceChoice.light
    @State private var opaque = false
    @State private var selected = true
    @State private var shellExamplesExpanded = false
    @State private var historyExamplesExpanded = false
    @State private var growthExamplesExpanded = false
    @State private var alertExamplesExpanded = false
    @State private var categoryRowExpanded = false
    @State private var showsNavigationPrototype = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(showsNavigationPrototype ? "CacheDrop · Workspace prototype" : "CacheDrop · Component gallery").font(.headline).accessibilityIdentifier("designGalleryTitle")
                Spacer()
                Button(showsNavigationPrototype ? "Components" : "Full window prototype") { showsNavigationPrototype.toggle() }
                    .accessibilityIdentifier("galleryNavigationPrototype")
                Toggle("Opaque chrome", isOn: $opaque).accessibilityIdentifier("galleryOpaqueChrome")
                AppearancePicker(choice: $appearance).labelsHidden().fixedSize()
                CloseButton(label: "Close Design gallery", identifier: "closeDesignGallery") { dismissWindow(id: "design-gallery") }
            }.padding(CacheDropDesign.Space.lg).background { ChromeSurface() }
            if showsNavigationPrototype {
                NavigationPrototype()
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
                    PageHeader(title: "Native design system", subtitle: "Developer examples only · No personal storage measurements",
                               back: BackButton(destination: "Overview", action: {}))
                    Button { shellExamplesExpanded.toggle() } label: {
                        Label("Synthetic shell and appearance examples", systemImage: shellExamplesExpanded ? "chevron.down" : "chevron.right")
                    }.buttonStyle(.plain).accessibilityValue(shellExamplesExpanded ? "Expanded" : "Collapsed").accessibilityIdentifier("galleryShellExamples")
                    if shellExamplesExpanded {
                        ShellAppearanceGalleryExamples()
                        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                            Text("Synthetic category badge · Inert examples").font(.headline)
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: false, selectedCategories: 0) {}
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: true, selectedCategories: 1) {}
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: false, selectedCategories: 2) {}
                        }.frame(width: 166).background { ChromeSurface(role: .sidebar) }
                    }
                    DisclosureGroup("Synthetic History activity examples", isExpanded: $historyExamplesExpanded) {
                        HistoryActivityGalleryExamples()
                    }
                    DisclosureGroup("Synthetic Storage trends examples", isExpanded: $growthExamplesExpanded) { StorageTrendsGalleryExamples() }
                    DisclosureGroup("Synthetic storage alert settings", isExpanded: $alertExamplesExpanded) {
                        AlertThresholdEditor(draft: .constant("60"), canApply: true, apply: {})
                        AlertThresholdEditor(draft: .constant("invalid"), canApply: false, invalidDraft: true, apply: {})
                        AlertPermissionDetails(authorization: .denied, checked: true, settingsFeedback: "System Settings could not be opened.", openSettings: {})
                    }
                    CapacityGalleryExamples()
                    Text("Synthetic Saved data entry · Inert example").font(.headline)
                    SavedDataEntry(action: {})
                    Text("Synthetic Protected items entry · Inert example").font(.headline)
                    ProtectedItemsEntry(action: {})
                    Text("Synthetic Saved data controls · Inert enabled example").font(.headline)
                    SavedDataMaintenanceControls(clear: {}, reset: {})
                    StatusRow(text: "Reset waits until the interrupted cleanup is reviewed.", symbol: "exclamationmark.triangle", role: .caution)
                    StatusRow(text: "Downloads · Access unavailable", role: .caution, action: StatusAction(title: "Choose again…") {})
                    StatusRow(text: "Synth will be skipped: Synth is running. Quit it, then scan again.", symbol: "exclamationmark.circle", role: .caution,
                              action: StatusAction(title: "Quitting…", isDisabled: true) {})
                    Text("Synthetic unavailable controls · Cleanup or maintenance in progress").font(.headline)
                    SavedDataMaintenanceControls(enabled: false, clear: {}, reset: {})
                    Text("Full Disk Access · Inert example").font(.headline)
                    SettingsRow(title: "Full Disk Access", detail: "Optional access to more protected folders") {
                        StatusRow(text: "Not granted", symbol: "lock.shield")
                        Button("Learn more") {}.buttonStyle(.link).accessibilityIdentifier("galleryAccessExample")
                    }
                    // Explore storage's inspector (#320, #371): one path, as tall as its content.
                    ExplorerInspector(name: "Camera guide.pdf") {
                        Text("Location").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("/Example/Downloads/Camera guide.pdf")
                        Text("On disk").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("8 MB")
                        Text("Why it’s listed").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Not opened since Mar 2, 2026.")
                        Text("Action").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Move to Trash. The space stays used until you empty the Trash.")
                    }
                    ExplorerInspector(name: "Cloud file (example)", close: {}) {
                        Text("Example cloud file")
                        Text("On disk: Unknown")
                        Text("Cleanup action").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Remove local copies")
                    }
                    // Built in (#342): always included, so its checkbox can't change, and no Forget.
                    LocationScopeRow(name: "Downloads", path: "/Example/Downloads", status: "Built in · Not scanned", included: .constant(true), enabled: true, fixed: true) { EmptyView() }
                    LocationScopeRow(name: "Projects", path: "/Example/Projects", status: "Not scanned", included: $selected, enabled: true) { Menu("More") { Button("Forget location") {} } }
                    LocationScopeRow(name: "Downloads B", path: "/Example/Downloads/Long project folder/Downloads B", status: "Location unavailable · Reconnect it, then scan again", overlap: "Overlaps another remembered location · Shared contents are counted once.", included: $selected, enabled: true) {
                        HStack {
                            Button("Choose again…") {}
                            Button("Scan again") {}
                            Menu("More") { Button("Forget location") {} }
                        }
                    }.frame(maxWidth: 520)
                    LocationScopeRow(name: "Omitted Downloads", path: "/Example/Downloads/Omitted", status: "Omitted from the next scan", included: .constant(false), enabled: false) {
                        Menu("More") { Button("Forget location") {} }
                    }
                    RecommendationGroup {
                        StorageReviewRow(category: .downloads, title: "Downloads", detail: "Example files", value: "128 MB", meaning: "On disk", actionTitle: "Review files", action: {})
                        Divider()
                        StorageReviewRow(category: .cloud, title: "Downloaded iCloud files", detail: "Example cloud files", value: "Unknown", meaning: "On disk", actionTitle: "Review iCloud inventory", action: {})
                        Divider()
                        StorageReviewRow(category: .browser, title: "Browser caches", detail: "Example browser cache", value: "Unknown", meaning: "Unavailable")
                        Divider()
                        // #372: a category that found nothing stays listed, muted, with no Review link.
                        StorageReviewRow(category: .logs, title: "Logs and crash reports", detail: "Logs and crash reports apps wrote", value: "Empty", mutedValue: true)
                    }

                    SelectionSummary(value: "3 files", detail: "Example selection · No action will run", title: "Ready to clean")
                    SelectionSummary(value: "Synthetic mixed selection", detail: "Downloads and browser caches · No action will run", title: "Ready to clean")
                    HStack(spacing: CacheDropDesign.Space.lg) {
                        ForEach(0..<5) { index in CategoryBadge(category: [StorageCategory.cloud, .developer, .downloads, .browser, .managed][index]) }
                    }
                    SettingsRow(title: "Selection states", detail: "Native controls retain focus, Space, disabled and mixed semantics.") {
                        NativeCategoryCheckbox(state: .unchecked, label: "Unchecked", enabled: true, action: {}, identifier: "galleryUnchecked")
                        NativeCategoryCheckbox(state: .mixed, label: "Mixed selection", enabled: true, action: {}, identifier: "galleryMixed")
                        NativeCategoryCheckbox(state: .checked, label: "Selected", enabled: true, action: {}, identifier: "gallerySelected")
                        NativeCategoryCheckbox(state: .unchecked, label: "Unavailable · Access required", enabled: false, action: {}, identifier: "galleryDisabled")
                        Toggle("Interactive native checkbox", isOn: $selected)
                    }
                    SummarySurface {
                        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                            StatusRow(text: "Scan completed", symbol: "checkmark.circle", role: .success)
                            StatusRow(text: "Scanned 10:42 · Not fully read", symbol: "exclamationmark.circle", role: .caution)
                            StatusRow(text: "Access unavailable · Choose the folder again", symbol: "lock", role: .failure)
                            ScanPreparationProgress(text: "Reading files…", fraction: 0.4)
                            Text("Workspace behind onboarding").frame(maxWidth: .infinity, minHeight: CacheDropDesign.Space.page)
                                .modifier(OnboardingBackdrop(active: true))
                        }
                    }
                    // #311: one button rule, one example of each kind.
                    Text("Buttons · One rule").font(.headline)
                    ButtonRuleGalleryExamples()
                    Text("Search and Sort · Under the description, in the list’s header").font(.headline)
                    ListHeaderGalleryExamples()
                    // #321: one empty state, saying what's true with at most one action that leads where the user can act.
                    Text("Empty states · One way forward").font(.headline)
                    EmptyState(title: "No scans yet", detail: "Scan again tomorrow to see trends",
                               symbol: "chart.line.uptrend.xyaxis", action: EmptyStateAction("Scan again") {}, identifier: "galleryEmptyAction")
                    NothingToCleanUp(identifier: "galleryNothingToCleanUp", action: EmptyStateAction("Explore storage") {})
                    // #372: Overview's one line above its list, which stays in place with every category Empty.
                    NothingToCleanUp(identifier: "galleryNothingToCleanUpCompact", compact: true, action: EmptyStateAction("Explore storage") {})
                    EmptyState(title: "Nothing to review", symbol: "checkmark.circle", identifier: "galleryEmptyPlain")
                    EmptyState(title: "No scans yet", action: EmptyStateAction("Scan again") {}, identifier: "galleryEmptyCompact", compact: true)
                    EmptyState(title: "No matching apps", symbol: "app", identifier: "galleryEmptyInList", inList: true)
                    InspectableItemRow(name: "Example cache", detail: "Not used recently", size: "8 MB", symbol: "folder",
                                       inspected: false, inspect: nil, reveal: {}, revealIdentifier: "galleryItemReveal") {
                        Toggle("Include Example cache", isOn: $selected).labelsHidden().accessibilityIdentifier("galleryItemSelection")
                    }
                    // #308: nothing known yet, skeleton rows in each page's layout; a rescan dims the rows already shown.
                    Text("Waiting for a scan · Skeleton rows").font(.headline)
                    SkeletonRows(.category, count: 2, identifier: "gallerySkeletonCategory")
                    SkeletonRows(.review, count: 2, identifier: "gallerySkeletonReview")
                    SkeletonRows(.line, count: 2, identifier: "gallerySkeletonLine")
                    Text("Waiting for a scan · Rows from the last scan").font(.headline)
                    CategoryRow(category: .browser, state: .unchecked, title: "Browser caches · Example during a rescan", detail: "Dimmed, and can’t be clicked until the scan ends.",
                                size: "640 MB", enabled: false, identifier: "galleryWaitingRow", itemCount: nil, expanded: .constant(false), toggle: {}) {
                        EmptyView()
                    } items: { EmptyView() }.waitingForScan(true)
                    Text("Busy action · Checks running after a click").font(.headline)
                    HStack {
                        BusyAction(busy: true) { Button("Clean up") {}.buttonStyle(.borderedProminent).accessibilityIdentifier("galleryBusyAction") }
                        BusyAction(busy: false) { Button("Clean up") {}.buttonStyle(.borderedProminent).accessibilityIdentifier("galleryIdleAction") }
                        ReviewCleanupButton(enabled: false, focusRequest: 0, tooltip: CacheDropDesign.waitForScanHelp, action: {}).fixedSize()
                    }.controlSize(.large)
                    CapacityMeter(available: nil, total: nil)
                    CapacityMeter(available: 40_000_000_000, total: 512_000_000_000, compact: true)
                    SettingsRow(title: "Shared navigation and brand", detail: "Reference accents identify destinations; labels and selected traits carry meaning.") {
                        AppBrand()
                        CacheDropSidebarRow(title: "Overview", symbol: "internaldrive", selected: false) {}
                        CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: true, accent: CacheDropDesign.teal) {}
                    }
                    CategorySelectionHeader(category: .downloads, state: .mixed, title: "Downloads · Example mixed selection", detail: "The checkbox or a click on the row changes selection; filenames remain inspection controls.", size: "16 MB", enabled: true, action: {})
                    CategoryRow(category: .developer, state: .checked, title: "Developer · Example category row", detail: "Plan and Smart clean share one selection",
                                size: "1.2 GB", enabled: true, identifier: "galleryCategoryRow", itemCount: 2, staying: 1, expanded: $categoryRowExpanded, toggle: {}) {
                        EmptyView()
                    } items: {
                        Text("Example cache").font(CacheDropDesign.TypeStyle.note)
                        Text("Example build files").font(CacheDropDesign.TypeStyle.note)
                    }
                    // Applications (Decision 51): a row that can't be chosen has no checkbox, and says why.
                    CategoryRow(category: .apps, state: nil, title: "Example app", detail: "Example maker", size: "800 MB", enabled: true,
                                identifier: "galleryReadOnlyRow", itemCount: nil, expanded: .constant(false), toggle: {}) {
                        StatusRow(text: "Needs your password to remove", symbol: "lock", action: StatusAction(title: "Reveal in Finder", action: {}))
                    } items: { EmptyView() }
                    // With no maker, no empty line is left under the title (#298).
                    CategoryRow(category: .apps, state: nil, title: "Example app without a maker", detail: "", size: "12 MB", enabled: true,
                                identifier: "galleryNoDetailRow", itemCount: nil, expanded: .constant(false), toggle: {}) {
                        StatusRow(text: "Needs your password to remove", symbol: "lock", action: StatusAction(title: "Reveal in Finder", action: {}))
                    } items: { EmptyView() }
                    VolumeSummary(available: 40_000_000_000, total: 512_000_000_000, observation: "Example disk space")
                    VolumeSummary(available: nil, total: nil, observation: "Free space unknown")
                    // Every segment kind at the tip, as the cleaning bar draws a run (#343, #355): categories, going to the Trash, in Trash.
                    VolumeSummary(available: 40_000_000_000, total: 512_000_000_000, observation: "Synthetic found items · Some going to the Trash",
                                  breakdown: StorageBreakdown(used: 472_000_000_000, total: 512_000_000_000, categories: [
                                      (.developer, .measured(60_000_000_000)), (.browser, .measured(20_000_000_000)), (.downloads, .measured(25_000_000_000)),
                                      (.logs, .measured(8_000_000_000)),
                                  ], trash: .holds(12_000_000_000), toTrash: [.downloads: 15_000_000_000]))
                }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.background(CacheDropDesign.reading)
            // While background work runs, its progress line takes the note's place (Decision 46).
            ActionStrip(message: "Developer gallery · Actions are inert examples") { ReviewCleanupButton(enabled: false, focusRequest: 0, action: {}) }
                .environment(\.cacheDropBackgroundWork, BackgroundWorkStatus(line: .init(parts: [.init(id: "galleryProgress", text: "Checking Example cache… 4 of 31"), .init(id: "galleryMore", text: "+1 more")])))
            ActionStrip(message: "Developer gallery · Actions are inert examples") { ReviewCleanupButton(enabled: false, focusRequest: 0, action: {}) }
                .environment(\.cacheDropBackgroundWork, BackgroundWorkStatus(line: .init(parts: [.init(id: "galleryFolderScan", text: "Scanning Downloads"), .init(id: "galleryPhase", text: "Reading files…"), .init(id: "galleryCount", text: "1,240 files read")], runsFolderScan: true), stop: {}, returnToScan: {}))
            ActionStrip(message: "Developer gallery · Actions are inert examples") { ReviewCleanupButton(enabled: false, focusRequest: 0, action: {}) }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("designGallery")
        .frame(minWidth: CacheDropDesign.Size.minimumWindow.width, minHeight: CacheDropDesign.Size.minimumWindow.height)
        .cacheDropButtonRule()
        .environment(\.cacheDropOpaqueChrome, opaque)
        .preferredColorScheme(appearance == .automatic ? nil : appearance == .dark ? .dark : .light)
    }
}
/// #537: one complete window treatment, rendered directly by the gallery with synthetic data.
/// Light composition is under review; semantic surfaces also adapt to Dark without a separate layout.
private struct NavigationPrototype: View {
    @State private var destination = Destination.plan
    @State private var showsReview = false

    var body: some View {
        HStack(spacing: CacheDropDesign.Space.md) {
            sidebar
                .frame(width: CacheDropDesign.Size.sidebarWidth + CacheDropDesign.Space.page)
                .modifier(NavigationPrototypeGlass())
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
                        PageHeader(title: destination == .overview ? "Storage overview" : "Cleanup plan",
                                   subtitle: destination == .overview ? "A clearer picture of what’s on your Mac." : "Choose what to clean, then review the changes.")
                            .accessibilityElement(children: .contain).accessibilityIdentifier("prototypeNavigationHeader")
                        if destination == .overview { overview } else { plan }
                    }.padding(CacheDropDesign.Space.xl)
                }.scrollEdgeEffectHidden(true, for: .top)
                actionBar
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CacheDropDesign.reading, in: RoundedRectangle(cornerRadius: CacheDropDesign.Prototype.windowRadius))
                .clipShape(RoundedRectangle(cornerRadius: CacheDropDesign.Prototype.windowRadius))
                .overlay { RoundedRectangle(cornerRadius: CacheDropDesign.Prototype.windowRadius).strokeBorder(CacheDropDesign.separator.opacity(0.5), lineWidth: CacheDropDesign.Stroke.fine) }
        }.padding(CacheDropDesign.Space.md).background(CacheDropDesign.Prototype.canvas)
            .accessibilityElement(children: .contain).accessibilityIdentifier("navigationPrototype")
            .sheet(isPresented: $showsReview) { ThemePrototypeReviewSheet() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            AppBrand().padding(.horizontal, CacheDropDesign.Space.sm).padding(.top, CacheDropDesign.Space.lg).padding(.bottom, CacheDropDesign.Space.xl)
            ScrollView {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            Text("Storage").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.horizontal, CacheDropDesign.Space.sm)
            ForEach(Destination.allCases.filter { $0 != .locations }) { page in navigation(page) }
            Text("Settings").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).padding(.horizontal, CacheDropDesign.Space.sm).padding(.top, CacheDropDesign.Space.xl)
            navigation(.locations)
            }
            }.scrollIndicators(.hidden)
            Spacer(minLength: CacheDropDesign.Space.xl)
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                Label("This Mac", systemImage: "laptopcomputer").font(CacheDropDesign.TypeStyle.note)
                CapacityMeter(available: ThemePrototypeData.available, total: ThemePrototypeData.total, compact: true)
                Text("Updated 10:42 AM").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, CacheDropDesign.Space.sm).padding(.bottom, CacheDropDesign.Space.lg)
        }.padding(CacheDropDesign.Space.md)
    }

    private func navigation(_ page: Destination) -> some View {
        CacheDropSidebarRow(title: page.rawValue, symbol: page.symbol, selected: destination == page,
                           accent: page == .plan ? CacheDropDesign.teal : page == .growth ? CacheDropDesign.purple : CacheDropDesign.blue,
                           selectedCategories: page == .plan ? 3 : nil) {
            // Only these two destinations are part of this prototype; the other examples stay inert.
            if page == .overview || page == .plan { destination = page }
        }.keyboardShortcut(page.shortcut, modifiers: .command).accessibilityIdentifier("prototype-" + page.rawValue)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            SelectionSummary(value: ThemePrototypeData.selectedSize, detail: "33 items selected", title: "Ready to clean")
            ColumnHeader(nameTitle: "Name", sizeTitle: "Size", sort: .constant(ListSort()), identifier: "prototypeSort")
            VStack(spacing: 0) {
                ForEach(ThemePrototypeData.categories) { item in
                    ThemePrototypeCategoryRow(item: item)
                        .padding(.vertical, CacheDropDesign.Space.md)
                    if item.id != ThemePrototypeData.categories.last?.id { Divider() }
                }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            HStack(alignment: .top, spacing: CacheDropDesign.Space.lg) {
                VolumeSummary(available: ThemePrototypeData.available, total: ThemePrototypeData.total, observation: "Updated 10:42 AM", name: "This Mac",
                              breakdown: StorageBreakdown(used: 60_000_000_000, total: ThemePrototypeData.total,
                                                          categories: [(.developer, .measured(1_800_000_000)), (.browser, .measured(640_000_000)), (.downloads, .measured(128_000_000))], trash: .empty))
                SummarySurface {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                        Text("Recommended for review").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text(ThemePrototypeData.selectedSize).font(CacheDropDesign.TypeStyle.value).monospacedDigit()
                        Button("Review in Cleanup plan") { destination = .plan }.buttonStyle(.link).accessibilityIdentifier("prototypeOpenPlan")
                    }.frame(minHeight: CacheDropDesign.Prototype.overviewSummaryHeight, alignment: .leading)
                }.frame(width: CacheDropDesign.Size.sidebarWidth + CacheDropDesign.Space.page)
            }
            VStack(spacing: 0) {
                ForEach(ThemePrototypeData.categories) { item in
                    StorageReviewRow(category: item.category, title: item.title, detail: item.detail, value: item.size,
                                     meaning: item.category == .downloads ? "Review files" : "Rebuildable", action: { destination = .plan }, identifier: "prototypeOverview-" + item.id)
                    if item.id != ThemePrototypeData.categories.last?.id { Divider() }
                }
            }
            HStack {
                Text("Scanned locations").font(CacheDropDesign.TypeStyle.section)
                Spacer()
                Label("Downloads · Scanned 10:42 AM", systemImage: "folder").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: CacheDropDesign.Space.lg) {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                Text("33 items selected").font(CacheDropDesign.TypeStyle.section)
                Text("Review before anything changes").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: CacheDropDesign.Space.sm)
            if destination == .overview {
                Button("Scan again") {}.buttonStyle(.glass).accessibilityIdentifier("prototypeScanAgain")
            }
            Button("Review cleanup") { showsReview = true }.buttonStyle(.glassProminent).accessibilityIdentifier("prototypeReviewCleanup")
        }.controlSize(.large).padding(CacheDropDesign.Space.lg)
            .background(CacheDropDesign.summary.opacity(0.7))
            .overlay(alignment: .top) { Rectangle().fill(CacheDropDesign.separator.opacity(0.35)).frame(height: CacheDropDesign.Stroke.fine) }
    }
}

/// One fixture set feeds Overview, Cleanup plan, and Review; amounts stay consistent across the journey.
private enum ThemePrototypeData {
    struct Category: Identifiable {
        let category: StorageCategory
        let title: String
        let detail: String
        let size: String
        let count: Int
        var id: String { title }
    }
    static let available: Int64 = 40_000_000_000
    static let total: Int64 = 100_000_000_000
    static let selectedSize = "2.57 GB"
    static let categories: [Category] = [
        .init(category: .developer, title: "Developer caches and build files", detail: "Package caches and build files that tools rebuild", size: "1.8 GB", count: 22),
        .init(category: .browser, title: "Browser caches", detail: "Cached pages and images browsers fetch again", size: "640 MB", count: 8),
        .init(category: .downloads, title: "Downloads", detail: "Files you downloaded, ready to review", size: "128 MB", count: 3),
    ]
}

private extension CacheDropDesign {
    enum Prototype {
        static var canvas: Color { CacheDropDesign.adaptive(light: 0xECEEF2, dark: 0x111114) }
        static let windowRadius = CacheDropDesign.Radius.surface * 2
        static let overviewSummaryHeight: CGFloat = 100
    }
}

/// Shared glass treatment uses a neutral canvas rather than an artificial colored backdrop.
private struct NavigationPrototypeGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.cacheDropOpaqueChrome) private var opaque
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CacheDropDesign.Prototype.windowRadius)
        content.background {
            if reduced || opaque { shape.fill(CacheDropDesign.sidebar) }
            else { Color.clear.glassEffect(.regular, in: shape) }
        }.clipShape(shape)
            .overlay { if contrast == .increased { shape.strokeBorder(CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.regular) } }
    }
}

private struct ThemePrototypeCategoryRow: View {
    let item: ThemePrototypeData.Category
    @State private var expanded = false
    var body: some View {
        CategoryRow(category: item.category, state: .checked, title: item.title, detail: item.detail, size: item.size, enabled: true,
                    identifier: "prototypeCategory-" + item.id, itemCount: item.count, expanded: $expanded, toggle: {}) {
            EmptyView()
        } items: {
            Text("Example files · " + item.size).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
        }
    }
}

/// A real native sheet, with the same reading/summary surfaces as both prototype pages; all cleanup actions are inert.
private struct ThemePrototypeReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: CacheDropDesign.Space.md) {
                CategoryBadge(symbol: "checklist", color: CacheDropDesign.teal)
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    Text("Review cleanup").font(CacheDropDesign.TypeStyle.sheet)
                    Text("33 items selected · " + ThemePrototypeData.selectedSize).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                }
                Spacer()
                CloseButton(label: "Close review", identifier: "prototypeCloseReview") { dismiss() }
            }.padding(CacheDropDesign.Space.xl)
            ScrollView {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
                    reviewGroup(.permanentlyRemoved, size: "2.44 GB", detail: "These items are deleted permanently. Their apps and tools rebuild them when needed.", items: Array(ThemePrototypeData.categories.prefix(2)))
                    reviewGroup(.movedToTrash, size: "128 MB", detail: "These files go to the Trash. Space stays used until you empty it.", items: Array(ThemePrototypeData.categories.suffix(1)))
                }.padding(.horizontal, CacheDropDesign.Space.xl).padding(.bottom, CacheDropDesign.Space.xl)
            }.scrollEdgeEffectHidden(true, for: .top)
            SheetFooter {
                Text("Up to 2.44 GB freed now").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            } actions: {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered).accessibilityIdentifier("prototypeCancelReview")
                Button("Clean up") {}.buttonStyle(.glassProminent).accessibilityIdentifier("prototypeConfirmCleanup")
            }.padding(CacheDropDesign.Space.xl).background(CacheDropDesign.summary.opacity(0.7))
        }.frame(width: CacheDropDesign.Size.sheetWide.width, height: CacheDropDesign.Size.sheetWide.height + CacheDropDesign.Space.page)
            .background(CacheDropDesign.reading).cacheDropButtonRule()
            .accessibilityElement(children: .contain).accessibilityIdentifier("prototypeReviewSheet")
    }

    private func reviewGroup(_ consequence: ConsequenceGroup, size: String, detail: String, items: [ThemePrototypeData.Category]) -> some View {
        SummarySurface {
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                HStack(spacing: CacheDropDesign.Space.md) {
                    consequence.badge
                    Text(consequence.title).font(CacheDropDesign.TypeStyle.section)
                    Spacer()
                    Text(size).font(CacheDropDesign.TypeStyle.section).monospacedDigit()
                }
                Text(detail).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(items) { item in
                    HStack {
                        Text(item.title)
                        Spacer()
                        Text(item.size).monospacedDigit()
                    }.font(CacheDropDesign.TypeStyle.note)
                }
                DisclosureGroup("Show files · \(items.reduce(0) { $0 + $1.count })") {
                    Text("Example selection · No files on disk are changed").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                }.font(CacheDropDesign.TypeStyle.caption).accessibilityIdentifier("prototypeReviewFiles-" + consequence.title)
            }
        }
    }
}

/// Inert presentation examples reuse the live capacity components; no reads or timers.
private struct CapacityGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            example("checking", available: nil, total: nil, observation: "Checking free space…", status: "Checking capacity…", refreshing: true)
            example("refreshing", observation: "Updated 10:00 AM", status: "Refreshing…", refreshing: true)
            example("important", observation: "Updated 10:00 AM")
            example("fallback", observation: "Updated 10:00 AM")
            example("partial", total: nil, observation: "Updated 10:00 AM")
            example("stale", observation: "Last updated 10:00 AM", status: "Couldn’t refresh capacity", retry: true)
            example("unavailable", available: nil, total: nil, observation: "Free space unavailable", status: "Couldn’t refresh capacity", retry: true)
        }
    }
    private func example(_ name: String, available: Int64? = 40_000_000_000, total: Int64? = 512_000_000_000, observation: String, status: String = "", refreshing: Bool = false, retry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            Text("Synthetic capacity " + name + " · Inert example").font(.headline)
            VolumeSummary(available: available, total: total, observation: observation, status: status,
                          refreshTitle: retry ? "Try again" : "Refresh capacity", refreshing: refreshing, refresh: {})
        }.accessibilityElement(children: .contain).accessibilityIdentifier("capacityGallery-" + name)
    }
}
/// One of each button kind (#311): capsules large in the bar and sheet footers and regular in a page body, links inside a
/// row or status line, and the one close style.
private struct ButtonRuleGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            Text("Page body · Regular capsule").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            HStack { Button("Add folder…") {}; Button("Scan selected locations") {} }
            Text("Row and status line · Link").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            StatusRow(text: "Downloads · Access unavailable", role: .caution, action: StatusAction(title: "Choose again…") {})
            Text("Sheet footer · Large capsules, Cancel then the primary button").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            SummarySurface {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                    HStack { Text("Example sheet").font(CacheDropDesign.TypeStyle.section); Spacer(); CloseButton {} }
                    Divider()
                    SheetFooter { Button("Cancel") {}; Button("Clean up") {}.buttonStyle(.borderedProminent) }
                }
            }.frame(maxWidth: CacheDropDesign.Size.sheetNarrow)
            Text("Bottom bar · Large capsules").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            ActionStrip(message: "Example note") { Button("Scan again") {}; Button("Review plan") {}.buttonStyle(.borderedProminent) }
        }
    }
}
/// A page's search under its description, then a list's sortable column header (#352): click a column to sort by it, again to flip it.
private struct ListHeaderGalleryExamples: View {
    @State private var search = ""
    @State private var sort = ListSort()
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
            PageHeader(title: "Example page", subtitle: "Search under the description; sort by clicking a column of the list’s header.")
            PageSearchField(label: "Search the example list", prompt: "Name or maker", text: $search, identifier: "gallerySearch")
            ColumnHeader(nameTitle: "Name", sizeTitle: "On disk", sort: $sort, identifier: "gallerySort")
            ForEach(sort.ordered(Self.rows, name: \.name, bytes: \.bytes), id: \.name) { row in
                HStack { Text(row.name); Spacer(); Text(SizeFormatter.text(row.bytes)) }.font(CacheDropDesign.TypeStyle.note)
            }
        }
    }
    private struct Row { let name: String; let bytes: Int64 }
    private static let rows = [Row(name: "Movies", bytes: 9_000_000_000), Row(name: "archive 2.zip", bytes: 800_000_000),
                               Row(name: "archive 10.zip", bytes: 800_000_000)]
}
private struct ShellAppearanceGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            Text("Synthetic appearance controls · Inert examples").font(.headline)
            ForEach(Array([AppearancePreferenceController.Notice?.none, .invalidSavedValue, .unreadable, .saveFailed].enumerated()), id: \.offset) { index, notice in
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xs) {
                    Text("Appearance notice example " + String(index)).font(CacheDropDesign.TypeStyle.caption)
                    AppearancePreferenceNotice(notice: notice, retry: {})
                }.accessibilityElement(children: .contain).accessibilityIdentifier("appearanceGallery-" + String(index))
            }
        }
    }
}

#endif

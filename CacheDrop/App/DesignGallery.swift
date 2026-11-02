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
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CacheDrop · Component gallery").font(.headline).accessibilityIdentifier("designGalleryTitle")
                Spacer()
                Toggle("Opaque chrome", isOn: $opaque).accessibilityIdentifier("galleryOpaqueChrome")
                AppearancePicker(choice: $appearance).labelsHidden().fixedSize()
                CloseButton(label: "Close Design gallery", identifier: "closeDesignGallery") { dismissWindow(id: "design-gallery") }
            }.padding(CacheDropDesign.Space.lg).background { ChromeSurface() }
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
                    FullDiskAccessDetails(status: .notGranted)
                    // Explore storage's inspector (#320, #371): one path, as tall as its content.
                    ExplorerInspector(name: "Camera guide.pdf") {
                        Text("Location").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("/Example/Downloads/Camera guide.pdf")
                        Text("On disk").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("8 MB")
                        Text("Why it’s listed").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Not opened since Mar 2, 2026.")
                        Text("Action").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Move to Trash")
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
                        ForEach(0..<7) { index in CategoryBadge(category: [StorageCategory.cloud, .developer, .downloads, .browser, .managed, .appCaches, .leftovers][index]) }
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
                            // A heading already says it: the line under the bar takes no room (#573).
                            ScanPreparationProgress(text: "Your results are ready", fraction: 1, showsText: false)
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
                    // Decision 126: the review sheet opens at the click and shows its checks running (#565).
                    Text("Review sheet · Checks running").font(.headline)
                    ReviewChecksRunning(cancel: {}, identifier: "galleryReview")
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
        .accessibilityElement(children: .contain).accessibilityIdentifier("designGallery")
        .cacheDropButtonRule()
        .environment(\.cacheDropOpaqueChrome, opaque)
        .preferredColorScheme(appearance == .automatic ? nil : appearance == .dark ? .dark : .light)
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

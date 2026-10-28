import SwiftUI
import CacheDropCore

#if DEBUG
/// Explicit development surface; never appears in product navigation or release builds.
struct DesignGallery: View {
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
                Text("CacheDrop · Component gallery").font(.headline)
                Spacer()
                Toggle("Opaque chrome", isOn: $opaque)
                AppearancePicker(choice: $appearance).labelsHidden().fixedSize()
            }.padding(CacheDropDesign.Space.lg).background { ChromeSurface() }
            ScrollView {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
                    PageHeader(title: "Native design system", subtitle: "Developer examples only · No personal storage measurements",
                               back: BackButton(destination: "Overview", action: {}))
                    Button { shellExamplesExpanded.toggle() } label: {
                        Label("Synthetic shell and appearance examples", systemImage: shellExamplesExpanded ? "chevron.down" : "chevron.right")
                    }.buttonStyle(.plain).accessibilityValue(shellExamplesExpanded ? "Expanded" : "Collapsed")
                    if shellExamplesExpanded {
                        ShellAppearanceGalleryExamples()
                        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                            Text("Synthetic category badge · Inert examples").font(.headline)
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: false, selectedCategories: 0) {}
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: true, selectedCategories: 1) {}
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: false, selectedCategories: 2) {}
                        }.frame(width: 166)
                    }
                    DisclosureGroup("Synthetic History activity examples", isExpanded: $historyExamplesExpanded) {
                        HistoryActivityGalleryExamples()
                    }
                    DisclosureGroup("Synthetic Storage trends examples", isExpanded: $growthExamplesExpanded) { GrowthGalleryExamples() }
                    DisclosureGroup("Synthetic storage alert settings", isExpanded: $alertExamplesExpanded) {
                        AlertThresholdEditor(draft: .constant("60"), canApply: true, apply: {})
                        AlertThresholdEditor(draft: .constant("invalid"), canApply: false, invalidDraft: true, apply: {})
                        AlertPermissionDetails(authorization: .denied, checked: true, settingsFeedback: "System Settings could not be opened.", openSettings: {})
                    }
                    CapacityGalleryExamples()
                    Text("Synthetic Local records entry · Inert example").font(.headline)
                    LocalRecordsEntry(action: {})
                    Text("Synthetic Protected items entry · Inert example").font(.headline)
                    ProtectedItemsEntry(action: {})
                    Text("Synthetic Local records controls · Inert enabled example").font(.headline)
                    LocalRecordsMaintenanceControls(clear: {}, reset: {})
                    StatusRow(text: "Reset is blocked by unfinished cleanup records. Open recovery review; no operations will resume automatically.", symbol: "exclamationmark.triangle", role: .caution)
                    StatusRow(text: "Downloads · Access unavailable", role: .caution, action: StatusAction(title: "Choose again…") {})
                    Text("Synthetic unavailable controls · Cleanup or maintenance in progress").font(.headline)
                    LocalRecordsMaintenanceControls(enabled: false, clear: {}, reset: {})
                    Text("Synthetic Full Disk Access row · Live status check only").font(.headline)
                    FullDiskAccessSetting()
                    // Explore storage's inspector (#320): always open, one path.
                    ExplorerInspector(name: "Camera guide.pdf") {
                        Text("Location").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("/Example/Downloads/Camera guide.pdf")
                        Text("On disk").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("8 MB")
                        Text("Why it’s listed").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Not opened since Mar 2, 2026.")
                        Text("Action").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Move to Trash. The space stays used until you empty the Trash.")
                    }.frame(height: 220)
                    ExplorerInspector(name: "Cloud metadata (synthetic)", close: {}) {
                        Text("Synthetic Gallery metadata; no provider certification.")
                        Text("On disk: Unknown")
                        Text("Cleanup action").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        Text("Cloud-managed item. Cloud cleanup is unavailable; no eviction or synced deletion is offered.")
                    }.frame(height: 220)
                    LocationScopeRow(name: "Downloads", path: "/Example/Downloads", status: "Not scanned", included: $selected, enabled: true) { Menu("More") { Button("Forget location") {} } }
                    LocationScopeRow(name: "Downloads B", path: "/Example/Downloads/Long project folder/Downloads B", status: "Location unavailable · Reconnect and recheck", overlap: "Overlaps another remembered location · Shared contents are counted once.", included: $selected, enabled: true) {
                        HStack {
                            Button("Choose again…") {}
                            Button("Reconnect and recheck") {}
                            Menu("More") { Button("Forget location") {} }
                        }
                    }.frame(maxWidth: 520)
                    LocationScopeRow(name: "Omitted Downloads", path: "/Example/Downloads/Omitted", status: "Omitted from the next scan", included: .constant(false), enabled: false) {
                        Menu("More") { Button("Forget location") {} }
                    }
                    RecommendationGroup {
                        StorageReviewRow(category: .downloads, title: "Downloads", detail: "Example only · Review exact files before moving to Trash.", value: "128 MB", meaning: "Logical files", actionTitle: "Review files", action: {})
                        Divider()
                        StorageReviewRow(category: .cloud, title: "Downloaded iCloud files", detail: "Example unknown measurement · Eviction unavailable.", value: "Unknown", meaning: "Local allocation", actionTitle: "Review iCloud inventory", action: {})
                        Divider()
                        StorageReviewRow(category: .browser, title: "Browser caches", detail: "No qualified profile inspection.", value: "Not inspected", meaning: "Unavailable")
                    }

                    SelectionSummary(value: "3 files", detail: "Example selection · No action will run", consequence: "Space stays occupied until Finder empties Trash.")
                    SelectionSummary(value: "Synthetic mixed selection", detail: "Downloads and browser caches · No action will run", consequence: "Caches are permanently removed; Downloads go to Trash.", title: "Selected for cleanup")
                    HStack(spacing: CacheDropDesign.Space.lg) {
                        ForEach(0..<5) { index in CategoryBadge(category: [StorageCategory.cloud, .developer, .downloads, .browser, .managed][index]) }
                    }
                    SettingsRow(title: "Selection states", detail: "Native controls retain focus, Space, disabled and mixed semantics.") {
                        MacroCategoryCheckbox(state: .unchecked, label: "Unchecked", enabled: true, action: {}, identifier: "galleryUnchecked")
                        MacroCategoryCheckbox(state: .mixed, label: "Mixed selection", enabled: true, action: {}, identifier: "galleryMixed")
                        MacroCategoryCheckbox(state: .checked, label: "Selected", enabled: true, action: {}, identifier: "gallerySelected")
                        MacroCategoryCheckbox(state: .unchecked, label: "Unavailable · Access required", enabled: false, action: {}, identifier: "galleryDisabled")
                        Toggle("Interactive native checkbox", isOn: $selected)
                    }
                    SummarySurface {
                        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                            StatusRow(text: "Completed selected-scope observation", symbol: "checkmark.circle", role: .success)
                            StatusRow(text: "Partial coverage · Remaining bytes unknown", symbol: "exclamationmark.circle", role: .caution)
                            StatusRow(text: "Access unavailable · Choose the folder again", symbol: "lock", role: .failure)
                            ProgressView("Reading metadata…")
                        }
                    }
                    EmptyState(title: "No findings yet", detail: "Choose a folder to begin. Unknown measurements stay distinct from zero.", symbol: "folder")
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
                        BusyAction(busy: true) { Button("Clean up") {}.buttonStyle(.borderedProminent) }
                        ReviewCleanupButton(enabled: false, focusRequest: 0, tooltip: CacheDropDesign.waitForScanHelp, action: {}).fixedSize()
                    }.controlSize(.large)
                    CapacityMeter(available: nil, total: nil)
                    SettingsRow(title: "Shared navigation and brand", detail: "Reference accents identify destinations; labels and selected traits carry meaning.") {
                        AppBrand()
                        CacheDropSidebarRow(title: "Overview", symbol: "internaldrive", selected: false) {}
                        CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: true, accent: CacheDropDesign.teal) {}
                    }
                    CategorySelectionHeader(category: .downloads, state: .mixed, title: "Downloads · Example mixed selection", detail: "The checkbox alone changes selection; filenames remain inspection controls.", size: "16 MB", enabled: true, action: {})
                    CategoryRow(category: .developer, state: .checked, title: "Developer · Example category row", detail: "Plan and Smart clean share this row; each keeps its own selection.",
                                size: "1.2 GB", enabled: true, identifier: "galleryCategoryRow", itemCount: 2, staying: 1, expanded: $categoryRowExpanded, toggle: {}) {
                        EmptyView()
                    } items: {
                        Text("Example cache").font(.callout)
                        Text("Example build files").font(.callout)
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
                    VolumeSummary(available: 40_000_000_000, total: 512_000_000_000, observation: "Synthetic gallery capacity · No category attribution")
                    VolumeSummary(available: nil, total: nil, observation: "No capacity observation · Unknown stays distinct from zero")
                }.padding(CacheDropDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.background(CacheDropDesign.reading)
            // While background work runs, its progress line takes the note's place (Decision 46).
            ActionStrip(message: "Developer gallery · Actions are inert examples") { ReviewCleanupButton(enabled: false, focusRequest: 0, action: {}) }
                .environment(\.cacheDropBackgroundWork, BackgroundWorkStatus(line: .init(parts: [.init(id: "galleryProgress", text: "Checking Example cache… 4 of 31"), .init(id: "galleryMore", text: "+1 more")])))
            ActionStrip(message: "Developer gallery · Actions are inert examples") { ReviewCleanupButton(enabled: false, focusRequest: 0, action: {}) }
                .environment(\.cacheDropBackgroundWork, BackgroundWorkStatus(line: .init(parts: [.init(id: "galleryFolderScan", text: "Scanning Downloads"), .init(id: "galleryPhase", text: "Reading file metadata…"), .init(id: "galleryCount", text: "1240 entries inspected")], runsFolderScan: true), stop: {}, returnToScan: {}))
            ActionStrip(message: "Developer gallery · Actions are inert examples") { ReviewCleanupButton(enabled: false, focusRequest: 0, action: {}) }
        }
        .environment(\.cacheDropOpaqueChrome, opaque)
        .preferredColorScheme(appearance == .automatic ? nil : appearance == .dark ? .dark : .light)
    }
}
/// Inert presentation examples reuse the live capacity components; no reads or timers.
private struct CapacityGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            example("checking", available: nil, total: nil, observation: "Startup-volume capacity", status: "Checking capacity…", refreshing: true)
            example("refreshing", observation: "Observed 10:00 AM · Available for important usage", status: "Refreshing…", refreshing: true)
            example("important", observation: "Observed 10:00 AM · Available for important usage")
            example("fallback", observation: "Observed 10:00 AM · Available capacity fallback")
            example("partial", total: nil, observation: "Observed 10:00 AM · Available capacity fallback")
            example("stale", observation: "Last observed 10:00 AM · Available for important usage", status: "Couldn’t refresh capacity", retry: true)
            example("unavailable", available: nil, total: nil, observation: "Capacity unavailable", status: "Couldn’t refresh capacity", retry: true)
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

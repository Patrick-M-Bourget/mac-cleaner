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
    @State private var mapExamplesExpanded = false
    @State private var alertExamplesExpanded = false
    @State private var categoryRowExpanded = false
    @State private var applicationsSectionExpanded = true
    @State private var audioSectionExpanded = true
    @State private var makerGroupExpanded = true
    @State private var onboardingExpanded = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: CacheDropDesign.Space.sm) {
                Text("CacheDrop · Component gallery").font(CacheDropDesign.TypeStyle.section).accessibilityIdentifier("designGalleryTitle")
                Spacer()
                Toggle("Opaque chrome", isOn: $opaque).accessibilityIdentifier("galleryOpaqueChrome")
                AppearancePicker(choice: $appearance).labelsHidden().fixedSize()
                CloseButton(label: "Close Design gallery", identifier: "closeDesignGallery") { dismissWindow(id: "design-gallery") }
            }.padding(CacheDropDesign.Space.lg).background { ChromeSurface() }
            ScrollView {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
                    PageHeader(title: "Native design system", subtitle: "Developer examples only · No personal storage measurements",
                               back: BackButton(destination: "Overview", action: {}))
                    // A navigation trail (Decision 150): quiet steps, the one on show in primary, a long name truncated in the middle.
                    HStack(spacing: CacheDropDesign.Space.sm) {
                        QuietLink(title: "Scanned folders") {}
                        Image(systemName: "chevron.right").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        QuietLink(title: "Music") {}
                        Image(systemName: "chevron.right").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        QuietLink(title: "Logic Pro Projects archived from the old studio drive", current: true) {}
                    }.font(CacheDropDesign.TypeStyle.note)
                    // Onboarding's two steps (#783), each at its real sheet size: Welcome, then one sheet that scans and shows what it found.
                    ActionDisclosureGroup("Onboarding · Synthetic examples", isExpanded: $onboardingExpanded) { OnboardingGalleryExamples() }
                        .accessibilityIdentifier("galleryOnboarding")
                    ActionDisclosureGroup(isExpanded: $shellExamplesExpanded, identifier: "galleryShellExamples") {
                        ShellAppearanceGalleryExamples()
                        // #777, Decision 182: sidebar rows carry no count badge, selected or not.
                        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                            Text("Synthetic sidebar rows · Inert examples").font(CacheDropDesign.TypeStyle.section)
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: false, accent: CacheDropDesign.teal) {}
                            CacheDropSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: true, accent: CacheDropDesign.teal) {}
                        }.frame(width: CacheDropDesign.Size.sidebarWidth).background { ChromeSurface(role: .sidebar) }
                    } label: { Text("Synthetic shell and appearance examples") }
                    ActionDisclosureGroup("Synthetic History activity examples", isExpanded: $historyExamplesExpanded) {
                        HistoryActivityGalleryExamples()
                    }
                    ActionDisclosureGroup("Synthetic Storage trends examples", isExpanded: $growthExamplesExpanded) { StorageTrendsGalleryExamples() }
                    ActionDisclosureGroup("Synthetic storage map examples", isExpanded: $mapExamplesExpanded) { StorageMapGalleryExamples() }
                    ActionDisclosureGroup("Synthetic storage alert settings", isExpanded: $alertExamplesExpanded) {
                        // #778, Decision 183: a Settings group is the Form's own header and one footer; a toggle's detail is its caption.
                        Form {
                            Section {
                                Toggle(isOn: .constant(true)) {
                                    Text("Notify me when space is low")
                                    Text("CacheDrop checks free space about every 15 minutes while it’s open").font(CacheDropDesign.TypeStyle.caption)
                                }
                                Toggle(isOn: .constant(false)) {
                                    Text("Remind me weekly to clean up")
                                    Text("Sent when your last scan that week found at least 1 GB ready to clean").font(CacheDropDesign.TypeStyle.caption)
                                }
                            } header: {
                                Text("Notifications")
                            } footer: {
                                Text("CacheDrop never scans or cleans in the background").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                            }
                        }.formStyle(.grouped).frame(width: CacheDropDesign.Size.sheetNarrow).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("gallerySettingsGroup")
                        AlertThresholdEditor(draft: .constant("60"), canApply: true, apply: {})
                        AlertThresholdEditor(draft: .constant("invalid"), canApply: false, invalidDraft: true, apply: {})
                        AlertPermissionDetails(authorization: .denied, checked: true, settingsFeedback: "System Settings could not be opened.", openSettings: {})
                    }
                    // Help → What’s New (#553, Decision 161): the notes, and a development build without its version's notes.
                    Text("Synthetic What’s New · Inert examples").font(CacheDropDesign.TypeStyle.section)
                    WhatsNewContent(notes: .success(ReleaseNotes(version: "9.9.9", summary: "An example summary sentence about this version.",
                                                                 changes: ["An example change that wraps onto a second line because it is long enough to.", "A second example change."])),
                                    version: "9.9.9").frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading)
                    WhatsNewContent(notes: .failure(ReleaseNotesError.notBundled), version: "9.9.9")
                        .frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading)
                    CapacityGalleryExamples()
                    Text("Synthetic Saved data entry · Inert example").font(CacheDropDesign.TypeStyle.section)
                    SavedDataEntry(action: {})
                    Text("Synthetic Protected items entry · Inert example").font(CacheDropDesign.TypeStyle.section)
                    ProtectedItemsEntry(action: {})
                    Text("Synthetic Saved data controls · Inert enabled example").font(CacheDropDesign.TypeStyle.section)
                    SavedDataMaintenanceControls(clear: {}, reset: {})
                    StatusRow(text: "Reset waits until the interrupted cleanup is reviewed.", symbol: "exclamationmark.triangle", role: .caution)
                    StatusRow(text: "Downloads · Access unavailable", role: .caution, action: StatusAction(title: "Choose again…") {})
                    StatusRow(text: "Synth is open, so its caches will be skipped · 1.2 GB", symbol: "exclamationmark.circle", role: .caution,
                              action: StatusAction(title: "Quitting…", isDisabled: true) {})
                    // #772: every quiet status line is a StatusRow; several links join with "·", and a line can name what it sums up.
                    Text("Status lines · One StatusRow").font(CacheDropDesign.TypeStyle.section)
                    StatusRow(text: "Trash holds 4.2 GB · 1.2 GB from CacheDrop", symbol: "trash", identifier: "galleryTrashLine",
                              actions: [StatusAction(title: "Empty from Trash…") {}, StatusAction(title: "Empty Trash…") {}])
                    StatusRow(text: "2 locations need Full Disk Access", symbol: "lock.shield", detail: "Example cache, Example mail downloads",
                              action: StatusAction(title: "Learn more") {})
                    StatusRow(text: "Downloads · Access unavailable", role: .caution, action: StatusAction(title: "Locations") {})
                    SettingsUnreadableNotice.line(scanning: false) {}
                    Text("Synthetic unavailable controls · Cleanup or maintenance in progress").font(CacheDropDesign.TypeStyle.section)
                    SavedDataMaintenanceControls(enabled: false, clear: {}, reset: {})
                    Text("Full Disk Access · Inert example").font(CacheDropDesign.TypeStyle.section)
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
                    LocationScopeRow(name: "Projects", path: "/Example/Projects", status: "Not scanned", included: $selected, enabled: true) {
                        Menu("More") { Button("Forget location") {} }.menuStyle(.borderlessButton).fixedSize()
                    }
                    LocationScopeRow(name: "Downloads B", path: "/Example/Downloads/Long project folder/Downloads B", status: "Location unavailable · Reconnect it, then scan again", overlap: "Overlaps another remembered location · Shared contents are counted once.", included: $selected, enabled: true) {
                        // A row's actions are links, as on Locations (Decision 65 rule 3).
                        HStack(spacing: CacheDropDesign.Space.sm) {
                            Button("Choose again…") {}.buttonStyle(.link)
                            Button("Scan again") {}.buttonStyle(.link)
                            Menu("More") { Button("Forget location") {} }.menuStyle(.borderlessButton).fixedSize()
                        }
                    }.frame(maxWidth: CacheDropDesign.Size.sheetNarrow)
                    LocationScopeRow(name: "Omitted Downloads", path: "/Example/Downloads/Omitted", status: "Omitted from the next scan", included: .constant(false), enabled: false) {
                        Menu("More") { Button("Forget location") {} }.menuStyle(.borderlessButton).fixedSize()
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
                    // Smart clean's card (#779, Decision 173): the same component, titled "Free up".
                    SelectionSummary(value: "Up to 2.4 GB", detail: "12 items selected", title: SmartCleanSummary.title)
                    HStack(spacing: CacheDropDesign.Space.lg) {
                        ForEach(0..<9) { index in CategoryBadge(category: [StorageCategory.cloud, .developer, .downloads, .browser, .managed, .appCaches, .audioSoftware, .photoVideo, .leftovers][index]) }
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
                            Text("Workspace behind onboarding").frame(maxWidth: .infinity, minHeight: CacheDropDesign.Space.page)
                                .modifier(OnboardingBackdrop(active: true))
                        }
                    }
                    // #311: one button rule, one example of each kind.
                    Text("Buttons · One rule").font(CacheDropDesign.TypeStyle.section)
                    ButtonRuleGalleryExamples()
                    Text("Search and Sort · In the page header, in the list’s header").font(CacheDropDesign.TypeStyle.section)
                    ListHeaderGalleryExamples()
                    // #321: one empty state, saying what's true with at most one action that leads where the user can act.
                    Text("Empty states · One way forward").font(CacheDropDesign.TypeStyle.section)
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
                    Text("Waiting for a scan · Skeleton rows").font(CacheDropDesign.TypeStyle.section)
                    SkeletonRows(.category, count: 2, identifier: "gallerySkeletonCategory")
                    SkeletonRows(.review, count: 2, identifier: "gallerySkeletonReview")
                    SkeletonRows(.line, count: 2, identifier: "gallerySkeletonLine")
                    Text("Waiting for a scan · Rows from the last scan").font(CacheDropDesign.TypeStyle.section)
                    CategoryRow(category: .browser, state: .unchecked, title: "Browser caches · Example during a rescan", detail: "Dimmed, and can’t be clicked until the scan ends.",
                                size: "640 MB", enabled: false, identifier: "galleryWaitingRow", itemCount: nil, expanded: .constant(false), toggle: {}) {
                        EmptyView()
                    } items: { EmptyView() }.waitingForScan(true)
                    Text("Busy action · Checks running after a click").font(CacheDropDesign.TypeStyle.section)
                    HStack(spacing: CacheDropDesign.Space.sm) {
                        BusyAction(busy: true) { Button("Clean up") {}.buttonStyle(.borderedProminent).accessibilityIdentifier("galleryBusyAction") }
                        BusyAction(busy: false) { Button("Clean up") {}.buttonStyle(.borderedProminent).accessibilityIdentifier("galleryIdleAction") }
                        ReviewCleanupButton(enabled: false, focusRequest: 0, tooltip: CacheDropDesign.waitForScanHelp, action: {}).fixedSize()
                    }.controlSize(.large)
                    // Decision 126: the review sheet opens at the click and shows its checks running (#565).
                    Text("Review sheet · Checks running").font(CacheDropDesign.TypeStyle.section)
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
                    // Smart clean's Worth a look (#780, Decision 178): a section title over the row Applications draws, holding the files from deleted apps Smart clean doesn't tick.
                    Text(WorthALook.title).font(CacheDropDesign.TypeStyle.section).accessibilityAddTraits(.isHeader)
                    CategoryRow(category: .leftovers, state: .unchecked, title: CatalogCategory.leftovers.overviewTitle, detail: CatalogCategory.leftovers.overviewDetail,
                                size: "84 MB", enabled: true, identifier: "galleryWorthALookRow", itemCount: 3, expanded: .constant(false), toggle: {}) {
                        EmptyView()
                    } items: { EmptyView() }
                    // A row whose owner is open (#138): its line in the row's notice, its link at the row-link size.
                    CategoryRow(category: .developer, state: .checked, title: "Example build files", detail: "Example tool caches", size: "640 MB", enabled: true,
                                identifier: "galleryRunningRow", itemCount: nil, expanded: .constant(false), toggle: {}) {
                        StatusRow(text: "Example app is open", symbol: "exclamationmark.circle", role: .caution, action: StatusAction(title: "Quit Example app") {})
                    } items: { EmptyView() }
                    // Its apps not opened in 6 months (#781, Decision 188): the Apps badge, Choose apps, each app's row with when it was last opened.
                    CategoryRow(category: .apps, state: .unchecked, title: WorthALook.appsTitle, detail: "", size: "1.4 GB", enabled: true,
                                identifier: "galleryWorthALookApps", itemCount: 1, chooseNoun: "apps", expanded: .constant(true), toggle: {}) { EmptyView() } items: {
                        CategoryRow(category: .apps, state: .unchecked, title: "Example app", detail: WorthALook.lastOpenedText(Date(timeIntervalSince1970: 1_773_000_000)),
                                    size: "1.4 GB", enabled: true, identifier: "galleryWorthALookApp", itemCount: nil, expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
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
                    // An Applications section (Decision 153): a category row with no checkbox, its rows behind "Choose apps · N".
                    CategoryRow(category: .apps, state: nil, title: "Example section", detail: "Apps in your Applications folders", size: "812 MB", enabled: true,
                                identifier: "galleryApplicationsSection", itemCount: 1, chooseNoun: "apps", expanded: $applicationsSectionExpanded, toggle: {}) { EmptyView() } items: {
                        CategoryRow(category: .apps, state: nil, title: "Example app in a section", detail: "Example maker", size: "800 MB", enabled: true,
                                    identifier: "galleryApplicationsSectionRow", itemCount: nil, expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
                    }
                    // A section that found nothing is one row, Empty muted in its size column, as on Overview (Decision 176).
                    CategoryRow(category: .leftovers, state: nil, title: "Example empty section", detail: "Settings and data they left behind", size: "Empty", enabled: true,
                                identifier: "galleryEmptySection", itemCount: nil, mutedSize: true, expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
                    // Audio software opens straight to its groups, behind "Show groups · N"; its groups and makers are category rows with
                    // no checkbox and no badge, their titles on the rows' text column (Decisions 151, 153, 175).
                    CategoryRow(category: .audioSoftware, state: nil, title: "Example audio section", detail: "DAWs and apps, plug-ins, sounds and drivers", size: "8.7 GB",
                                enabled: true, identifier: "galleryAudioSection", itemCount: 3, chooseVerb: "Show", chooseNoun: "groups",
                                expanded: $audioSectionExpanded, toggle: {}) { EmptyView() } items: {
                        VStack(alignment: .leading, spacing: 0) {
                            CategoryRow(category: .audioSoftware, state: nil, title: "Example maker", detail: "", size: "2.4 GB", enabled: true,
                                        identifier: "galleryMakerGroup", itemCount: 2, chooseNoun: "plug-ins", showsBadge: false, expanded: $makerGroupExpanded, toggle: {}) { EmptyView() } items: {
                                CategoryRow(category: .audioSoftware, state: .unchecked, title: "Example plug-in", detail: "Example maker", size: "1.9 GB", enabled: true,
                                            identifier: "galleryMakerGroupProduct", itemCount: nil, expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
                                CategoryRow(category: .audioSoftware, state: .unchecked, title: "Another example plug-in", detail: "Example maker", size: "500 MB", enabled: true,
                                            identifier: "galleryMakerGroupProduct2", itemCount: nil, expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
                            }
                            Divider().padding(.vertical, CacheDropDesign.Space.md)
                            // A group where nothing can be ticked says Show (Decision 154).
                            CategoryRow(category: .audioSoftware, state: nil, title: "Example read-only group", detail: "", size: "6.3 GB", enabled: true,
                                        identifier: "galleryShowGroup", itemCount: 3, chooseVerb: "Show", chooseNoun: "sounds", showsBadge: false,
                                        expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
                            Divider().padding(.vertical, CacheDropDesign.Space.md)
                            // A group that found nothing reads Empty, with no disclosure (Decision 176).
                            CategoryRow(category: .audioSoftware, state: nil, title: "Example empty group", detail: "", size: "Empty", enabled: true,
                                        identifier: "galleryEmptyGroup", itemCount: nil, showsBadge: false, mutedSize: true,
                                        expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
                        }
                    }
                    // A read-only sound row; its vendor's installed manager can remove or move it (Decision 157).
                    InspectableItemRow(name: "Example sample library", detail: "Example maker", size: "4.1 GB", symbol: "waveform", inspected: false, inspect: nil,
                                       reveal: {}, revealIdentifier: "gallerySoundReveal",
                                       status: StatusRow(text: "Example manager can remove or move it", symbol: "shippingbox", identifier: "gallerySoundManager",
                                                         action: StatusAction(title: "Open Example manager", identifier: "gallerySoundOpen") {})) { EmptyView() }
                    // A driver the user can move: its place and Reveal in Finder before it's ticked (Decision 158).
                    CategoryRow(category: .audioSoftware, state: .unchecked, title: "Example driver", detail: "Example maker", size: "4 MB", enabled: true,
                                identifier: "galleryDriverRow", itemCount: nil, expanded: .constant(false), toggle: {}) {
                        StatusRow(text: "…/Plug-Ins/HAL", symbol: "folder", action: StatusAction(title: "Reveal in Finder", action: {}))
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
            // A cleanup running: its note may wrap, and Stop cleanup is the bar's one action.
            CleanupStopStrip(stopRequested: false, stop: {})
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("designGallery")
        .cacheDropButtonRule()
        .environment(\.cacheDropOpaqueChrome, opaque)
        .preferredColorScheme(appearance == .automatic ? nil : appearance == .dark ? .dark : .light)
    }
}
/// Onboarding's steps (#783, #784) with synthetic data: Welcome, Scanning with 4 of 10 categories read, the same on later launches,
/// Ready and Nothing found.
private struct OnboardingGalleryExamples: View {
    @State private var sharing = false
    private static let categories = Onboarding.categories
    private static let found: [(CatalogCategory, Int64)] = [(.developer, 3_900_000_000), (.browser, 1_600_000_000), (.system, 800_000_000),
                                                             (.downloads, 300_000_000), (.logs, 200_000_000)]
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            example("Welcome", "welcome") {
                OnboardingWelcomeStep(categories: Self.categories, onStart: {}, onClose: {})
            }
            example("Scanning · 4 of 10 categories read", "scanning") {
                step(.scanning(found: 2_700_000_000, finished: Set(Self.categories.prefix(4))))
            }
            example("Later launches · Scanning, 4 of 10 categories read", "laterLaunch") {
                OnboardingScanStep(categories: Self.categories, phase: .scanning(found: 2_700_000_000, finished: Set(Self.categories.prefix(4))),
                                   introduction: false, sharesSetupProgress: $sharing, onStartSmartClean: {}, onViewOverview: {}, onClose: {})
            }
            example("Ready", "ready") {
                step(.ready(found: Self.found.reduce(0) { $0 + $1.1 },
                            top: Self.found.prefix(3).map { .init(category: $0.0, estimate: .measured($0.1)) }))
            }
            example("Nothing found", "nothingFound") { step(.nothingFound) }
        }.padding(.top, CacheDropDesign.Space.md)
    }
    private func step(_ phase: OnboardingScanStep.Phase) -> some View {
        OnboardingScanStep(categories: Self.categories, phase: phase, sharesSetupProgress: $sharing, onStartSmartClean: {}, onViewOverview: {}, onClose: {})
    }
    /// A sheet on the gallery's page, outlined so its real size reads true in a window shot.
    private func example(_ title: String, _ name: String, @ViewBuilder sheet: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            Text(title).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            sheet().clipShape(RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface)).overlay {
                RoundedRectangle(cornerRadius: CacheDropDesign.Radius.surface).strokeBorder(CacheDropDesign.separator, lineWidth: CacheDropDesign.Stroke.fine)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("onboardingGallery-" + name)
    }
}
/// Inert presentation examples reuse the live capacity components; no reads or timers.
private struct CapacityGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            example("checking", available: nil, total: nil, observation: "Checking free space…", status: "Checking free space…", refreshing: true)
            example("refreshing", observation: "Updated 10:00 AM", status: "Refreshing…", refreshing: true)
            example("important", observation: "Updated 10:00 AM")
            example("fallback", observation: "Updated 10:00 AM")
            example("partial", total: nil, observation: "Updated 10:00 AM")
            example("stale", observation: "Last updated 10:00 AM", status: "Couldn’t refresh free space", retry: true)
            example("unavailable", available: nil, total: nil, observation: "Free space unknown", status: "Couldn’t refresh free space", retry: true)
        }
    }
    private func example(_ name: String, available: Int64? = 40_000_000_000, total: Int64? = 512_000_000_000, observation: String, status: String = "", refreshing: Bool = false, retry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
            Text("Synthetic capacity " + name + " · Inert example").font(CacheDropDesign.TypeStyle.section)
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
            Button("Clear completed history…") {}
            Text("Row and status line · Link").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            StatusRow(text: "Downloads · Access unavailable", role: .caution, action: StatusAction(title: "Choose again…") {})
            Text("Sheet footer · Large capsules, Cancel then the primary button").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            SummarySurface {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
                    SheetHeader(title: "Example sheet", subtitle: "Every sheet titles with SheetHeader", close: CloseButton {})
                    Divider()
                    SheetFooter { Button("Cancel") {}; Button("Clean up") {}.buttonStyle(.borderedProminent) }
                }
            }.frame(maxWidth: CacheDropDesign.Size.sheetNarrow)
            Text("Bottom bar · Large capsules").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            ActionStrip(message: "Example note") { Button("Scan again") {}; Button("Review plan") {}.buttonStyle(.borderedProminent) }
            // #776, Decision 181: Locations' actions are in the bar, both regular, Scan again last.
            Text("Locations · Bottom bar").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            ActionStrip(message: nil) { Button("Add folder…") {}; Button("Scan again") {} }
            // #782, Decision 177: while a run's items wait in the Trash, Results leads with Empty from Trash…; its line keeps Open Trash.
            Text("Results · Items still in the Trash").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            TrashLine(text: nil, identifier: "galleryResultsTrash")
            ActionStrip(message: nil) { Button("View history") {}; Button("Start a new plan") {}; Button("Empty from Trash…") {}.buttonStyle(.borderedProminent) }
        }
    }
}
/// A page's search on its header's right, then a list's sortable column header (#352): click a column to sort by it, again to flip it.
private struct ListHeaderGalleryExamples: View {
    @State private var search = ""
    @State private var sort = ListSort()
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.md) {
            // A page's search sits on the title's right (Applications, Explore storage).
            PageHeader(title: "Example page", subtitle: "Search on the right; sort by clicking a column of the list’s header",
                       search: PageSearchField(label: "Search the example list", prompt: "Name or maker", text: $search, identifier: "gallerySearch"))
            // The plan's and Applications' preset (#765): Name over the rows' titles, Size over their sizes.
            ColumnHeader.categoryRows(sort: $sort, identifier: "gallerySort")
            ForEach(sort.ordered(Self.rows, name: \.name, bytes: \.bytes), id: \.name) { row in
                CategoryRow(category: .downloads, state: .unchecked, title: row.name, detail: "", size: SizeFormatter.text(row.bytes), enabled: true,
                            identifier: "gallerySortRow-" + row.name, itemCount: nil, expanded: .constant(false), toggle: {}) { EmptyView() } items: { EmptyView() }
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
            Text("Synthetic appearance controls · Inert examples").font(CacheDropDesign.TypeStyle.section)
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

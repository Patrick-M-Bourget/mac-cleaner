import SwiftUI
import StillCore

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
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Still · Component gallery").font(.headline)
                Spacer()
                Toggle("Opaque chrome", isOn: $opaque)
                AppearancePicker(choice: $appearance).labelsHidden().fixedSize()
            }.padding(StillDesign.Space.lg).background { ChromeSurface() }
            ScrollView {
                VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                    PageHeader(title: "Native design system", subtitle: "Developer examples only · No personal storage measurements")
                    Button { shellExamplesExpanded.toggle() } label: {
                        Label("Synthetic shell and appearance examples", systemImage: shellExamplesExpanded ? "chevron.down" : "chevron.right")
                    }.buttonStyle(.plain).accessibilityValue(shellExamplesExpanded ? "Expanded" : "Collapsed")
                    if shellExamplesExpanded {
                        ShellAppearanceGalleryExamples()
                        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                            Text("Synthetic category badge · Inert examples").font(.headline)
                            StillSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: false, selectedCategories: 0) {}
                            StillSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: true, selectedCategories: 1) {}
                            StillSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: false, selectedCategories: 2) {}
                        }.frame(width: 166)
                    }
                    DisclosureGroup("Synthetic History activity examples", isExpanded: $historyExamplesExpanded) {
                        HistoryActivityGalleryExamples()
                    }
                    DisclosureGroup("Synthetic Storage trends examples", isExpanded: $growthExamplesExpanded) { GrowthGalleryExamples() }
                    DisclosureGroup("Synthetic storage alert settings", isExpanded: $alertExamplesExpanded) {
                        AlertThresholdEditor(draft: .constant("60"), appliedBytes: 40_000_000_000, hasCurrentTotal: true, canApply: true, apply: {})
                        AlertThresholdEditor(draft: .constant("invalid"), appliedBytes: 40_000_000_000, hasCurrentTotal: true, canApply: false, invalidDraft: true, apply: {})
                        AlertThresholdEditor(draft: .constant("invalid"), appliedBytes: 40_000_000_000, hasCurrentTotal: false, canApply: false, apply: {})
                        AlertPermissionDetails(authorization: .unknown, checked: true, openSettings: {})
                        AlertPermissionDetails(authorization: .denied, checked: true, settingsFeedback: "System Settings could not be opened.", openSettings: {})
                        QuietAlertExplanation(expanded: .constant(true))
                    }
                    CapacityGalleryExamples()
                    Text("Synthetic Local records entry · Inert example").font(.headline)
                    LocalRecordsEntry(action: {})
                    Text("Synthetic Local records controls · Inert enabled example").font(.headline)
                    LocalRecordsMaintenanceControls(clear: {}, reset: {})
                    StatusRow(text: "Reset is blocked by unfinished cleanup records. Open recovery review; no operations will resume automatically.", symbol: "exclamationmark.triangle", role: .caution)
                    Text("Synthetic unavailable controls · Cleanup or maintenance in progress").font(.headline)
                    LocalRecordsMaintenanceControls(enabled: false, clear: {}, reset: {})
                    Text("Synthetic future-gated diagnostics entry · Inert example").font(.headline)
                    LocalRecordsDiagnosticsEntry(action: {})
                    Text("Synthetic Full Disk Access row · Live status check only").font(.headline)
                    FullDiskAccessSetting()
                    NotAccessibleRow(title: "Safari cache")
                    CategoryPrerequisite(title: "Not scanned", detail: "Scan the included Downloads locations before choosing files.", actionTitle: "Scan Downloads…", enabled: true, action: {})
                    CategoryPrerequisite(title: "No eligible files", detail: "No eligible files in this inspected location.", actionTitle: "Scan Downloads again", enabled: true, action: {})
                    ExplorerInspector(name: "Camera guide.pdf", close: {}) {
                        Text("Location").font(.caption).foregroundStyle(.secondary)
                        Text("/Example/Downloads/Camera guide.pdf")
                        Text("Observed scope").font(.caption).foregroundStyle(.secondary)
                        Text("/Example/Downloads")
                        Text("On disk: 8 MB observed")
                        Text("Logical size: 8 MB")
                        Text("Why listed").font(.caption).foregroundStyle(.secondary)
                        Text("Observed during a manual scan")
                        Text("Cleanup action").font(.caption).foregroundStyle(.secondary)
                        Text("Move this exact file to Trash after selection and confirmation.")
                    }.frame(height: 220)
                    ExplorerInspector(name: "Cloud metadata (synthetic)", close: {}) {
                        Text("Synthetic Gallery metadata; no provider certification.")
                        Text("On disk: Unknown")
                        Text("Cleanup action").font(.caption).foregroundStyle(.secondary)
                        Text("Cloud-managed item. Cloud cleanup is unavailable; no eviction or synced deletion is offered.")
                    }.frame(height: 220)
                    ToolbarScanStatus(location: "Downloads", returnToScan: {}, stop: {})
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
                    HStack(spacing: StillDesign.Space.lg) {
                        ForEach(0..<5) { index in CategoryBadge(category: [StorageCategory.cloud, .developer, .downloads, .browser, .managed][index]) }
                    }
                    SettingsRow(title: "Selection states", detail: "Native controls retain focus, Space, disabled and mixed semantics.") {
                        MacroCategoryCheckbox(state: .unchecked, label: "Unchecked", enabled: true, action: {}, identifier: "galleryUnchecked")
                        MacroCategoryCheckbox(state: .mixed, label: "Mixed selection", enabled: true, action: {}, identifier: "galleryMixed")
                        MacroCategoryCheckbox(state: .checked, label: "Selected", enabled: true, action: {}, identifier: "gallerySelected")
                        MacroCategoryCheckbox(state: .unchecked, label: "Unavailable · Access required", enabled: false, action: {}, identifier: "galleryDisabled")
                        Toggle("Interactive native checkbox", isOn: $selected)
                    }
                    FindingRow(category: .downloads, title: "Downloads", detail: "Example category", consequence: "Move exact files to Trash; space stays occupied until emptied.") { Button("Choose items") {} }
                    SummarySurface {
                        VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                            StatusRow(text: "Completed selected-scope observation", symbol: "checkmark.circle", role: .success)
                            StatusRow(text: "Partial coverage · Remaining bytes unknown", symbol: "exclamationmark.circle", role: .caution)
                            StatusRow(text: "Access unavailable · Choose the folder again", symbol: "lock", role: .failure)
                            ProgressView("Reading metadata…")
                        }
                    }
                    ScanProgressSummary(inspectedEntries: 1240, logicalSubtotal: "16 MB", recentNames: ["Example document.pdf", "Example archive.zip"])
                    ScanProgressSummary(inspectedEntries: 2480, logicalSubtotal: "16 MB", recentNames: ["Example document.pdf"], phaseMessage: "Rechecking changed coverage (one attempt)…")
                    EmptyState(title: "No findings yet", detail: "Choose a folder to begin. Unknown measurements stay distinct from zero.", symbol: "folder")
                    CapacityMeter(available: nil, total: nil)
                    SettingsRow(title: "Shared navigation and brand", detail: "Reference accents identify destinations; labels and selected traits carry meaning.") {
                        AppBrand()
                        StillSidebarRow(title: "Overview", symbol: "internaldrive", selected: false) {}
                        StillSidebarRow(title: "Cleanup plan", symbol: "checklist", selected: true, accent: StillDesign.teal) {}
                    }
                    CategorySelectionHeader(category: .downloads, state: .mixed, title: "Downloads · Example mixed selection", detail: "The checkbox alone changes selection; filenames remain inspection controls.", size: "16 MB", enabled: true, action: {})
                    VolumeSummary(available: 40_000_000_000, total: 512_000_000_000, observation: "Synthetic gallery capacity · No category attribution")
                    VolumeSummary(available: nil, total: nil, observation: "No capacity observation · Unknown stays distinct from zero")
                }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.background(StillDesign.reading)
            ActionStrip(message: "Developer gallery · Actions are inert examples") { ReviewCleanupButton(enabled: false, focusRequest: 0, action: {}) }
        }
        .environment(\.stillOpaqueChrome, opaque)
        .preferredColorScheme(appearance == .automatic ? nil : appearance == .dark ? .dark : .light)
    }
}
/// Inert presentation examples reuse the live capacity components; no reads or timers.
private struct CapacityGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
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
        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
            Text("Synthetic capacity " + name + " · Inert example").font(.headline)
            VolumeSummary(available: available, total: total, observation: observation, status: status,
                          refreshTitle: retry ? "Try again" : "Refresh capacity", refreshing: refreshing, refresh: {})
        }.accessibilityElement(children: .contain).accessibilityIdentifier("capacityGallery-" + name)
    }
}
private struct ShellAppearanceGalleryExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            Text("Synthetic monitoring footer · Inert examples").font(.headline)
            ForEach(Array([AlertShellState.off, .checking, .on, .snoozed(until: Date(timeIntervalSince1970: 2_000_000)), .attention(.capacityUnavailable), .attention(.savedStateUnavailable), .attention(.submissionFailed)].enumerated()), id: \.offset) { index, state in
                VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                    Text("Monitoring example " + String(index)).font(.caption)
                    MonitoringFooter(state: state, openDetails: {}).frame(width: 142)
                    MonitoringDetails(state: state, effective: [.on, .snoozed(until: Date(timeIntervalSince1970: 2_000_000)), .attention(.capacityUnavailable)].contains(state))
                }.accessibilityElement(children: .contain).accessibilityIdentifier("monitoringGallery-" + String(index))
            }
            Text("Synthetic appearance controls · Inert examples").font(.headline)
            ForEach(Array([AppearancePreferenceController.Notice?.none, .invalidSavedValue, .unreadable, .saveFailed].enumerated()), id: \.offset) { index, notice in
                VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                    Text("Appearance notice example " + String(index)).font(.caption)
                    AppearancePreferenceNotice(notice: notice, retry: {})
                }.accessibilityElement(children: .contain).accessibilityIdentifier("appearanceGallery-" + String(index))
            }
        }
    }
}

#endif

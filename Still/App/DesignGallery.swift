import SwiftUI
import StillCore

#if DEBUG
/// Explicit development surface; never appears in product navigation or release builds.
struct DesignGallery: View {
    @State private var appearance = "Light"
    @State private var opaque = false
    @State private var selected = true
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Still · Component gallery").font(.headline)
                Spacer()
                Toggle("Opaque chrome", isOn: $opaque)
                Picker("Appearance", selection: $appearance) { Text("Light").tag("Light"); Text("Dark").tag("Dark") }.labelsHidden().frame(width: 100).accessibilityLabel("Appearance")
            }.padding(StillDesign.Space.lg).background { ChromeSurface() }
            ScrollView {
                VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                    PageHeader(title: "Native design system", subtitle: "Developer examples only · No personal storage measurements")
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
                    CleanupScopeNotice(chooseDownloads: {})
                    CleanupScopeNotice(enabled: false, chooseDownloads: {})
                    CleanupScopeNotice(compact: true, chooseDownloads: {})
                    RecommendationGroup {
                        StorageReviewRow(category: .downloads, title: "Downloads", detail: "Example only · Review exact files before moving to Trash.", value: "128 MB", meaning: "Logical files", actionTitle: "Review files", action: {})
                        Divider()
                        StorageReviewRow(category: .cloud, title: "Downloaded iCloud files", detail: "Example unknown measurement · Eviction unavailable.", value: "Unknown", meaning: "Local allocation", actionTitle: "Review iCloud inventory", action: {})
                        Divider()
                        StorageReviewRow(category: .browser, title: "Browser caches", detail: "No qualified profile inspection.", value: "Not inspected", meaning: "Unavailable")
                    }

                    SelectionSummary(value: "3 files", detail: "Example selection · No action will run", consequence: "Space stays occupied until Finder empties Trash.")
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
        .preferredColorScheme(appearance == "Dark" ? .dark : .light)
    }
}
#endif

/// Explicit debug-only review settings do not alter macOS accessibility preferences.
struct DesignAccessibilityPreview: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content.environment(\.stillOpaqueChrome, ProcessInfo.processInfo.arguments.contains("--design-opaque-chrome"))
        #else
        content
        #endif
    }
}

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
                Picker("Appearance", selection: $appearance) { Text("Light").tag("Light"); Text("Dark").tag("Dark") }.frame(width: 120)
            }.padding(StillDesign.Space.lg).background { ChromeSurface() }
            ScrollView {
                VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
                    PageHeader(title: "Native design system", subtitle: "Developer examples only · No personal storage measurements")
                    SelectionSummary(value: "3 files", detail: "Example selection · No action will run")
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
                    EmptyState(title: "No findings yet", detail: "Choose a folder to begin. Unknown measurements stay distinct from zero.", symbol: "folder")
                    CapacityMeter(available: nil, total: nil)
                }.padding(StillDesign.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.background(StillDesign.reading)
            ActionStrip(message: "Developer gallery · Actions are inert examples") { Button("Review cleanup") {}.disabled(true) }
        }
        .environment(\.stillOpaqueChrome, opaque)
        .preferredColorScheme(appearance == "Dark" ? .dark : .light)
    }
}
#endif

/// Explicit debug-only review settings do not alter macOS accessibility preferences.
struct DesignAccessibilityPreview: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        #if DEBUG
        content.environment(\.stillOpaqueChrome, ProcessInfo.processInfo.arguments.contains("--design-opaque-chrome"))
            .environment(\.colorSchemeContrast, ProcessInfo.processInfo.arguments.contains("--design-increased-contrast") ? .increased : contrast)
        #else
        content
        #endif
    }
}

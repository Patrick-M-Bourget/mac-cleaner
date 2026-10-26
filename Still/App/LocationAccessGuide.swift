import SwiftUI

/// Contextual education only; this view does not inspect folders or request permissions.
struct LocationAccessGuide: View {
    @Binding var expanded: Bool

    var body: some View {
        DisclosureGroup("About folder access", isExpanded: $expanded) {
            SettingsRow(title: "Your chosen folders", detail: "Still can inspect folders you explicitly choose. macOS may restrict protected locations; uninspected bytes remain unknown.") {
                FullDiskAccessSetting()
            }
        }
        .padding(.leading, StillDesign.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI

/// Contextual education only; this view does not inspect or request permissions.
struct LocationAccessGuide: View {
    @Binding var expanded: Bool

    var body: some View {
        DisclosureGroup("About folder access", isExpanded: $expanded) {
            SettingsRow(title: "Your chosen folders", detail: "Still can inspect folders you explicitly choose. macOS may restrict protected locations; uninspected bytes remain unknown.") {
                VStack(alignment: .leading, spacing: StillDesign.Space.md) {
                    StatusRow(text: "Full Disk Access is optional. It broadly exposes protected data and is not a read-only grant.", symbol: "lock.shield")
                    Text("It does not make protected files eligible for cleanup. Still’s cleanup rules stay the same.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Manage this manually in System Settings → Privacy & Security → Full Disk Access.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, StillDesign.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

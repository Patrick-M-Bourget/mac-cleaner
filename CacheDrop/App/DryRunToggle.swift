import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// The Settings dry run. Off by default (Decision 27); its group's footer says what it does (#768).
struct DryRunToggle: View {
    static let footer = "Nothing changes while it’s on"
    @Bindable var model: CatalogCleanupModel
    var body: some View {
        Toggle("Dry run", isOn: $model.dryRun)
            .disabled(!model.canEdit).help(model.editBlockedReason ?? "").accessibilityIdentifier("dryRunToggle")
    }
}

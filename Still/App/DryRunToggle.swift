import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// The Settings dry run. Off by default (Decision 27).
struct DryRunToggle: View {
    @Bindable var model: CatalogCleanupModel
    var body: some View {
        Toggle("Dry run (nothing changes)", isOn: $model.dryRun)
            .disabled(!model.canEdit).accessibilityIdentifier("dryRunToggle")
    }
}

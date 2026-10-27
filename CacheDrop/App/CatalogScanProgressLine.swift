import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// The catalog scan's progress as one quiet line: a small spinner and "Checking <location>… 4 of 31" (Decision 25).
struct CatalogScanProgressLine: View {
    let model: CatalogCleanupModel
    var body: some View {
        HStack(spacing: CacheDropDesign.Space.sm) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            Text(model.scanProgressText).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).truncationMode(.middle)
                .accessibilityIdentifier("catalogScanProgress")
        }
    }
}

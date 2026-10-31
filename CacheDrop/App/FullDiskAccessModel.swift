import AppKit
import Observation
import CacheDropCore

/// Full Disk Access state for an access surface, checked when it is shown. Catalog scans probe too, the one at
/// launch included (`CatalogCleanupModel.scan`). Checking never asks for access (`FullDiskAccessProbe`).
@MainActor @Observable final class FullDiskAccessModel {
    /// Nil until the first check.
    private(set) var status: FullDiskAccessStatus?
    private let detector: (any FullDiskAccessDetecting)?

    /// The probe runs against the catalog's home, so a debug UI test's fixture home stands in for the real one.
    init(detector: (any FullDiskAccessDetecting)? = CatalogCleanupModel.home.map { FullDiskAccessProbe(home: $0) }) { self.detector = detector }

    func refresh() async {
        #if DEBUG
        // Delay only the fixture's probe to inspect Checking… without a real permission request.
        if LocalStateLocation.isDisposableTest, let seconds = Double(ProcessInfo.processInfo.environment["CACHEDROP_TEST_FULL_DISK_ACCESS_PAUSE"] ?? ""), seconds > 0 {
            try? await Task.sleep(for: .seconds(min(seconds, 10)))
        }
        #endif
        guard let detector else { status = .unknown; return }
        status = await Task.detached { detector.status() }.value
    }
    /// Only ever from a button the user pressed.
    func openSettings() { NSWorkspace.shared.open(FullDiskAccessGuide.settingsURL) }
}

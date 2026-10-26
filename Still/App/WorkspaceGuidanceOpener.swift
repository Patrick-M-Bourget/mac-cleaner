import AppKit
import StillCore

/// Opens guidance places with NSWorkspace.
struct WorkspaceGuidanceOpener: GuidanceOpening {
    @MainActor func open(_ target: GuidanceTarget) async -> Bool {
        switch target {
        case .folder(let url): return NSWorkspace.shared.open(url)
        case .url(let url): return NSWorkspace.shared.open(url)
        case .app(let bundleID):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
            return (try? await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())) != nil
        }
    }
}

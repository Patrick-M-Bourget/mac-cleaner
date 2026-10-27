import AppKit
import CacheDropCore

/// Opens guidance places with NSWorkspace.
struct WorkspaceGuidanceOpener: GuidanceOpening {
    @MainActor func open(_ target: GuidanceTarget) async -> Bool {
        switch target {
        case .folder(let url), .url(let url): return Finder.open(url)
        case .app(let bundleID):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
            return (try? await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())) != nil
        }
    }
}

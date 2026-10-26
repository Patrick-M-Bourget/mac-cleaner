import Foundation
import Testing
@testable import StillCore

/// No apps are installed: tests never ask LaunchServices about this Mac's apps.
struct FixtureApps: AppLookup {
    func app(bundleID: String) -> InstalledApp? { nil }
    func app(updaterCacheDirName name: String) -> InstalledApp? { nil }
}

/// The built-in catalog with no installed apps.
let fixtureRules = BuiltInCatalog.rules(apps: FixtureApps())

/// Copies are never in use; tests that check use pass their own.
struct FixtureNothingInUse: InUseChecking {
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? { [] }
}

/// For executors whose candidates are deleted, never trashed: the real Trash is never the default.
struct TrashNeverUsed: TrashMoving {
    func moveToTrash(_ url: URL) throws -> URL? {
        Issue.record("Nothing should be moved to Trash here: \(url.path)")
        throw CocoaError(.featureUnsupported)
    }
}

extension Catalog {
    /// Discovery as tests run it, reading nothing outside the fixture: the fixture home stands in for the system root,
    /// no tool is installed unless `locateTool` finds a stand-in, there's no user folder unless one is given,
    /// and no copy is in use.
    func discover(fixture home: URL, userFolder: URL? = nil, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = FixtureNothingInUse(),
                  now: Date = Date(), locateTool: (ToolCommand) -> URL? = { _ in nil }, systemRoot: URL? = nil) -> [Candidate] {
        discovery(fixture: home, userFolder: userFolder, exclusions: exclusions, inUse: inUse, now: now, locateTool: locateTool, systemRoot: systemRoot).candidates
    }
    func discovery(fixture home: URL, userFolder: URL? = nil, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = FixtureNothingInUse(),
                   now: Date = Date(), locateTool: (ToolCommand) -> URL? = { _ in nil }, systemRoot: URL? = nil) -> CatalogDiscovery {
        discovery(home: home, userFolder: userFolder, exclusions: exclusions, inUse: inUse, now: now, locateTool: locateTool, systemRoot: systemRoot ?? home)
    }
}

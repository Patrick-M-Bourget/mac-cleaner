import Foundation
import Observation
import os
import CacheDropCore

/// Remembered configuration is separate from the process-only observations and live plan.
@MainActor @Observable final class RememberedLocations {
    private(set) var scopes: [RememberedScope] = []
    enum AccessStatus {
        case notScanned, ready, chooseAgain, unavailable, omitted, recheck
        var text: String {
            switch self {
            case .notScanned: "Not scanned"
            case .ready: "Ready for manual scan"
            case .chooseAgain: "Access unavailable · Choose again to renew"
            case .unavailable: "Location unavailable · Reconnect and recheck"
            case .omitted: "Omitted from the next scan"
            case .recheck: "Not scanned · Recheck required"
            }
        }
        /// The short reason Overview's recovery row gives next to the location's name (#223).
        var reason: String {
            switch self {
            case .chooseAgain: "Access unavailable"
            case .unavailable: "Location unavailable"
            default: text
            }
        }
        var needsRecovery: Bool { self == .chooseAgain || self == .unavailable }
    }
    private(set) var statuses: [UUID: AccessStatus] = [:]
    /// What the last failed recheck found, read once when it failed: "Folder not found" when nothing is there any more (#249).
    private(set) var recoveryReasons: [UUID: String] = [:]
    /// Every included location that needs access renewed or its volume reconnected: one Overview recovery row each (#223, #231).
    var recoveries: [(scope: RememberedScope, status: AccessStatus)] {
        included.compactMap { scope in statuses[scope.id].flatMap { $0.needsRecovery ? (scope, $0) : nil } }
    }
    /// Why a location's bookmark last failed (#342), kept so an "Access unavailable" can be diagnosed; also logged.
    private(set) var bookmarkFailures: [UUID: BookmarkFailure] = [:]
    private static let log = Logger(subsystem: "com.patrickbourget.CacheDrop", category: "locations")
    /// Downloads at its standard path (#342), first in every list; nil while a disposable test run has no fixture home.
    var builtInDownloads: RememberedScope? {
        CatalogCleanupModel.home.map { RememberedScope.builtInDownloads(at: $0.appendingPathComponent("Downloads", isDirectory: true)) }
    }
    /// The built-in locations, first in every list.
    private var builtIn: [RememberedScope] { builtInDownloads.map { [$0] } ?? [] }
    /// A registry entry the built-in Downloads replaces: one picked in an earlier version, or one carrying its ID.
    private func replacedByBuiltIn(_ scope: RememberedScope) -> Bool { builtIn.contains { $0.path == scope.path || $0.id == scope.id } }
    private(set) var notice: String?
    var message: String? {
        get {
            if let notice { return notice }
            // Recovery guidance comes from current per-location evidence. Resolving one
            // scope must not leave its old failure visible or hide another failed scope.
            return included.first(where: { statuses[$0.id]?.needsRecovery == true }).flatMap { scope in
                statuses[scope.id].map { URL(fileURLWithPath: scope.path).lastPathComponent + " · " + $0.text }
            }
        }
        set { notice = newValue }
    }
    private func registry() throws -> ScopeRegistry {
        ScopeRegistry(directory: try LocalStateLocation.root(create: true).appendingPathComponent("Scopes", isDirectory: true))
    }
    func load() {
        let saved: [RememberedScope]
        do { saved = try registry().list(); message = nil }
        catch { scopes = builtIn; message = "Remembered locations could not be read. No locations were scanned."; return }
        scopes = builtIn + saved.filter { !replacedByBuiltIn($0) }
        forgetReplaced(saved)
    }
    /// A Downloads folder picked in an earlier version is quietly forgotten: the built-in one replaces it (#342). It is left out
    /// of the list either way, so a failed forget is only tried again at the next load (#387).
    private func forgetReplaced(_ saved: [RememberedScope]) {
        guard let registry = try? registry() else { return }
        for picked in saved where replacedByBuiltIn(picked) { try? registry.forget(picked.id) }
    }
    @discardableResult func remember(_ url: URL, downloads: Bool) -> Bool {
        // Downloads itself is built in: nothing to remember, it is scanned as it is (#342).
        if let builtIn = builtInDownloads, url.standardizedFileURL.path == builtIn.path {
            load(); statuses[builtIn.id] = .notScanned; recoveryReasons[builtIn.id] = nil; return true
        }
        do {
            let scope = try registry().remember(url: url, kind: downloads ? .downloads : .inspection)
            load(); statuses[scope.id] = .notScanned; recoveryReasons[scope.id] = nil; return true
        } catch { message = "This location could not be remembered. Choose it again or check access."; return false }
    }
    var included: [RememberedScope] { scopes.filter(\.isIncluded) }
    func resolve(_ scope: RememberedScope) -> ScopeAccessLease? {
        do {
            let lease = try registry().resolveForScan(scope)
            statuses[scope.id] = .ready; recoveryReasons[scope.id] = nil; bookmarkFailures[scope.id] = nil; return lease
        } catch ScopeRegistryError.chooseAgain(let failure) {
            statuses[scope.id] = .chooseAgain; bookmarkFailures[scope.id] = failure
            Self.log.error("Access unavailable for a remembered location: \(failure.summary, privacy: .public)")
        }
        catch { statuses[scope.id] = .unavailable }
        recoveryReasons[scope.id] = statuses[scope.id].map { UnavailableScannedFolder.reason(path: scope.path, otherwise: $0.reason) }
        return nil
    }
    @discardableResult func setIncluded(_ value: Bool, scope: RememberedScope) -> Bool {
        guard !scope.isBuiltIn else { return false }
        do { try registry().setIncluded(value, id: scope.id); load(); statuses[scope.id] = value ? .recheck : .omitted; return true }
        catch { message = "The location setting could not be saved."; return false }
    }
    @discardableResult func forget(_ scope: RememberedScope) -> Bool {
        guard !scope.isBuiltIn else { return false }
        do { try registry().forget(scope.id); load(); statuses[scope.id] = nil; recoveryReasons[scope.id] = nil; return true }
        catch { message = "The location could not be forgotten. No files were changed."; return false }
    }
    func leases(for urls: [URL]) throws -> [ScopeAccessLease] {
        let registry = try registry()
        let saved = builtIn + (try registry.list())
        var leases: [ScopeAccessLease] = []
        do {
            for url in Set(urls.map(\.standardizedFileURL)) {
                guard let scope = saved.first(where: { $0.path == url.path }) else { throw ScopeRegistryError.unknownScope }
                leases.append(try registry.resolveForScan(scope))
            }
            return leases
        } catch { for lease in leases { lease.close() }; throw error }
    }
    func reset() throws {
        try registry().reset(); scopes = builtIn; statuses = [:]; recoveryReasons = [:]; bookmarkFailures = [:]; message = nil
    }
}

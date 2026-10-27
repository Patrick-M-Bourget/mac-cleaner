import Foundation
import Observation
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
    /// The first included location that needs access renewed or its volume reconnected: Overview's one recovery row (#223).
    var recovery: (scope: RememberedScope, status: AccessStatus)? {
        for scope in included { if let status = statuses[scope.id], status.needsRecovery { return (scope, status) } }
        return nil
    }
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
        do { scopes = try registry().list(); message = nil }
        catch { message = "Remembered locations could not be read. No locations were scanned." }
    }
    @discardableResult func remember(_ url: URL, downloads: Bool) -> Bool {
        do {
            let scope = try registry().remember(url: url, kind: downloads ? .downloads : .inspection)
            load(); statuses[scope.id] = .notScanned; return true
        } catch { message = "This location could not be remembered. Choose it again or check access."; return false }
    }
    var included: [RememberedScope] { scopes.filter(\.isIncluded) }
    var includedDownloads: [RememberedScope] { included.filter { $0.kind == .downloads } }
    func resolve(_ scope: RememberedScope) -> ScopeAccessLease? {
        do { let lease = try registry().resolveForScan(id: scope.id); statuses[scope.id] = .ready; return lease }
        catch ScopeRegistryError.chooseAgain { statuses[scope.id] = .chooseAgain }
        catch { statuses[scope.id] = .unavailable }
        return nil
    }
    @discardableResult func setIncluded(_ value: Bool, scope: RememberedScope) -> Bool {
        do { try registry().setIncluded(value, id: scope.id); load(); statuses[scope.id] = value ? .recheck : .omitted; return true }
        catch { message = "The location setting could not be saved."; return false }
    }
    @discardableResult func forget(_ scope: RememberedScope) -> Bool {
        do { try registry().forget(scope.id); load(); statuses[scope.id] = nil; return true }
        catch { message = "The location could not be forgotten. No files were changed."; return false }
    }
    func leases(for urls: [URL]) throws -> [ScopeAccessLease] {
        let registry = try registry()
        let saved = try registry.list()
        var leases: [ScopeAccessLease] = []
        do {
            for url in Set(urls.map(\.standardizedFileURL)) {
                guard let scope = saved.first(where: { $0.path == url.path }) else { throw ScopeRegistryError.unknownScope }
                leases.append(try registry.resolveForScan(id: scope.id))
            }
            return leases
        } catch { for lease in leases { lease.close() }; throw error }
    }
    func reset() throws { try registry().reset(); scopes = []; statuses = [:]; message = nil }
}

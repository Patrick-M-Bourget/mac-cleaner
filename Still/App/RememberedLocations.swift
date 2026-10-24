import Foundation
import Observation
import StillCore

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
        var needsRecovery: Bool { self == .chooseAgain || self == .unavailable }
    }
    private(set) var statuses: [UUID: AccessStatus] = [:]
    var message: String?
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
        message = statuses[scope.id].map { URL(fileURLWithPath: scope.path).lastPathComponent + " · " + $0.text }
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

import Foundation
import CryptoKit
import Darwin

public struct GrowthScanToken: Sendable {
    public let id = UUID()
    fileprivate let startedAt = Date()
    fileprivate let scope: URL
    fileprivate let epoch: UUID
    fileprivate let fingerprint: GrowthFingerprint
}
/// Metadata-only context around a catalog scan. It never starts enumeration itself.
public actor GrowthScanRecorder {
    private let store: GrowthHistoryStore
    public init(store: GrowthHistoryStore) { self.store = store }
    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

extension GrowthScanRecorder {
    /// Captures the store's epoch and the home folder's identity before a catalog scan starts.
    public func beginCatalog(home: URL, exclusionFingerprint: String) async throws -> GrowthScanToken {
        let epoch = try await store.recordingEpoch()
        return GrowthScanToken(scope: home.standardizedFileURL, epoch: epoch, fingerprint: try Self.catalogFingerprint(home, exclusions: exclusionFingerprint))
    }
    /// Records a completed catalog scan per category and location. Coverage is tracked per location, so access
    /// changes (Full Disk Access, unreadable folders) and catalog changes never invalidate the whole comparison.
    /// `afterCleanup` marks the rescan right after a cleanup, which is never a later scan's baseline (#126).
    public func completeCatalog(_ discovery: CatalogDiscovery, catalog: Catalog, fullDiskAccess: FullDiskAccessStatus, token: GrowthScanToken, observedAt: Date = Date(),
                                afterCleanup: Bool = false) async throws -> GrowthComparison {
        try Task.checkCancellation()
        guard observedAt >= token.startedAt, try Self.catalogFingerprint(token.scope, exclusions: token.fingerprint.exclusions) == token.fingerprint else { return .unknown }
        let snapshot = GrowthSnapshot(fingerprint: token.fingerprint, scopeLabel: "Known locations", observedAt: observedAt,
                                      groups: CatalogGrowth.groups(discovery, catalog: catalog, fullDiskAccess: fullDiskAccess), afterCleanup: afterCleanup)
        return try await store.record(snapshot, now: max(observedAt, Date()), expectedEpoch: token.epoch)
    }
    static func catalogFingerprint(_ home: URL, exclusions: String) throws -> GrowthFingerprint {
        let canonical = home.resolvingSymlinksInPath().standardizedFileURL
        var info = stat()
        guard lstat(canonical.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              let volume = try canonical.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else { throw CocoaError(.fileReadNoPermission) }
        return GrowthFingerprint(scopeID: "catalog:" + digest(canonical.path), rootID: info.resourceID, volumeID: volume, access: "catalog-per-location-coverage-v1",
                                 rules: "catalog-per-location-v1", exclusions: exclusions, classification: "catalog-category-location-v1")
    }
}

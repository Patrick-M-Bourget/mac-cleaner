import Foundation
import Darwin

public enum ManagedStorageCategory: String, CaseIterable, Sendable, Identifiable {
    case releaseArchives, deviceBackups, photos, mail, messages, systemData
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .releaseArchives: "Release archives"
        case .deviceBackups: "Device backups"
        case .photos: "Photos"
        case .mail: "Mail"
        case .messages: "Messages"
        case .systemData: "System-managed storage"
        }
    }
}

public enum ManagedAllocation: Equatable, Sendable {
    case measured(Int64), unknown, inaccessible, uninspected, notIndependentlyEstimated
}
public enum ManagedObjectKind: Sendable { case regularFile, directory, package, symbolicLink, other }
public struct ManagedObjectMetadata: Sendable {
    public let kind: ManagedObjectKind
    public let allocatedBytes: Int64?
    public init(kind: ManagedObjectKind, allocatedBytes: Int64?) { self.kind = kind; self.allocatedBytes = allocatedBytes }
}
/// Metadata-only system boundary. Managed roots must never be recursively traversed.
public protocol ManagedMetadataReading: Sendable { func read(_ url: URL) throws -> ManagedObjectMetadata }
public struct NativeManagedMetadata: ManagedMetadataReading {
    public init() {}
    public func read(_ url: URL) throws -> ManagedObjectMetadata {
        var info = stat()
        guard url.isFileURL, lstat(url.path, &info) == 0 else { throw CocoaError(.fileReadNoPermission) }
        let type = info.st_mode & S_IFMT
        if type == S_IFLNK { return .init(kind: .symbolicLink, allocatedBytes: nil) }
        if type == S_IFDIR {
            let values = try url.resourceValues(forKeys: [.isPackageKey])
            return .init(kind: values.isPackage == true ? .package : .directory, allocatedBytes: nil)
        }
        guard type == S_IFREG else { return .init(kind: .other, allocatedBytes: nil) }
        let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        return .init(kind: .regularFile, allocatedBytes: values.totalFileAllocatedSize.map(Int64.init))
    }
}

public struct ManagedStorageObservation: Sendable, Identifiable {
    public var id: ManagedStorageCategory { category }
    public let category: ManagedStorageCategory
    public let allocation: ManagedAllocation
    public let selectedURL: URL?
    public let observedAt: Date?
    public let coverage: String
    public var canExecuteCleanup: Bool { false }
    public var reclaimableBytes: Int64? { nil }
}

/// Inventory values remain separate from FileObservation/PlanDraft cleanup candidates.
public actor ManagedStorageInventory {
    private let metadata: any ManagedMetadataReading
    private var saved: [ManagedStorageCategory: ManagedStorageObservation] = [:]
    public init(metadata: any ManagedMetadataReading = NativeManagedMetadata()) { self.metadata = metadata }
    public func observations() -> [ManagedStorageObservation] {
        ManagedStorageCategory.allCases.map { category in
            saved[category] ?? .init(category: category,
                allocation: category == .systemData ? .notIndependentlyEstimated : .uninspected,
                selectedURL: nil, observedAt: nil, coverage: category == .systemData ? "Managed by macOS; no independent category estimate" : "No location inspected")
        }
    }
    @discardableResult
    public func inspect(_ category: ManagedStorageCategory, selected url: URL) -> ManagedStorageObservation {
        if category == .releaseArchives {
            return .init(category: category, allocation: .uninspected, selectedURL: nil, observedAt: nil, coverage: "Protected from Still cleanup")
        }
        guard category != .systemData else {
            return .init(category: .systemData, allocation: .notIndependentlyEstimated, selectedURL: nil,
                observedAt: nil, coverage: "Managed by macOS; no independent category estimate")
        }
        let allocation: ManagedAllocation
        let coverage: String
        do {
            let item = try metadata.read(url)
            switch item.kind {
            case .regularFile:
                if let bytes = item.allocatedBytes, bytes >= 0 { allocation = .measured(bytes) }
                else { allocation = .unknown }
                coverage = "Selected file allocation only; not the full app or account"
            case .package, .directory, .symbolicLink, .other:
                allocation = .uninspected
                coverage = "Protected or linked managed contents not traversed; recursive size unknown"
            }
        } catch {
            allocation = .inaccessible
            coverage = "Selected location unavailable; no complete allocation measured"
        }
        let observation = ManagedStorageObservation(category: category, allocation: allocation,
            selectedURL: url, observedAt: Date(), coverage: coverage)
        saved[category] = observation
        return observation
    }
}

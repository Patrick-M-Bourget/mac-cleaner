import Foundation
import Testing
import StillCore

private struct ManagedMeasurementFixture: ManagedMetadataReading {
    func read(_ url: URL) throws -> ManagedObjectMetadata {
        ManagedObjectMetadata(kind: .regularFile, allocatedBytes: url.lastPathComponent == "empty" ? 0 : 4_096)
    }
}

@Test func selectedManagedObjectAllocationKeepsMeasuredZeroDistinctFromUninspected() async throws {
    let inventory = ManagedStorageInventory(metadata: ManagedMeasurementFixture())
    let initial = await inventory.observations()
    #expect(initial.first { $0.category == .photos }?.allocation == .uninspected)
    #expect(initial.first { $0.category == .systemData }?.allocation == .notIndependentlyEstimated)
    let measured = await inventory.inspect(.mail, selected: URL(fileURLWithPath: "/disposable/attachment"))
    #expect(measured.allocation == .measured(4_096))
    #expect(!measured.canExecuteCleanup && measured.reclaimableBytes == nil)
    let zero = await inventory.inspect(.messages, selected: URL(fileURLWithPath: "/disposable/empty"))
    #expect(zero.allocation == .measured(0))
    #expect(zero.observedAt != nil)
}

private actor UnavailableOwnerApp: ManagedApplicationLaunching {
    private(set) var requested: [String] = []
    func open(identifiers: [String]) async -> Bool { requested = identifiers; return false }
}

@Test func ownerAppUnavailableKeepsGuidanceAndReportsFailure() async {
    let launcher = UnavailableOwnerApp()
    let guidance = ManagedStorageGuidance(category: .photos)
    let result = await guidance.open(using: launcher)
    #expect(result == .unavailable)
    #expect(await launcher.requested == ["com.apple.Photos"])
    #expect(guidance.supportURL.host == "support.apple.com")
}

private struct DeniedManagedMetadata: ManagedMetadataReading {
    func read(_ url: URL) throws -> ManagedObjectMetadata { throw ScanAccessFailure.denied }
}

@Test func protectedManagedPackageStaysUninspectedAndUnchanged() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillManaged-" + UUID().uuidString, isDirectory: true)
    let package = root.appendingPathComponent("Protected.photoslibrary", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sentinel = package.appendingPathComponent("sentinel.bin")
    try Data([1, 2, 3]).write(to: sentinel)
    let inventory = ManagedStorageInventory()
    let observed = await inventory.inspect(.photos, selected: package)
    #expect(observed.allocation == .uninspected)
    #expect(!observed.canExecuteCleanup && observed.reclaimableBytes == nil)
    #expect(try Data(contentsOf: sentinel) == Data([1, 2, 3]))
    let backup = await inventory.inspect(.deviceBackups, selected: root)
    #expect(backup.allocation == .uninspected)
}

@Test func deniedManagedLocationNeverBecomesZeroOrErasesOtherRows() async {
    let inventory = ManagedStorageInventory(metadata: DeniedManagedMetadata())
    let denied = await inventory.inspect(.mail, selected: URL(fileURLWithPath: "/disposable/denied"))
    #expect(denied.allocation == .inaccessible)
    let rows = await inventory.observations()
    #expect(rows.first { $0.category == .photos }?.allocation == .uninspected)
    #expect(rows.first { $0.category == .systemData }?.allocation == .notIndependentlyEstimated)
}

import Foundation
import XCTest
import CacheDropCore

final class ScopeRegistryTests: XCTestCase {
    func testRememberedConfigurationSurvivesReopeningWithoutRestoringFindings() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let store = ScopeRegistry(directory: root.appendingPathComponent("State"))
        let scope = try store.remember(url: downloads, kind: .downloads)
        try store.setIncluded(false, id: scope.id)
        let reopened = ScopeRegistry(directory: root.appendingPathComponent("State"))
        let records = try reopened.list()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, scope.id)
        XCTAssertEqual(records.first?.isIncluded, false)
        XCTAssertEqual(records.first?.kind, .downloads)
    }
    func testExplicitAccessRechecksAndForgettingPreservesOverlappingConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Downloads")
        let child = folder.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ScopeRegistry(directory: root.appendingPathComponent("State"))
        let parent = try store.remember(url: folder, kind: .downloads)
        let nested = try store.remember(url: child, kind: .inspection)
        XCTAssertEqual(try store.list().count, 2)
        let lease = try store.resolveForScan(id: nested.id)
        let actualIdentity = try XCTUnwrap(lease.url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject)
        let expectedIdentity = try XCTUnwrap(child.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject)
        XCTAssertEqual(actualIdentity, expectedIdentity)
        lease.close()
        try store.setIncluded(false, id: nested.id)
        XCTAssertThrowsError(try store.resolveForScan(id: nested.id)) { error in
            guard case ScopeRegistryError.excluded = error else { return XCTFail("Expected excluded") }
        }
        try store.forget(parent.id)
        XCTAssertEqual(try store.list().map(\.id), [nested.id])
        try store.setIncluded(true, id: nested.id)
        try FileManager.default.removeItem(at: child)
        XCTAssertThrowsError(try store.resolveForScan(id: nested.id))
        try store.reset()
        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testSymlinkedSettingsCannotRedirectConfigurationWrites() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("State")
        let outside = root.appendingPathComponent("unrelated.txt")
        try Data("preserve".utf8).write(to: outside)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: state.appendingPathComponent("scopes-v1.json"), withDestinationURL: outside)
        let store = ScopeRegistry(directory: state)
        XCTAssertThrowsError(try store.reset())
        XCTAssertThrowsError(try store.list())
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "preserve")
    }

    func testRememberingRootSymlinkCannotSilentlyAddItsDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("ActualDownloads")
        let link = root.appendingPathComponent("ChosenDownloads")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        let store = ScopeRegistry(directory: root.appendingPathComponent("State"))
        XCTAssertThrowsError(try store.remember(url: link, kind: .downloads))
        XCTAssertTrue(try store.list().isEmpty)
        // Ordinary ancestor aliases such as /var -> /private/var remain valid.
        let actual = try store.remember(url: destination, kind: .downloads)
        XCTAssertEqual(try store.list().map(\.id), [actual.id])
        let lease = try store.resolveForScan(id: actual.id)
        lease.close()
    }

    func testMalformedConfigurationFailsClosedUntilExplicitReset() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("State")
        let store = ScopeRegistry(directory: state)
        _ = try store.remember(url: folder, kind: .downloads)
        try Data("not a supported configuration archive".utf8).write(to: state.appendingPathComponent("scopes-v1.json"))
        XCTAssertThrowsError(try store.list())
        XCTAssertThrowsError(try store.remember(url: folder, kind: .downloads))
        try store.reset()
        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

}

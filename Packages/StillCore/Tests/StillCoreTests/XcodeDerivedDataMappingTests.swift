import Foundation
import Darwin
import Testing
import StillCore

@Test func nativeXcodeMappingKeepsVerifiedProjectAlongsideUnknownAssociation() throws {
    let fm = FileManager.default
    let canonical = realpath(fm.temporaryDirectory.path, nil)!
    defer { free(canonical) }
    let root = URL(fileURLWithPath: String(cString: canonical)).appendingPathComponent("StillXcodeMapping-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let project = root.appendingPathComponent("Sources/Owned.xcodeproj")
    try fm.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("owned fixture metadata".utf8).write(to: project.appendingPathComponent("project.pbxproj"))
    let derived = root.appendingPathComponent("DerivedData")
    let known = derived.appendingPathComponent("Owned-opaque")
    try fm.createDirectory(at: known.appendingPathComponent("Build/Intermediates.noindex"), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": project.path, "LastAccessedDate": Date()], format: .xml, options: 0)
    try data.write(to: known.appendingPathComponent("info.plist"))
    let unknown = derived.appendingPathComponent("Unknown-opaque")
    try fm.createDirectory(at: unknown, withIntermediateDirectories: true)
    try Data("malformed".utf8).write(to: unknown.appendingPathComponent("info.plist"))
    let result = try NativeXcodeBuildEnvironment().projects(in: derived)
    #expect(result.associations.count == 1, "Unavailable: \(result.unavailable.map(\.reason))")
    #expect(result.associations.first?.projectURL.path == project.path)
    #expect(result.unavailable.count == 1)
    #expect(result.unavailable.first?.derivedDataURL.path == unknown.path)
}

@Test func nativeXcodeMappingRefusesLinkedAndDuplicateProjectAssociationsWithoutReadingSource() throws {
    let fm = FileManager.default
    let canonical = realpath(fm.temporaryDirectory.path, nil)!
    defer { free(canonical) }
    let root = URL(fileURLWithPath: String(cString: canonical)).appendingPathComponent("StillXcodeMapping-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let project = root.appendingPathComponent("Owned.xcodeproj")
    try fm.createDirectory(at: project, withIntermediateDirectories: true)
    let protected = Data("owned protected metadata".utf8)
    try protected.write(to: project.appendingPathComponent("project.pbxproj"))
    let derived = root.appendingPathComponent("DerivedData")
    let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": project.path, "LastAccessedDate": Date()], format: .binary, options: 0)
    for name in ["First-opaque", "Second-opaque"] {
        let folder = derived.appendingPathComponent(name)
        try fm.createDirectory(at: folder.appendingPathComponent("Build/Intermediates.noindex"), withIntermediateDirectories: true)
        try plist.write(to: folder.appendingPathComponent("info.plist"))
    }
    let linked = derived.appendingPathComponent("Linked-opaque")
    try fm.createDirectory(at: linked, withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: linked.appendingPathComponent("info.plist"), withDestinationURL: derived.appendingPathComponent("First-opaque/info.plist"))
    let result = try NativeXcodeBuildEnvironment().projects(in: derived)
    #expect(result.associations.isEmpty)
    #expect(result.unavailable.count == 3)
    #expect(try Data(contentsOf: project.appendingPathComponent("project.pbxproj")) == protected)
}

private struct ReplacedXcodeMappingEnvironment: XcodeBuildEnvironment {
    let root: URL
    func validateInstallation() throws {}
    func standardDerivedDataURL() throws -> URL { root }
    func ownerObservation() throws -> XcodeOwnerObservation { .init(activity: .closed) }
    func now() -> Date { Date() }
    func projects(in root: URL) throws -> XcodeProjectMapping {
        let result = try NativeXcodeBuildEnvironment().projects(in: root)
        let metadata = result.associations[0].metadataURL
        let bytes = try Data(contentsOf: metadata)
        try bytes.write(to: metadata, options: .atomic)
        return result
    }
}

@Test func xcodeInspectionRefusesMappingMetadataReplacedAfterNativeResolution() async throws {
    let fm = FileManager.default
    let canonical = realpath(fm.temporaryDirectory.path, nil)!
    defer { free(canonical) }
    let root = URL(fileURLWithPath: String(cString: canonical)).appendingPathComponent("StillXcodeMapping-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let project = root.appendingPathComponent("Owned.xcodeproj")
    try fm.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("owned metadata".utf8).write(to: project.appendingPathComponent("project.pbxproj"))
    let derived = root.appendingPathComponent("DerivedData")
    let folder = derived.appendingPathComponent("Owned-opaque")
    try fm.createDirectory(at: folder.appendingPathComponent("Build/Intermediates.noindex"), withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": project.path, "LastAccessedDate": Date()], format: .xml, options: 0)
    try plist.write(to: folder.appendingPathComponent("info.plist"))
    let module = XcodeIntermediates(environment: ReplacedXcodeMappingEnvironment(root: derived), journalURL: root.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    #expect(inspection.projects.count == 1)
    #expect(inspection.projects[0].artifacts.isEmpty)
    #expect(inspection.projects[0].unavailableReason != nil)
}

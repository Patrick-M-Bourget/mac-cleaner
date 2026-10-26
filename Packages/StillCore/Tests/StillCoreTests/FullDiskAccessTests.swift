import Foundation
import Testing
@testable import StillCore

/// A fixture home with the probed protected folder in the given state. Never the real home.
private func fixtureHome(_ safari: FolderState) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillFDA-\(UUID())")
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
    let folder = home.appendingPathComponent("Library/Safari")
    switch safari {
    case .missing: break
    case .readable: try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    case .blocked:
        // macOS answers a protected folder with EPERM; a folder with no permissions answers EACCES. Both mean "can't open".
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
    }
    return home
}
private enum FolderState { case missing, readable, blocked }
private func cleanUp(_ home: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home.appendingPathComponent("Library/Safari").path)
    try? FileManager.default.removeItem(at: home)
}

@Test func detectsFullDiskAccessWhenAProtectedFolderOpens() throws {
    let home = try fixtureHome(.readable); defer { cleanUp(home) }
    #expect(FullDiskAccessProbe(home: home).status() == .granted)
}

@Test func detectsNoFullDiskAccessWhenAProtectedFolderRefusesToOpen() throws {
    let home = try fixtureHome(.blocked); defer { cleanUp(home) }
    #expect(FullDiskAccessProbe(home: home).status() == .notGranted)
}

@Test func detectionIsUnknownWhenNoProtectedFolderExists() throws {
    let home = try fixtureHome(.missing); defer { cleanUp(home) }
    #expect(FullDiskAccessProbe(home: home).status() == .unknown)
}

@Test func detectionFallsBackToTheNextProtectedFolderWhenSafariIsMissing() throws {
    let home = try fixtureHome(.missing); defer { cleanUp(home) }
    let tcc = home.appendingPathComponent("Library/Application Support/com.apple.TCC")
    try FileManager.default.createDirectory(at: tcc, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: tcc.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tcc.path) }
    #expect(FullDiskAccessProbe(home: home).status() == .notGranted)
}

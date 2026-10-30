import Foundation
import Darwin
import Testing
@testable import CacheDropCore

/// #463: the in-use check reads only file-backed regions when macOS gives exactly the files the full walk does. This process
/// maps many files, so it is the check CacheDrop runs on itself before trusting the faster reading; a macOS that changed the
/// flavor fails here, and the app falls back to the full walk.
/// Other tests map files in this process meanwhile, so the readings are compared as the app compares them, not once.
@Test func fileBackedRegionsGiveTheSameMappedFilesAsTheFullWalk() throws {
    #expect(try #require(SystemInUseSnapshot.mappedPaths(getpid(), flavor: SystemInUseSnapshot.fileBackedRegions)).isEmpty == false)
    #expect(SystemInUseSnapshot.fileBackedRegionsAgree)
}

/// A file mapped from a temporary folder holds no descriptor once mapped; the faster reading still finds it, so a mapped
/// copy reads as in use (review of #474).
@Test func aFileMappedFromATemporaryFolderIsFoundByTheFasterReading() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropMapped-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("mapped.bin")
    try Data(repeating: 5, count: 64 * 1024).write(to: file)
    let mapped = try Data(contentsOf: file, options: .alwaysMapped)
    defer { withExtendedLifetime(mapped) {} }
    let real = try #require(realPath(file.path))
    #expect(try #require(SystemInUseSnapshot.mappedPaths(getpid(), flavor: SystemInUseSnapshot.fileBackedRegions)).contains(real))
    #expect(try #require(SystemInUseSnapshot.mappedPaths(getpid())).contains(real))
}

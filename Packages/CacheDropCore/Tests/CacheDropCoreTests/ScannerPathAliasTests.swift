import Darwin
import Foundation
import Testing
import CacheDropCore

@Test func explicitNativeTemporaryPathAliasesObserveTheSameOwnedResource() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("CacheDropScannerAlias-" + UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let shortPath = root.standardizedFileURL.path
    try #require(shortPath.hasPrefix("/var/"), "This macOS fixture requires the native /var alias")
    let longRoot = URL(fileURLWithPath: "/private" + shortPath, isDirectory: true)
    var first = stat(), second = stat()
    try #require(lstat(root.path, &first) == 0 && lstat(longRoot.path, &second) == 0)
    try #require(first.st_dev == second.st_dev && first.st_ino == second.st_ino)
    let file = root.appendingPathComponent("sentinel.txt")
    try Data("owned sentinel!!!".utf8).write(to: file)
    var known = stat()
    try #require(lstat(file.path, &known) == 0)
    for selectedRoot in [URL(fileURLWithPath: shortPath, isDirectory: true), longRoot] {
        let result = try await FolderScanner().scan(selectedRoot)
        #expect(result.isComplete)
        #expect(result.logicalBytes == 17)
        let row = try #require(result.observations.only)
        #expect(row.kind == .file)
        #expect(row.logicalBytes == 17)
        #expect(row.resourceID == "\(known.st_dev):\(known.st_ino)")
        #expect(row.url.resolvingSymlinksInPath().standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

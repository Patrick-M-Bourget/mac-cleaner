import Foundation
import Testing
import StillCore

/// A temp home with a Downloads folder; tests never read or write the real Downloads.
private func downloadsHome() throws -> (home: URL, downloads: URL) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillDownloads-\(UUID())").resolvingSymlinksInPath()
    let downloads = home.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    return (home.resolvingSymlinksInPath(), downloads.resolvingSymlinksInPath())
}
private let day: TimeInterval = 86_400
/// Writes a file of `size` logical bytes (sparse when large) last opened, changed and created `age` ago.
@discardableResult
private func file(_ downloads: URL, _ path: String, size: Int64 = 10, age: TimeInterval = 0, now: Date) throws -> URL {
    let url = downloads.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 1, count: Int(min(size, 10))))
    if size > 10 { let handle = try FileHandle(forWritingTo: url); try handle.truncate(atOffset: UInt64(size)); try handle.close() }
    let date = now.addingTimeInterval(-age)
    try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    var times = [timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(url.path, &times) == 0)
    return url
}
private let megabyte: Int64 = 1_000_000

@Test func downloadsOffersInstallersAtAnyAgeAndOnlyLargeFilesNotOpenedIn90Days() throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    try file(downloads, "Setup.dmg", now: now)
    try file(downloads, "Old Tool.PKG", age: 400 * day, now: now)
    try file(downloads, "nested/archive.zip", now: now)
    try file(downloads, "notes.txt", age: 400 * day, now: now)
    try file(downloads, "movie-old.mov", size: 600 * megabyte, age: 120 * day, now: now)
    try file(downloads, "movie-recent.mov", size: 600 * megabyte, age: 30 * day, now: now)
    try file(downloads, "small-old.mov", size: 499 * megabyte, age: 120 * day, now: now)
    try file(downloads, "big-old.dmg", size: 600 * megabyte, age: 120 * day, now: now)
    try file(downloads, "Thing.app/Contents/inner.dmg", now: now)
    try file(downloads, "Projects.photoslibrary/big.mov", size: 600 * megabyte, age: 120 * day, now: now)
    try FileManager.default.createSymbolicLink(at: downloads.appendingPathComponent("link.dmg"), withDestinationURL: downloads.appendingPathComponent("Setup.dmg"))

    let candidates = Catalog(rules: BuiltInCatalog.rules).discover(home: home, now: now)
    let found = Dictionary(uniqueKeysWithValues: candidates.map { (String($0.url.path.dropFirst(downloads.path.count + 1)), $0) })
    #expect(Set(found.keys) == ["Setup.dmg", "Old Tool.PKG", "nested/archive.zip", "big-old.dmg", "movie-old.mov"])
    #expect(found["Setup.dmg"]?.ruleID == "downloads-installers")
    #expect(found["big-old.dmg"]?.ruleID == "downloads-installers")
    #expect(found["movie-old.mov"]?.ruleID == "downloads-old-large")
    #expect(candidates.allSatisfy { $0.action == .trash && !$0.isDirectory && $0.sizeComplete })
    #expect(found["movie-old.mov"]?.logicalBytes == 600 * megabyte)
    let lastUsed = try #require(found["movie-old.mov"]?.lastUsed)
    #expect(abs(lastUsed.timeIntervalSince(now.addingTimeInterval(-120 * day))) < 2)
}

@Test func aLargeFileOpenedRecentlyIsNotOld() throws {
    let (home, downloads) = try downloadsHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let now = Date()
    let url = try file(downloads, "video.mov", size: 600 * megabyte, age: 200 * day, now: now)
    let opened = now.addingTimeInterval(-10 * day)
    var times = [timeval(tv_sec: Int(opened.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(now.addingTimeInterval(-200 * day).timeIntervalSince1970), tv_usec: 0)]
    #expect(utimes(url.path, &times) == 0)
    #expect(Catalog(rules: BuiltInCatalog.rules).discover(home: home, now: now).isEmpty)
}

import Foundation
import Darwin
import StillCore

/// Shared app-owned local state. Debug tests bind an existing disposable root by identity.
enum LocalStateLocation {
    static var isDisposableTest: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        return env["STILL_TEST_STATE_ROOT"] != nil || env["STILL_TEST_STATE_ID"] != nil
        #else
        return false
        #endif
    }
    static func removeKnownFile(_ relative: String) throws {
        let root = try root(create: false)
        let file = root.appendingPathComponent(relative)
        guard file.standardizedFileURL.path.hasPrefix(root.path + "/"), !relative.contains("..") else { throw CocoaError(.fileWriteNoPermission) }
        var info = stat()
        if lstat(file.path, &info) != 0 { if errno == ENOENT { return }; throw CocoaError(.fileWriteUnknown) }
        guard info.st_mode & S_IFMT == S_IFREG, file.path == file.resolvingSymlinksInPath().path, info.st_uid == geteuid() else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: file)
    }
    static func root(create: Bool) throws -> URL {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["STILL_TEST_STATE_ROOT"] != nil || environment["STILL_TEST_STATE_ID"] != nil {
            guard let path = environment["STILL_TEST_STATE_ROOT"], let expected = environment["STILL_TEST_STATE_ID"] else { throw CocoaError(.fileReadNoPermission) }
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            let prefix = "StillTestState-"
            guard url.lastPathComponent.hasPrefix(prefix), UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil,
                  ["tmp", "T"].contains(url.deletingLastPathComponent().lastPathComponent),
                  url.path == url.resolvingSymlinksInPath().path else { throw CocoaError(.fileReadNoPermission) }
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700,
                  "\(info.st_dev):\(info.st_ino)" == expected else { throw CocoaError(.fileReadNoPermission) }
            let marker = url.appendingPathComponent(".still-owned-test-state")
            var markerInfo = stat()
            guard lstat(marker.path, &markerInfo) == 0, markerInfo.st_mode & S_IFMT == S_IFREG,
                  markerInfo.st_uid == geteuid(), markerInfo.st_size <= 128,
                  try String(contentsOf: marker, encoding: .utf8) == String(url.lastPathComponent.dropFirst(prefix.count)) else { throw CocoaError(.fileReadNoPermission) }
            return url
        }
        #endif
        let manager = FileManager.default
        let url = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: create).appendingPathComponent("Still", isDirectory: true)
        if create { try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var info = stat()
        if lstat(url.path, &info) == 0 {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsLocalKey])
            guard info.st_mode & S_IFMT == S_IFDIR, values.isUbiquitousItem != true, values.volumeIsLocal == true else { throw CocoaError(.fileReadNoPermission) }
        } else if errno != ENOENT { throw CocoaError(.fileReadNoPermission) }
        return url
    }
}

/// Local app-owned journal location; recovery opens existing storage only.
enum CleanupJournalLocation {
    static func writer() throws -> SQLiteCleanupJournal {
        try SQLiteCleanupJournal(url: LocalStateLocation.root(create: true).appendingPathComponent("cleanup.sqlite"))
    }
    static func existingReader() throws -> SQLiteCleanupJournal? {
        let url = try LocalStateLocation.root(create: false).appendingPathComponent("cleanup.sqlite")
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw CleanupJournalError.unavailable
        }
        return try SQLiteCleanupJournal(url: url, readOnly: true)
    }

}

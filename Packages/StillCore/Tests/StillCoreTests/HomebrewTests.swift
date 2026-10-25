import Foundation
import Testing
@testable import StillCore

@Test func unsupportedHomebrewVersionProducesGuidanceWithoutCleanupPreview() throws {
    let report = HomebrewPreview.parse(version: "Homebrew 999.0", prefix: "/fixture/prefix", cache: "/fixture/cache", output: "Would remove: /fixture/cache/item (1 MB)", qualifiedVersion: "Homebrew fixture-1")
    #expect(!report.qualified)
    #expect(report.targets.isEmpty)
    #expect(report.guidance != nil)
}

@Test func qualifiedFixturePreviewKeepsToolEstimateSeparateFromTargets() {
    let report = HomebrewPreview.parse(version: "Homebrew fixture-1", prefix: "/fixture/prefix", cache: "/fixture/cache", output: "Would remove: /fixture/cache/archive (12.3MB)\nWould free: 12.3MB\n", qualifiedVersion: "Homebrew fixture-1")
    #expect(report.qualified)
    #expect(report.targets == ["/fixture/cache/archive (12.3MB)"])
    #expect(report.estimate == "12.3MB")
}

@Test func unconstrainedOrOutOfRootOutputNeverBecomesAPlan() {
    let report = HomebrewPreview.parse(version: "Homebrew fixture-1", prefix: "/fixture/prefix", cache: "/fixture/cache", output: "Would remove: /outside/private-file (1MB)\n", qualifiedVersion: "Homebrew fixture-1")
    #expect(!report.qualified)
    #expect(report.targets.isEmpty)
}

@Test func boundedToolUsesExactArgumentsAndRejectsTimeoutOrExcessOutput() throws {
    let result = try BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "a ; $(echo not-executed)"], timeout: 2, outputLimit: 1024)
    #expect(result == "a ; $(echo not-executed)")
    #expect(throws: (any Error).self) { try BoundedTool.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], timeout: 0.05, outputLimit: 1024) }
    #expect(throws: (any Error).self) { try BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", String(repeating: "x", count: 4096)], timeout: 2, outputLimit: 64) }
}

@Test func disposableInstallationPreviewDoesNotChangePackageSentinel() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHomebrewProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("cache"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sentinel = root.appendingPathComponent("cache/archive")
    try Data("keep-package-data".utf8).write(to: sentinel)
    let executable = root.appendingPathComponent("brew")
    let script = """
    #!/bin/sh
    test "$HOMEBREW_NO_AUTO_UPDATE" = 1 || exit 3
    test "$HOMEBREW_NO_ANALYTICS" = 1 || exit 3
    case "$*" in
      --version) printf 'Homebrew fixture-1\\n' ;;
      --prefix) printf '%s/prefix\\n' "${0%/*}" ;;
      --cache) printf '%s/cache\\n' "${0%/*}" ;;
      'cleanup --dry-run') printf 'Would remove: %s/cache/archive (12.3MB)\\nWould free: 12.3MB\\n' "${0%/*}" ;;
      *) exit 2 ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let preview = try HomebrewInspector.inspectDisposable(executable: executable, qualifiedVersion: "Homebrew fixture-1")
    #expect(preview.qualified)
    #expect(preview.targets.count == 1)
    #expect(try Data(contentsOf: sentinel) == Data("keep-package-data".utf8))
}

@Test func realInstallationRemainsUnexecutedUntilQualifiedAndMissingToolGuides() throws {
    #expect(throws: (any Error).self) { try HomebrewInspector.inspect(executable: URL(fileURLWithPath: "/missing/brew")) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHomebrewProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("brew")
    try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let report = try HomebrewInspector.inspect(executable: executable)
    #expect(report.version == "Unqualified installation (not executed)")
    #expect(!report.qualified)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["STILL_HOMEBREW_PROBE_ROOT"] != nil, "Requires explicitly provisioned owned official Homebrew source")) func selectedPinnedHomebrewReportsCacheMetadataWithoutExecutingInstalledCode() throws {
    guard let path = ProcessInfo.processInfo.environment["STILL_HOMEBREW_PROBE_ROOT"] else {
        return // Genuine source integration is separately invoked with an owned installation.
    }
    let source = URL(fileURLWithPath: path)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHomebrewInventory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 0x61, count: 27).write(to: root.appendingPathComponent("obsolete.incomplete"))
    try Data(repeating: 0x62, count: 101).write(to: root.appendingPathComponent("current.bottle.tar.gz"))
    let report = try HomebrewInspector.inspectSelected(executable: source.appendingPathComponent("bin/brew"), cache: root)
    #expect(report.supported)
    #expect(report.version == "Homebrew shell source 4.6.17")
    #expect(report.cache == root.resolvingSymlinksInPath().path)
    #expect(report.regularFileCount == 2)
    #expect(report.logicalBytes == 128)
    #expect(report.incompleteDownloads.count == 1)
    #expect(report.incompleteDownloads.first?.logicalBytes == 27)
    #expect(report.estimatedReleaseBytes == nil)
    #expect(try Data(contentsOf: root.appendingPathComponent("obsolete.incomplete")) == Data(repeating: 0x61, count: 27))
    try FileManager.default.linkItem(at: root.appendingPathComponent("current.bottle.tar.gz"), to: root.appendingPathComponent("alias.bottle.tar.gz"))
    let hardlinks = try HomebrewInspector.inspectSelected(executable: source.appendingPathComponent("bin/brew"), cache: root)
    #expect(hardlinks.regularFileCount == 3)
    #expect(hardlinks.logicalBytes == 128)
    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("unavailable-link").path, withDestinationPath: "/nonexistent/StillHomebrewOutsideCache")
    let partial = try HomebrewInspector.inspectSelected(executable: source.appendingPathComponent("bin/brew"), cache: root)
    #expect(partial.supported)
    #expect(!partial.complete)
    #expect(partial.logicalBytes == nil)
    #expect(partial.allocatedBytes == nil)
}

@Test func arbitraryHomebrewNameDoesNotExecuteOrInspectCache() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillHomebrewInventory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let brew = root.appendingPathComponent("bin/brew")
    let marker = root.appendingPathComponent("executed")
    try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: brew)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
    let report = try HomebrewInspector.inspectSelected(executable: brew, cache: root)
    #expect(!report.supported)
    #expect(report.logicalBytes == nil)
    #expect(report.incompleteDownloads.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

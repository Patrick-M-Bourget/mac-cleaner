import Foundation
import Testing
import StillCore

/// A temp home folder; tests never read or write the real home.
private func fixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillDevCaches-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func makeFolder(_ home: URL, _ relative: String, bytes: Int = 100) throws {
    let file = home.appendingPathComponent(relative).appendingPathComponent("entry")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}

@Test func eachDeveloperCacheIsACandidateOnlyWhenItsFolderExists() throws {
    let home = try fixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: BuiltInCatalog.rules)
    #expect(catalog.discover(home: home).isEmpty)
    let folders = [
        "Library/Caches/Yarn": "yarn-cache", ".yarn/berry/cache": "yarn-cache",
        "Library/pnpm/store": "pnpm-store", "Library/Caches/pnpm": "pnpm-store",
        ".cache/uv": "uv-cache", "Library/Caches/pip": "pip-cache",
        ".cargo/registry": "cargo-cache", ".cargo/git": "cargo-cache",
        ".gradle/caches": "gradle-cache", "Library/Caches/CocoaPods": "cocoapods-cache",
    ]
    for folder in folders.keys { try makeFolder(home, folder) }
    let found = catalog.discover(home: home)
    #expect(Dictionary(found.map { ($0.url.path, $0.ruleID) }, uniquingKeysWith: { a, _ in a })
            == Dictionary(uniqueKeysWithValues: folders.map { (home.appendingPathComponent($0.key).path, $0.value) }))
    #expect(found.allSatisfy { $0.action == .delete && $0.logicalBytes == 100 })
    // Installed tools and their downloads stay out of reach.
    #expect(!found.contains { $0.url.path.hasPrefix(home.appendingPathComponent(".cargo/bin").path) })
}

private func owner(_ id: String) throws -> RuleOwner { try #require(BuiltInCatalog.rules.first { $0.id == id }?.owner) }

@Test func eachCommandLineCacheIsRefusedOnlyWhileItsOwnToolRuns() throws {
    let cases: [(String, [[String]], [[String]])] = [
        ("yarn-cache", [["node", "/usr/local/lib/node_modules/corepack/dist/yarn.js", "install"], ["node", "/p/.yarn/releases/yarn-4.5.0.cjs"], ["/opt/homebrew/bin/yarn"]],
                       [["node", "/p/node_modules/.bin/vite"], ["/usr/bin/yarnspinner"]]),
        ("pnpm-store", [["node", "/opt/homebrew/lib/node_modules/pnpm/bin/pnpm.cjs", "add"], ["/Users/me/Library/pnpm/pnpm", "i"]],
                       [["node", "server.js", "pnpm"]]),
        ("uv-cache", [["/Users/me/.local/bin/uv", "sync"], ["uvx", "ruff"]], [["/usr/bin/python3", "-m", "uvicorn", "app:app"]]),
        ("pip-cache", [["/usr/bin/python3", "-m", "pip", "install", "x"], ["/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/pip3.12", "install"], ["pip3"]],
                      [["/usr/bin/python3", "server.py"], ["/opt/homebrew/bin/pipx", "list"]]),
        ("cargo-cache", [["/Users/me/.cargo/bin/cargo", "build"], ["/Users/me/.rustup/toolchains/stable/bin/cargo-clippy"]],
                        [["/Users/me/.cargo/bin/rust-analyzer"], ["/Users/me/.cargo/bin/ripgrep"]]),
        ("gradle-cache", [["/usr/bin/java", "-Xmx2g", "-cp", "/Users/me/.gradle/wrapper/dists/gradle-8.10/lib/gradle-daemon-main-8.10.jar", "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "8.10"],
                          ["/bin/sh", "./gradlew", "assemble"], ["java", "-classpath", "/p/gradle/wrapper/gradle-wrapper.jar", "org.gradle.wrapper.GradleWrapperMain"]],
                         [["/usr/bin/java", "-jar", "app.jar"]]),
        ("cocoapods-cache", [["/usr/bin/ruby", "/usr/local/bin/pod", "install"], ["/opt/homebrew/bin/pod", "update"]], [["/usr/bin/ruby", "server.rb"], ["/usr/bin/podman"]]),
    ]
    for (rule, running, unrelated) in cases {
        let owner = try owner(rule)
        for argv in running { #expect(owner.matches(argv), "\(rule) should see \(argv)") }
        for argv in unrelated { #expect(!owner.matches(argv), "\(rule) should ignore \(argv)") }
    }
}

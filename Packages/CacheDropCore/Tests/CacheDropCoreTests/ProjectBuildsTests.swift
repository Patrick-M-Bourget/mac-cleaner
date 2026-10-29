import Foundation
import Testing
@testable import CacheDropCore

/// A temp folder standing in for one the user picked; tests never scan real projects.
private func pickedFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropProjects-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return URL(fileURLWithPath: try #require(realPath(folder.path)))
}
private let day: TimeInterval = 86_400
/// Writes a file whose modification date is `age` ago.
private func file(_ folder: URL, _ path: String, age: TimeInterval = 30 * day) throws {
    let url = folder.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 1, count: 100))
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
}
/// The build folders a picked folder offers, relative to it.
private func offered(_ folder: URL, inUse: any InUseChecking = FixtureNothingInUse(), exclusions: ExclusionPolicy = ExclusionPolicy()) -> [String: Candidate] {
    let found = ProjectBuilds.candidates(in: folder, exclusions: exclusions, home: fixtureNoHome, inUse: inUse)
    return Dictionary(uniqueKeysWithValues: found.map { (String($0.url.path.dropFirst(folder.path.count + 1)), $0) })
}

@Test func eachBuildFolderKindIsOfferedOnlyNextToItsProjectMarker() throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    // Each kind with its marker.
    try file(folder, "web/package.json"); try file(folder, "web/node_modules/left-pad/index.js")
    try file(folder, "web/.next/cache/a"); try file(folder, "web/dist/app.js")
    try file(folder, "swift/Package.swift"); try file(folder, "swift/.build/debug/app")
    try file(folder, "rust/Cargo.toml"); try file(folder, "rust/target/debug/app")
    try file(folder, "java/pom.xml"); try file(folder, "java/target/app.jar")
    try file(folder, "android/build.gradle.kts"); try file(folder, "android/build/out.apk")
    try file(folder, "groovy/build.gradle"); try file(folder, "groovy/build/out.jar")
    try file(folder, "py/pyproject.toml"); try file(folder, "py/.venv/bin/python"); try file(folder, "py/__pycache__/m.pyc")
    try file(folder, "req/requirements.txt"); try file(folder, "req/.venv/bin/python")
    try file(folder, "setup/setup.py"); try file(folder, "setup/__pycache__/m.pyc")
    try file(folder, "mac/App.xcodeproj/project.pbxproj"); try file(folder, "mac/DerivedData/Build/app")
    // The same names without their marker.
    try file(folder, "plain/node_modules/x.js"); try file(folder, "plain/dist/x.js"); try file(folder, "plain/.next/x")
    try file(folder, "plain/.build/x"); try file(folder, "plain/target/x"); try file(folder, "plain/build/x")
    try file(folder, "plain/.venv/x"); try file(folder, "plain/__pycache__/x"); try file(folder, "plain/DerivedData/x")
    // A marker for another kind doesn't count.
    try file(folder, "mixed/Cargo.toml"); try file(folder, "mixed/node_modules/x.js"); try file(folder, "mixed/build/x")

    let found = offered(folder)
    #expect(Set(found.keys) == ["web/node_modules", "web/.next", "web/dist", "swift/.build", "rust/target", "java/target", "android/build",
                                "groovy/build", "py/.venv", "py/__pycache__", "req/.venv", "setup/__pycache__", "mac/DerivedData"])
    #expect(found.values.allSatisfy { $0.ruleID == ProjectBuilds.ruleID && $0.action == .trash && $0.isDirectory && $0.sizeComplete && $0.estimatedBytes > 0 })
    // Grouped per project, with the project's last change.
    #expect(found["web/dist"]?.profile == "web")
    #expect(found["web/dist"]?.itemName == "dist in web")
    let lastUsed = try #require(found["rust/target"]?.lastUsed)
    #expect(abs(lastUsed.timeIntervalSinceNow + 30 * day) < 5)
}

/// Runs git in a fixture repository, never with the user's hooks or signing.
private func git(_ repo: URL, _ arguments: String...) throws {
    let process = Process()
    process.executableURL = try #require(WorkspaceGit.installed())
    process.arguments = ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.com",
                         "-C", repo.path] + arguments
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}
/// A fixture git project, all committed and last changed 30 days ago, with a `node_modules` git ignores.
private func committedProject(in folder: URL, _ name: String) throws -> URL {
    let project = folder.appendingPathComponent(name)
    try file(project, "package.json"); try file(project, "index.js"); try file(project, ".gitignore")
    try "node_modules\n".write(to: project.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * day)], ofItemAtPath: project.appendingPathComponent(".gitignore").path)
    try file(project, "node_modules/x/index.js")
    try git(project, "init", "-q"); try git(project, "add", "."); try git(project, "commit", "-q", "-m", "fixture")
    return project
}
/// Says the listed folders are open, or that it can't tell.
private struct FakeInUse: InUseChecking {
    var open: Set<String> = []
    var unknown = false
    func inUse(_ folders: [URL], by owner: RuleOwner) -> Set<String>? { unknown ? nil : Set(folders.map(\.path)).intersection(open) }
}

@Test func buildFoldersOfProjectsWithUncommittedChangesRecentEditsOrOpenFilesAreKeptHeldWithTheirReason() throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try committedProject(in: folder, "clean")
    let dirty = try committedProject(in: folder, "dirty")
    try file(dirty, "index.js")
    try "changed".write(to: dirty.appendingPathComponent("index.js"), atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * day)], ofItemAtPath: dirty.appendingPathComponent("index.js").path)
    // An untracked file isn't a change to a tracked file.
    let untracked = try committedProject(in: folder, "untracked")
    try file(untracked, "notes.txt")
    try file(folder, "recent/package.json"); try file(folder, "recent/node_modules/x.js"); try file(folder, "recent/src/app.js", age: 2 * day)
    try file(folder, "open/package.json"); try file(folder, "open/node_modules/x.js")

    let openUse = FakeInUse(open: [folder.appendingPathComponent("open").path])
    let found = offered(folder, inUse: openUse)
    #expect(Set(found.keys) == ["clean/node_modules", "untracked/node_modules", "dirty/node_modules", "recent/node_modules", "open/node_modules"])
    // Visible, never as free space: each held with why (#374).
    #expect(found.compactMapValues(\.hold) == ["dirty/node_modules": CandidateHold(.uncommittedChanges), "recent/node_modules": CandidateHold(.recentlyEdited),
                                                "open/node_modules": CandidateHold(.projectOpen)])
    #expect(found["open/node_modules"]?.hold?.line == "Its project is open in an app or tool. It is kept.")

    // Ticking is the override for the policy guards; a project in use is still skipped while it is, and cleaned once it isn't.
    let check = { (item: Candidate?, inUse: any InUseChecking) in
        CandidateCheck(catalog: Catalog(rules: fixtureRules), running: NothingRunning(), inUse: inUse, home: fixtureNoHome).check(try #require(item))
    }
    #expect(try check(found["dirty/node_modules"], openUse) == nil)
    #expect(try check(found["recent/node_modules"], openUse) == nil)
    #expect(try check(found["open/node_modules"], openUse) == .projectOpen)
    #expect(try check(found["open/node_modules"], FixtureNothingInUse()) == nil)
}

/// Ticking overrides only the guard the user was shown (#374): a build folder held because its project was open, closed by
/// Clean up, is still kept for a recent edit it was never shown.
@Test func tickingABuildFolderHeldAsOpenNeverOverridesAGuardItWasNotShown() throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try file(folder, "app/package.json"); try file(folder, "app/node_modules/x.js"); try file(folder, "app/src/app.js", age: 2 * day)
    let item = try #require(offered(folder, inUse: FakeInUse(open: [folder.appendingPathComponent("app").path]))["app/node_modules"])
    #expect(item.hold == CandidateHold(.projectOpen))
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: NothingRunning(), inUse: FixtureNothingInUse(), home: fixtureNoHome)
    #expect(check.check(item) == .recentlyEdited)
}

@Test func theCheckRefusesAProjectThatChangedSinceTheScan() throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let project = try committedProject(in: folder, "app")
    let item = try #require(offered(folder)["app/node_modules"])
    let check = { (inUse: any InUseChecking) in
        CandidateCheck(catalog: Catalog(rules: fixtureRules), running: NothingRunning(), inUse: inUse, home: fixtureNoHome).check(item)
    }
    #expect(check(FixtureNothingInUse()) == nil)
    #expect(check(FakeInUse(open: [project.path])) == .projectOpen)
    #expect(check(FakeInUse(unknown: true)) == .projectUnchecked)

    // A tracked file changed, dated as before: uncommitted changes.
    try "changed".write(to: project.appendingPathComponent("index.js"), atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * day)], ofItemAtPath: project.appendingPathComponent("index.js").path)
    #expect(check(FixtureNothingInUse()) == .uncommittedChanges)
    try git(project, "commit", "-q", "-am", "edit")
    #expect(check(FixtureNothingInUse()) == nil)

    // Edited today.
    try file(project, "src/new.js", age: 0)
    #expect(check(FixtureNothingInUse()) == .recentlyEdited)
    try FileManager.default.removeItem(at: project.appendingPathComponent("src"))

    // The marker is gone: it is no longer a project's build folder.
    try FileManager.default.removeItem(at: project.appendingPathComponent("package.json"))
    #expect(check(FixtureNothingInUse()) == .changed)
}

@Test func aBuildFolderGitTracksIsKept() throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let project = try committedProject(in: folder, "site")
    try file(project, "dist/app.js")
    try git(project, "add", "dist"); try git(project, "commit", "-q", "-m", "ship dist")
    #expect(Set(offered(folder).keys) == ["site/node_modules"])
}

private struct NothingRunning: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }

@Test func theWalkNeverLooksInsideAFoundBuildFolderButFindsNestedProjects() throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try file(folder, "app/package.json"); try file(folder, "app/node_modules/dep/package.json"); try file(folder, "app/node_modules/dep/node_modules/x.js")
    try file(folder, "app/target/sub/Cargo.toml"); try file(folder, "app/target/sub/target/x")
    try file(folder, "app/packages/ui/package.json"); try file(folder, "app/packages/ui/dist/x.js")
    // Without a marker, `target` is an ordinary folder that may hold projects.
    try file(folder, "app/target/sub2/Package.swift"); try file(folder, "app/target/sub2/.build/x")
    #expect(Set(offered(folder).keys) == ["app/node_modules", "app/packages/ui/dist", "app/target/sub/target", "app/target/sub2/.build"])
}

@Test func buildFoldersAreChosenOneByOneNeverRecommendedAndGoToTrash() async throws {
    let folder = try pickedFolder(), trash = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: trash) }
    try file(folder, "app/Cargo.toml"); try file(folder, "app/src/main.rs"); try file(folder, "app/target/debug/app")
    let item = try #require(offered(folder)["app/target"])
    let catalog = Catalog(rules: fixtureRules)
    #expect(try #require(catalog.rule(ProjectBuilds.ruleID)).choosesItems)
    #expect(RecommendedPlan(catalog: catalog, candidates: [item], check: { _ in nil }).candidates.isEmpty)

    let journal = try SQLiteCleanupJournal(url: trash.appendingPathComponent("journal.sqlite"))
    let check = CandidateCheck(catalog: catalog, running: NothingRunning(), inUse: FixtureNothingInUse(), home: fixtureNoHome)
    let result = await CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: FolderTrash(folder: trash.appendingPathComponent("Trash")))
        .execute(CatalogApproval(candidates: [item], previewOnly: false))
    #expect(result.records.map(\.state) == [.succeeded])
    #expect(result.records.first?.action == "moveToTrash")
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("app/target").path))
    #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Trash/target/debug/app").path))
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("app/src/main.rs").path))
}

/// Stands in for the Finder Trash so tests never touch the user's real Trash.
private struct FolderTrash: TrashMoving {
    let folder: URL
    func moveToTrash(_ url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

/// A fake git clone: a `.git` folder with a `HEAD`, as SwiftPM leaves in `.build/checkouts`.
private func gitClone(_ folder: URL, _ path: String) throws { try file(folder, path + "/.git/HEAD"); try file(folder, path + "/Sources/a.swift") }

@Test func swiftPMsOwnDependencyClonesDontKeepItsBuildFolderButOtherGitWorkDoes() throws {
    let folder = try pickedFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    // SwiftPM's clones of its dependencies, beside Package.swift: offered.
    try file(folder, "pkg/Package.swift"); try file(folder, "pkg/.build/debug/app")
    try gitClone(folder, "pkg/.build/checkouts/Foo"); try gitClone(folder, "pkg/.build/checkouts/Bar")
    // The same clone anywhere else in a build folder: kept.
    try file(folder, "other/Package.swift"); try file(folder, "other/.build/debug/app"); try gitClone(folder, "other/.build/other/Foo")
    try file(folder, "deep/Package.swift"); try gitClone(folder, "deep/.build/checkouts/Foo/Vendor")
    try file(folder, "web/package.json"); try gitClone(folder, "web/node_modules/pkg")
    // A `checkouts` folder in a build folder that isn't SwiftPM's: kept.
    try file(folder, "rust/Cargo.toml"); try gitClone(folder, "rust/target/checkouts/Foo")

    let found = offered(folder)
    #expect(Set(found.keys) == ["pkg/.build"])
    let item = try #require(found["pkg/.build"])
    let check = CandidateCheck(catalog: Catalog(rules: fixtureRules), running: NothingRunning(), inUse: FixtureNothingInUse(), home: fixtureNoHome)
    #expect(check.check(item) == nil)

    // A git working tree that appears elsewhere in it after the scan is refused at the check.
    try gitClone(folder, "pkg/.build/repositories/Foo")
    #expect(check.check(item) == .protected(".git"))
    try FileManager.default.removeItem(at: folder.appendingPathComponent("pkg/.build/repositories"))
    #expect(check.check(item) == nil)
    // Without its Package.swift, its clones are git work again.
    try FileManager.default.removeItem(at: folder.appendingPathComponent("pkg/Package.swift"))
    #expect(check.check(item) != nil)
}

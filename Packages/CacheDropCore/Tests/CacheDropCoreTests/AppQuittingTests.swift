import Foundation
import Testing
import CacheDropCore

@Test func anOpenAppOffersToQuitItAndACommandLineToolOffersACheck() {
    let app = RunningOwnerNotice(name: "Xcode", appOpen: true)
    #expect(app.text == "Xcode is running")
    #expect(app.action == .quitApp("Quit Xcode"))

    let tool = RunningOwnerNotice(name: "npm", appOpen: false)
    #expect(tool.text == "Quit npm to include this")
    #expect(tool.action == .checkAgain)

    let refused = RunningOwnerNotice(name: "Xcode", appOpen: true, stillOpen: true)
    #expect(refused.text == "Xcode is still open")
    #expect(refused.action == .quitApp("Quit Xcode"))
}

/// Records what CacheDrop asks of apps. It has no force-quit to call, so a test can only see normal quit requests.
private final class FakeQuitter: AppQuitting, @unchecked Sendable {
    private let lock = NSLock()
    private var open: Set<String>
    private let quitsWhenAsked: Bool
    private(set) var quitRequests: [[String]] = []
    init(open: Set<String>, quitsWhenAsked: Bool) { self.open = open; self.quitsWhenAsked = quitsWhenAsked }
    func isOpen(_ bundleIDs: [String]) -> Bool { lock.withLock { !open.isDisjoint(with: bundleIDs) } }
    func requestQuit(_ bundleIDs: [String]) -> Bool {
        lock.withLock {
            quitRequests.append(bundleIDs)
            if quitsWhenAsked { open.subtract(bundleIDs) }
            return true
        }
    }
    func waitUntilClosed(_ bundleIDs: [String], timeout: Duration) async -> Bool { !isOpen(bundleIDs) }
}

@Test func quittingAnAppSendsANormalQuitRequestAndReportsWhetherItQuit() async {
    let owner = RuleOwner(name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"], executables: ["xcodebuild"])
    let polite = FakeQuitter(open: ["com.apple.dt.Xcode"], quitsWhenAsked: true)
    #expect(await AppQuitRequest(quitter: polite).quit(owner) == .quit)
    #expect(polite.quitRequests == [["com.apple.dt.Xcode"]])

    // Unsaved work, or the app refused: it stays open and CacheDrop says so calmly.
    let stubborn = FakeQuitter(open: ["com.apple.dt.Xcode"], quitsWhenAsked: false)
    #expect(await AppQuitRequest(quitter: stubborn).quit(owner) == .stillOpen)
    #expect(stubborn.quitRequests == [["com.apple.dt.Xcode"]])
}

@Test func aCommandLineToolIsNeverAskedToQuit() async {
    let quitter = FakeQuitter(open: [], quitsWhenAsked: true)
    let npm = RuleOwner(name: "npm", executables: ["npm"])
    #expect(await AppQuitRequest(quitter: quitter).quit(npm) == .notAnApp)
    #expect(quitter.quitRequests.isEmpty)
}

/// The real quitter, read-only: Finder is always open and is never asked to quit here.
@Test func theSystemQuitterWaitsForAnOpenAppUntilItsTimeoutAndSendsNothingWhenTurnedOff() async {
    let quitter = SystemAppQuitter(sendsRequests: false)
    #expect(quitter.isOpen(["com.apple.finder"]))
    #expect(!quitter.requestQuit(["com.apple.finder"]))
    #expect(await !quitter.waitUntilClosed(["com.apple.finder"], timeout: .milliseconds(100)))
    #expect(await quitter.waitUntilClosed(["com.example.not-installed-\(UUID())"], timeout: .seconds(5)))
}

/// #377: the quitter a debug UI test run uses. It sees and asks to quit only apps run from inside its fixture folder, so a
/// journey can quit a fixture app it started and never a real one. The local copy of `sleep` is signed as its fixture
/// bundle before launch: its system signature is invalid inside an app and otherwise triggers a damaged-app dialog.
@Test func theFixtureQuitterQuitsOnlyAnAppRunFromItsFolder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropFixtureApps-\(UUID())").resolvingSymlinksInPath()
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropOtherApps-\(UUID())").resolvingSymlinksInPath()
    var started: [Process] = []
    defer {
        for process in started where process.isRunning { process.terminate() }
        for process in started { process.waitUntilExit() }
        try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside)
    }
    func codeSign(_ arguments: [String]) throws {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        command.arguments = arguments
        let errors = Pipe()
        command.standardError = errors
        try command.run()
        command.waitUntilExit()
        let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(command.terminationStatus == 0, "Fixture signing or verification failed before launch: \(diagnostic)")
    }
    func start(_ name: String, id: String, in folder: URL) throws -> Process {
        let bundle = folder.appendingPathComponent("Applications/\(name).app/Contents")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": id, "CFBundleExecutable": name, "CFBundleName": name, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: bundle.appendingPathComponent("MacOS/\(name)").path)
        try codeSign(["--force", "--sign", "-", bundle.deletingLastPathComponent().path])
        try codeSign(["--verify", "--strict", bundle.deletingLastPathComponent().path])
        let process = Process()
        process.executableURL = bundle.appendingPathComponent("MacOS/\(name)")
        process.arguments = ["60"]
        try process.run()
        started.append(process)
        return process
    }
    let synth = try start("Synth", id: "com.maker.synth", in: root), other = try start("Other", id: "com.maker.other", in: outside)
    let quitter = FixtureAppQuitter(root: root)
    #expect(quitter.isOpen(["com.maker.synth"]))
    #expect(!quitter.isOpen(["com.maker.other"]), "Never an app outside its folder")
    #expect(!quitter.isOpen(["com.apple.finder"]))
    #expect(!quitter.requestQuit(["com.maker.other"]))
    #expect(other.isRunning)

    #expect(quitter.requestQuit(["com.maker.synth"]))
    #expect(await quitter.waitUntilClosed(["com.maker.synth"], timeout: .seconds(5)))
    // The process can disappear from libproc before Foundation delivers its termination notification.
    synth.waitUntilExit()
    #expect(!synth.isRunning)
    #expect(!quitter.isOpen(["com.maker.synth"]))
}

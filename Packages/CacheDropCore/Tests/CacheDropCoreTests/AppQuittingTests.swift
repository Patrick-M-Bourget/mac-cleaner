import Foundation
import Testing
import CacheDropCore

@Test func anOpenAppOffersToQuitItAndACommandLineToolOffersACheck() {
    let app = RunningOwnerNotice(name: "Xcode", appOpen: true)
    #expect(app.text == "Xcode is running.")
    #expect(app.action == .quitApp("Quit Xcode"))

    let tool = RunningOwnerNotice(name: "npm", appOpen: false)
    #expect(tool.text == "Quit npm to include this.")
    #expect(tool.action == .checkAgain)

    let refused = RunningOwnerNotice(name: "Xcode", appOpen: true, stillOpen: true)
    #expect(refused.text == "Xcode is still open.")
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

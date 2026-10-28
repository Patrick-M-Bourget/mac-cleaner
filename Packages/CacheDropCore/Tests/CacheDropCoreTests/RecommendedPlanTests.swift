import Foundation
import Testing
@testable import CacheDropCore

/// An item a rule found, as the scan would offer it. Nothing here touches disk: the plan is chosen from the scan and the checks alone.
private func item(_ ruleID: String, action: CleanupAction? = nil, bytes: Int64 = 1_000, complete: Bool = true, name: String? = nil, lastUsed: Date? = nil,
                  tie: LeftoverTie? = nil) -> Candidate {
    let rule = Catalog(rules: fixtureRules).rule(ruleID)
    var found = Candidate(ruleID: ruleID, action: action ?? rule?.action ?? .delete, url: fixtureNoHome.appendingPathComponent(name ?? ruleID), resourceID: "1:\(ruleID.hashValue)",
                          isDirectory: true, toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: bytes, allocatedBytes: bytes,
                          sizeComplete: complete, lastUsed: lastUsed, observedAt: Date(), profile: nil)
    found.leftover = tie
    return found
}
private let catalog = Catalog(rules: fixtureRules)
/// A fixed "now", so the 90-day installer boundary is exact.
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
private func recommended(_ items: [Candidate], refusing refused: [String: CheckRefusal] = [:]) -> [String] {
    RecommendedPlan(catalog: catalog, candidates: items, now: now) { refused[$0.ruleID] }.candidates.map(\.ruleID)
}

@Test func theRecommendedPlanTakesDataThatRebuildsItself() {
    // A cache, build data, an updater download, a log and a leaked app copy, each deleted.
    let ids = ["npm-cache", "xcode-derived-data", "updater-downloads", "crash-reports", "chrome-code-sign-clones"]
    #expect(ids.allSatisfy { catalog.rule($0) != nil })
    #expect(recommended(ids.map { item($0) }) == ids)
}

@Test func anItemWhoseSizeIsUnknownIsNotRecommended() {
    #expect(recommended([item("npm-cache", bytes: 0, complete: false)]).isEmpty)
    // A lower bound is still a known size: at least that much comes back.
    #expect(recommended([item("npm-cache", bytes: 5_000, complete: false)]) == ["npm-cache"])
}

@Test func anItemTheChecksWouldRefuseIsNotRecommended() {
    #expect(recommended([item("npm-cache")], refusing: ["npm-cache": .ownerRunning("npm")]).isEmpty)
    #expect(recommended([item("npm-cache")], refusing: ["npm-cache": .ownerUnknown("npm")]).isEmpty)
    #expect(recommended([item("chrome-code-sign-clones")], refusing: ["chrome-code-sign-clones": .inUse("Google Chrome")]).isEmpty)
    #expect(recommended([item("npm-cache")], refusing: ["npm-cache": .excluded]).isEmpty)
}

@Test func installersNotOpenedOrChangedIn90DaysAreRecommended() {
    // #319: a disk image or package in Downloads, sent to the Trash, once nothing has opened or changed it for 90 days.
    #expect(recommended([item("downloads-installers", name: "Setup.dmg", lastUsed: daysAgo(91))]) == ["downloads-installers"])
    #expect(recommended([item("downloads-installers", name: "Tool.PKG", lastUsed: daysAgo(400))]) == ["downloads-installers"])
    #expect(recommended([item("downloads-installers", name: "Setup.dmg", lastUsed: daysAgo(90))]) == ["downloads-installers"], "90 days to the second is old enough")
}

@Test func recentInstallersArchivesAndUndatedInstallersAreNotRecommended() {
    #expect(recommended([item("downloads-installers", name: "Setup.dmg", lastUsed: daysAgo(89.99))]).isEmpty, "Opened or changed within 90 days")
    #expect(recommended([item("downloads-installers", name: "Setup.dmg", lastUsed: nil)]).isEmpty, "No date: not known to be old")
    #expect(recommended([item("downloads-installers", name: "Photos.zip", lastUsed: daysAgo(400))]).isEmpty, "An archive may be anything")
    #expect(recommended([item("downloads-installers", action: .delete, name: "Setup.dmg", lastUsed: daysAgo(400))]).isEmpty, "Only to the Trash")
}

@Test func otherLargeOldDownloadsAreNotRecommended() {
    #expect(recommended([item("downloads-old-large", name: "Movie.mov", lastUsed: daysAgo(400))]).isEmpty)
}

@Test func leftoversABundleIDOrReceiptTiesToTheirAppAreRecommended() {
    let byID = LeftoverTie(app: "Synth", bundleID: "com.gone.synth", vendor: "com.gone", evidence: .bundleID)
    let byReceipt = LeftoverTie(app: "Foo", bundleID: nil, vendor: "com.foocorp", evidence: .receipt("com.foocorp.foo.pkg"))
    #expect(recommended([item(RemovedAppLeftovers.ruleID, tie: byID), item(RemovedAppLeftovers.ruleID, tie: byReceipt)])
            == [RemovedAppLeftovers.ruleID, RemovedAppLeftovers.ruleID])
}

@Test func possiblyRelatedLeftoversAreNotRecommended() {
    let named = LeftoverTie(app: "Gone", bundleID: "com.gone.app", vendor: "com.gone", evidence: .nameOnly("Named like Gone"))
    #expect(recommended([item(RemovedAppLeftovers.possiblyRelatedRuleID, tie: named)]).isEmpty)
    // Even under the confirmed rule, a name-only tie, or none, is never taken.
    #expect(recommended([item(RemovedAppLeftovers.ruleID, tie: named), item(RemovedAppLeftovers.ruleID)]).isEmpty)
}

@Test func appUninstallsAreNotRecommended() {
    let uninstalls = AppRuleFamily.uninstallRules
    #expect(!uninstalls.isEmpty)
    #expect(recommended(uninstalls.map { item($0.id) }).isEmpty)
}

@Test func iCloudCopiesAreNotRecommended() {
    #expect(catalog.rule("icloud-local-copies")?.action == .evict)
    #expect(recommended([item("icloud-local-copies")]).isEmpty)
}

@Test func cachesAToolCleansWithItsOwnCommandAreRecommended() {
    // #319: Homebrew's cache, the pnpm store, uv's cache and unavailable simulators, each through the tool's own command.
    let ids = ["homebrew", "pnpm-store", "uv-cache", "xcode-simulators"]
    #expect(ids.allSatisfy { catalog.rule($0)?.action == .tool })
    #expect(recommended(ids.map { item($0) }) == ids)
}

@Test func toolActionsChosenOneByOneAreNotRecommended() {
    // Each simulator, runtime or Ollama model is chosen on its own.
    #expect(recommended([item("simulator-devices"), item("simulator-runtimes"), item("ollama-models")]).isEmpty)
}

@Test func leftoversOfAToolRuleAreNotRecommended() {
    #expect(recommended([item("homebrew", action: .delete, name: ".cachedrop-deleting-homebrew-\(UUID().uuidString)")]).isEmpty)
}

@Test func modelsAndVMImagesAreNotRecommended() {
    #expect(recommended([item("huggingface-models"), item("ollama-models"), item("app-vm-images")]).isEmpty)
    #expect(recommended([item("huggingface-models", action: .delete)]).isEmpty)
}

@Test func dockerIsNotRecommended() {
    #expect(recommended([item("docker-images"), item("docker-build-cache"), item("docker-containers")]).isEmpty)
}

@Test func guidanceIsNotRecommended() {
    let guidance = catalog.rules.filter { $0.action == .guidance }
    #expect(!guidance.isEmpty)
    #expect(recommended(guidance.map { item($0.id) }).isEmpty)
    #expect(recommended(guidance.map { item($0.id, action: .delete) }).isEmpty)
}

@Test func userFilesAreNotRecommended() {
    let picked = UserFiles.rule.id
    #expect(recommended([item(picked), item(picked, action: .delete)]).isEmpty)
}

@Test func onlyTheSafeItemsOfAMixedScanAreRecommended() {
    let scan = [item("downloads-installers", name: "New.dmg", lastUsed: daysAgo(3)), item("npm-cache"), item("ollama-models"), item("app-logs"), item("homebrew"),
                item("pip-cache"), item("docker-images"), item("downloads-installers", name: "Old.dmg", lastUsed: daysAgo(200))]
    #expect(recommended(scan, refusing: ["pip-cache": .ownerRunning("pip")]) == ["npm-cache", "app-logs", "homebrew", "downloads-installers"])
}

@Test func jetBrainsCachesAndOldTemporaryFilesAreNotRecommended() {
    // A JetBrains folder holds local history that doesn't rebuild; a temporary file can be anything an app left (#144).
    #expect(catalog.rule("jetbrains-caches") != nil && catalog.rule("temporary-files") != nil)
    #expect(recommended([item("jetbrains-caches"), item("temporary-files")]).isEmpty)
    // Caches apps keep in `C` rebuild themselves and stay in.
    #expect(recommended([item("temporary-app-caches")]) == ["temporary-app-caches"])
}

@Test func noRuleWhoseItemsAreChosenOneByOneIsRecommended() {
    // Installers are the one exception, by their own rule above (#319); undated, they are never taken.
    let chosen = catalog.rules.filter(\.choosesItems)
    #expect(Set(chosen.map(\.id)).isSuperset(of: ["jetbrains-caches", "temporary-files", "android-system-images", "ollama-models", "icloud-local-copies"]))
    #expect(recommended(chosen.map { item($0.id) } + chosen.map { item($0.id, action: .delete) }).isEmpty)
}

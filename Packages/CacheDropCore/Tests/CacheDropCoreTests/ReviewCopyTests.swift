import Foundation
import Testing
@testable import CacheDropCore

/// Every app is installed, so the catalog's per-app rules are all built.
private struct EveryApp: AppLookup {
    func app(bundleID: String) -> InstalledApp? { InstalledApp(name: "Synth", bundleID: bundleID, path: "/Applications/Synth.app") }
    func app(updaterCacheDirName name: String) -> InstalledApp? { InstalledApp(name: "Synth", bundleID: "com.maker.synth", path: "/Applications/Synth.app") }
}

private func sentences(_ text: String) -> Int { text.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count }

/// #462, Decision 92 rules 2 and 7: the review sheet's group says what happens once; each rule adds at most one sentence
/// of its own and never repeats the group or the command shown under its files.
@Test func reviewCopyIsOneSentenceAndRulesDontRepeatTheirGroup() {
    for group in ConsequenceGroup.allCases {
        #expect(sentences(group.consequence) == 1, "\(group): \(group.consequence)")
    }
    let rules = BuiltInCatalog.rules(apps: EveryApp()) + AppUninstall.rules + PlugInUninstall.rules
    for rule in rules where rule.action != .guidance {
        #expect(sentences(rule.consequence) <= 1, "\(rule.id): \(rule.consequence)")
        for repeated in ["Permanently removed", "Moved to Trash", "Runs `", "restore", "Trash in Finder"] {
            #expect(!rule.consequence.contains(repeated), "\(rule.id) repeats \"\(repeated)\": \(rule.consequence)")
        }
    }
}

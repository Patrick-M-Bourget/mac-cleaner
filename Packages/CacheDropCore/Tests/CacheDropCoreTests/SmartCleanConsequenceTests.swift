import Testing
@testable import CacheDropCore

/// #319: Smart clean shows one consequence line per category, from what the category's ticked rules do.
private let catalog = Catalog(rules: fixtureRules)
private func line(_ category: CatalogCategory, _ ids: [String]) -> String {
    SmartCleanConsequence.line(for: category, rules: ids.compactMap(catalog.rule))
}

@Test func trashBoundCategoriesSayTheyGoToTheTrash() {
    #expect(line(.downloads, ["downloads"]) == "Goes to the Trash; Put back works")
    #expect(line(.leftovers, [RemovedAppLeftovers.ruleID]) == "Goes to the Trash; Put back works")
}

@Test func deletedCategoriesSayHowTheyComeBack() {
    #expect(line(.developer, ["npm-cache", "xcode-derived-data"]) == "Comes back on its own when your tools and Xcode need it")
    #expect(line(.browser, ["chrome-cache"]) == "Comes back on its own as you browse")
    #expect(line(.system, ["app-caches"]) == "Comes back on its own when apps need it")
    #expect(line(.updaters, ["updater-downloads"]) == "Comes back on its own when apps check for updates")
    #expect(line(.logs, ["app-logs"]) == "Apps write new logs as they run")
}

@Test func aCategoryWithAToolCommandSaysTheToolCleansIt() {
    #expect(line(.developer, ["npm-cache", "homebrew"]) == "Comes back on its own when your tools and Xcode need it; some tools clean their own")
    #expect(line(.developer, ["homebrew"]) == "Comes back on its own when your tools and Xcode need it; some tools clean their own")
}

@Test func aCategoryThatMixesTrashWithOtherActionsSaysPartGoesToTheTrash() {
    #expect(line(.developer, ["npm-cache", "project-builds"]) == "Comes back on its own when your tools and Xcode need it; some goes to the Trash")
}

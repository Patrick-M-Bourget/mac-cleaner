import Foundation
import Testing
@testable import CacheDropCore

private struct Row: Equatable { let name: String; let maker: String?; let bytes: Int64 }
private let rows = [Row(name: "logic pro", maker: "Apple", bytes: 50), Row(name: "Zebra", maker: "u-he", bytes: 900),
                    Row(name: "Ableton Live 12", maker: "Ableton AG", bytes: 300), Row(name: "Ableton Live 2", maker: "Ableton AG", bytes: 300),
                    Row(name: "Éclair", maker: nil, bytes: 10)]
private func names(_ listing: ApplicationsListing) -> [String] { listing.arranged(rows, name: \.name, maker: \.maker, bytes: \.bytes).map(\.name) }

/// #295: Name sorts as Finder does: case and accents don't matter, and numbers read as numbers.
@Test func nameSortsAsFinderDoes() {
    #expect(names(ApplicationsListing(order: .name)) == ["Ableton Live 2", "Ableton Live 12", "Éclair", "logic pro", "Zebra"])
}

/// #295, Decision 51: Size is largest first, the default; rows of one size go by name.
@Test func sizeIsLargestFirstAndTheDefault() {
    #expect(names(ApplicationsListing()) == ["Zebra", "Ableton Live 2", "Ableton Live 12", "logic pro", "Éclair"])
}

/// #295: the search matches a row's name or maker, ignoring case and accents; an empty or blank search shows every row.
@Test func searchMatchesNameOrMaker() {
    #expect(names(ApplicationsListing(search: "ableton ag")) == ["Ableton Live 2", "Ableton Live 12"], "By maker")
    #expect(names(ApplicationsListing(order: .name, search: "ECLAIR")) == ["Éclair"], "By name, case and accents aside")
    #expect(names(ApplicationsListing(search: "U-HE ")) == ["Zebra"], "Spaces around it don't count")
    #expect(names(ApplicationsListing(search: "nothing like it")).isEmpty)
    #expect(names(ApplicationsListing(search: "  ")).count == rows.count, "Clearing it shows everything again")
}

private struct NoApps: AppPresence {
    func installedApps() -> [InstalledApp]? { [] }
    func isRegistered(bundleID: String) -> Bool { false }
}
private struct NoReceipts: InstallerReceiptReading { func receipts() -> [InstallerReceipt] { [] } }

/// #295: a leftover is searched by the removed app it is grouped under, or by its maker.
@Test func aLeftoverMatchesItsAppOrItsMaker() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("ApplicationsListingTests-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    for relative in ["Library/Preferences/com.gone.synth.plist", "Library/Preferences/com.other.pad.plist"] {
        let file = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: file)
    }
    let found = RemovedAppLeftovers.scan(home: home, apps: NoApps(), receipts: NoReceipts(), exclusions: ExclusionPolicy())
    func matched(_ search: String) -> [String] { found.filter(ApplicationsListing(search: search).matches).map(\.url.lastPathComponent) }
    #expect(found.count == 2)
    #expect(matched("synth") == ["com.gone.synth.plist"], "By the app's name")
    #expect(matched("Other") == ["com.other.pad.plist"], "By its maker")
    #expect(matched("").count == 2)
}

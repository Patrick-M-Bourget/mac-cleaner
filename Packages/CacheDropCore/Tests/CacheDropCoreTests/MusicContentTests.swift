import Foundation
import Testing
@testable import CacheDropCore

/// A fixture Mac: `system` stands in for `/`, `home` for the user's home folder.
private struct FixtureMac {
    let root: URL
    var system: URL { root.appendingPathComponent("system") }
    var home: URL { root.appendingPathComponent("home") }
    /// Stands in for `/Volumes`: a drive is connected when its folder is there.
    var volumes: URL { root.appendingPathComponent("Volumes") }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MusicContentTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    /// Makes a folder with one file of `bytes` bytes in it, at a path under the system root ("/…") or the home folder.
    @discardableResult func folder(_ path: String, bytes: Int = 4_096) throws -> URL {
        let url = path.hasPrefix("/") ? system.appendingPathComponent(String(path.dropFirst())) : home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url.appendingPathComponent("content.bin"))
        return url
    }
    func scan(_ owners: [ContentOwner], configured: @escaping @Sendable (MusicVendor) -> [MusicVendor.Configured] = { _ in [] }) -> MusicContent {
        MusicContent.scan(owners: owners, home: home, systemRoot: system, volumes: volumes, configured: configured)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private let reasonRack = ContentOwner(id: "reason-rack", name: "Reason Rack Plugin", bundleID: "se.propellerheads.reasonrackplugin.vst")
private let live = ContentOwner(id: "live", name: "Ableton Live 12 Suite", bundleID: "com.ableton.live")
private let logic = ContentOwner(id: "logic", name: "Logic Pro", bundleID: "com.apple.logic10")
private let mainStage = ContentOwner(id: "mainstage", name: "MainStage", bundleID: "com.apple.mainstage3")
private let pigments = ContentOwner(id: "pigments", name: "Pigments", bundleID: "com.arturia.pigments.vst3")
private let analogLab = ContentOwner(id: "analoglab", name: "Analog Lab", bundleID: "com.arturia.analoglab.component")
private let wavesShell = ContentOwner(id: "waves", name: "WaveShell1-VST3 15", bundleID: "com.WavesAudio.WaveShell1-VST3.15")
private let unrelated = ContentOwner(id: "other", name: "Serum", bundleID: "com.xferrecords.serum")

/// #175: Reason's sound banks and shared resources are its content; ReWire and REX libraries in the same folder are not.
@Test func reasonContentIsAttachedToReasonProducts() throws {
    let mac = try FixtureMac(); defer { mac.remove() }
    try mac.folder("/Library/Application Support/Propellerhead Software/Soundbanks")
    try mac.folder("/Library/Application Support/Propellerhead Software/SharedResources")
    try mac.folder("/Library/Application Support/Propellerhead Software/ReWire")

    let content = mac.scan([reasonRack, unrelated])

    #expect(content.items.map(\.name).sorted() == ["Shared resources", "Sound banks"])
    #expect(content.items.allSatisfy { $0.vendor == "Reason Studios" && $0.owners == ["reason-rack"] && $0.kind == .installed })
    #expect(content.items(for: "other").isEmpty)
    #expect(content.items(for: "reason-rack").count == 2)
}

/// #175: Ableton's Packs are installed content; its User Library is the user's own and never grouped with them.
@Test func abletonUserLibraryIsTheUsersAndPacksAreInstalled() throws {
    let mac = try FixtureMac(); defer { mac.remove() }
    try mac.folder("Music/Ableton/Factory Packs")
    try mac.folder("Music/Ableton/User Library")
    try mac.folder("Music/Ableton/Live Recordings")

    let content = mac.scan([live])

    #expect(content.items.map(\.name).sorted() == ["Packs", "User Library"])
    #expect(content.installed.map(\.name) == ["Packs"])
    #expect(content.yours.map(\.name) == ["User Library"])
    #expect(content.items(for: "live").count == 2)
}

/// #175: Logic Pro and MainStage share one sound library, and the legacy Logic content too: each shows once, with both owners.
@Test func logicContentIsSharedWithMainStageAndShownOnce() throws {
    let mac = try FixtureMac(); defer { mac.remove() }
    try mac.folder("Music/Logic Pro Library.bundle", bytes: 8_192)
    try mac.folder("/Library/Application Support/Logic")
    try mac.folder("/Library/Audio/Apple Loops/Apple")
    try mac.folder("/Library/Audio/Impulse Responses/Apple")

    let content = mac.scan([logic, mainStage, unrelated])

    #expect(content.items.map(\.name).sorted() == ["Apple Loops", "Impulse responses", "Logic Pro Library", "Logic content"])
    #expect(content.items.allSatisfy { $0.vendor == "Apple" && $0.owners == ["logic", "mainstage"] && $0.isShared })
    #expect(content.items.allSatisfy { $0.tie == .bundleID }, "Apple's content belongs to the named apps, not to every Apple app")
}

/// #175: a location reached two ways (a default that links to a configured one) is one item, counted once.
@Test func contentReachedTwoWaysIsCountedOnce() throws {
    let mac = try FixtureMac(); defer { mac.remove() }
    let packs = try mac.folder("/Volumes/Studio/Ableton Packs", bytes: 8_192)
    try FileManager.default.createDirectory(at: mac.home.appendingPathComponent("Music/Ableton"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: mac.home.appendingPathComponent("Music/Ableton/Factory Packs"), withDestinationURL: packs)

    let content = mac.scan([live], configured: { $0.name == "Ableton" ? [.init(url: packs, kind: .installed)] : [] })

    #expect(content.items.count == 1)
    #expect(content.items.first?.owners == ["live"])
    guard case .present(let size)? = content.items.first?.state, case .measured(let bytes) = size else {
        Issue.record("The linked folder is measured once, through its target"); return
    }
    #expect(bytes >= 8_192)
    #expect(content.size == size)
}

/// #175: a library on a drive that isn't connected is reported offline with its volume, never dropped or called removed.
@Test func aLibraryOnAMissingVolumeIsOffline() throws {
    let mac = try FixtureMac(); defer { mac.remove() }
    let drive = "Studio"
    let away = mac.volumes.appendingPathComponent("\(drive)/Ableton Packs")
    try FileManager.default.createDirectory(at: mac.home.appendingPathComponent("Music/Ableton"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: mac.home.appendingPathComponent("Music/Ableton/Factory Packs"), withDestinationURL: away)

    let content = mac.scan([live], configured: { $0.name == "Ableton" ? [.init(url: mac.volumes.appendingPathComponent("\(drive)/User Library"), kind: .yours)] : [] })

    #expect(content.items.map(\.name) == ["Packs", "User Library"])
    #expect(content.items.allSatisfy { $0.state == .offline(volume: drive) && $0.owners == ["live"] })
    #expect(content.yours.map(\.name) == ["User Library"], "Offline content keeps its kind")
    #expect(content.size == .measured(0))
}

/// #175: a Finder alias left where a library was moved from is followed for inventory; when its target is gone, it is offline.
@Test func anAliasToAMovedLibraryIsFollowedAndOfflineWhenItsTargetIsGone() throws {
    let mac = try FixtureMac(); defer { mac.remove() }
    let moved = try mac.folder("Elsewhere/Waves Samples", bytes: 8_192)
    let folder = mac.system.appendingPathComponent("Applications/Waves/Data/Instrument Data")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let alias = folder.appendingPathComponent("Waves Sample Libraries")
    try URL.writeBookmarkData(try moved.bookmarkData(options: .suitableForBookmarkFile), to: alias)

    let found = mac.scan([wavesShell])
    #expect(found.items.map(\.name) == ["Sample libraries"])
    #expect(found.items.first?.owners == ["waves"])
    guard case .present(.measured(let bytes))? = found.items.first?.state else { Issue.record("The alias's target is measured"); return }
    #expect(bytes >= 8_192)

    try FileManager.default.removeItem(at: moved)
    #expect(mac.scan([wavesShell]).items.first?.state == .offline(volume: nil))
}

/// #175: Arturia's resources folder serves all its products: one item, shared with every Arturia product installed.
@Test func arturiaResourcesAreSharedByEveryArturiaProduct() throws {
    let mac = try FixtureMac(); defer { mac.remove() }
    try mac.folder("/Library/Arturia")

    let center = ContentOwner(id: "asc", name: "Arturia Software Center", bundleID: "com.arturia.ArturiaSoftwareCenter")
    let content = mac.scan([pigments, center, analogLab, unrelated])

    #expect(content.items.map(\.name) == ["Resources"])
    #expect(content.items.first?.owners == ["pigments", "analoglab"], "The vendor's manager installs content; it doesn't own it")
    #expect(content.items.first?.isShared == true)
    #expect(content.items.first?.tie == .vendor, "Decision 52: no receipt or bundle ID ties it to one product, so the vendor does")
    #expect(content.items(for: "other").isEmpty)
}

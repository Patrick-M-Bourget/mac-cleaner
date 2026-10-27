import Foundation
import Testing
@testable import CacheDropCore

/// Plug-in inventory (#174, Decision 42). Every test builds its own fixture system root and home: never the real
/// `/Library`, `/Applications` or `/var/db/receipts`.
private func fixtureFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropPlugIns\(name)-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private let arm64: UInt32 = 0x0100_000c, x86_64: UInt32 = 0x0100_0007

/// A plug-in bundle with an Info.plist and a Mach-O header for `architectures`; its code is never loaded.
@discardableResult
private func plugIn(_ relative: String, in root: URL, id: String?, version: String = "1.0", component: String? = nil,
                    architectures: [UInt32] = [arm64], extensionPoint: String? = nil, bytes: Int = 4096) throws -> URL {
    let bundle = root.appendingPathComponent(relative)
    let executable = bundle.deletingPathExtension().lastPathComponent
    try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleExecutable": executable, "CFBundleShortVersionString": version]
    if let id { info["CFBundleIdentifier"] = id }
    let components = component.map { [["name": $0, "manufacturer": "Fxtr", "type": "aufx", "subtype": "fxtr"]] }
    if let extensionPoint {
        var attributes: [String: Any] = [:]
        if let components { attributes["AudioComponents"] = components }
        info["NSExtension"] = ["NSExtensionPointIdentifier": extensionPoint, "NSExtensionAttributes": attributes]
    } else if let components { info["AudioComponents"] = components }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    var header = Data()
    func big(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { header.append(contentsOf: $0) } }
    func little(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
    if architectures.count == 1 { little(0xfeed_facf); little(architectures[0]) }
    else { big(0xcafe_babe); big(UInt32(architectures.count)); for cpu in architectures { big(cpu); big(0); big(4096); big(16); big(12) } }
    header.append(Data(repeating: 0, count: max(0, bytes - header.count)))
    try header.write(to: bundle.appendingPathComponent("Contents/MacOS/" + executable))
    return bundle
}

private func scan(_ root: URL, _ home: URL) -> PlugInInventory {
    PlugInInventory.scan(home: home, systemRoot: root, sizer: KnownLocationSizer(timeBudget: 5))
}

@Test func allSixFormatsAreFoundInSystemAndUserFolders() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    let plugIns = "Library/Audio/Plug-Ins/"
    try plugIn(plugIns + "Components/Alpha.component", in: root, id: nil)
    try plugIn(plugIns + "VST/Beta.vst", in: root, id: nil)
    try plugIn(plugIns + "VST3/Vendor/Gamma.vst3", in: root, id: nil)
    try plugIn(plugIns + "CLAP/Delta.clap", in: root, id: nil)
    try plugIn("Library/Application Support/Avid/Audio/Plug-Ins/Epsilon.aaxplugin", in: root, id: nil)
    try plugIn("Applications/Zeta.app/Contents/PlugIns/Zeta AU.appex", in: root, id: nil, extensionPoint: "com.apple.AudioUnit-UI")
    try plugIn("Applications/Zeta.app/Contents/PlugIns/Widget.appex", in: root, id: nil, extensionPoint: "com.apple.widgetkit-extension")
    try plugIn(plugIns + "Components/Eta.component", in: home, id: nil)
    try plugIn(plugIns + "VST/Theta.vst", in: home, id: nil)
    try plugIn(plugIns + "VST3/Iota.vst3", in: home, id: nil)
    try plugIn(plugIns + "CLAP/Kappa.clap", in: home, id: nil)
    try plugIn("Applications/Lambda.app/Contents/PlugIns/Lambda.appex", in: home, id: nil, extensionPoint: "com.apple.AudioUnit")

    let files = scan(root, home).products.flatMap(\.files)
    let found = Dictionary(uniqueKeysWithValues: files.map { ($0.url.path, $0.format) })
    let expected: [(URL, String, PlugInFormat)] = [
        (root, plugIns + "Components/Alpha.component", .au), (root, plugIns + "VST/Beta.vst", .vst), (root, plugIns + "VST3/Vendor/Gamma.vst3", .vst3),
        (root, plugIns + "CLAP/Delta.clap", .clap), (root, "Library/Application Support/Avid/Audio/Plug-Ins/Epsilon.aaxplugin", .aax),
        (root, "Applications/Zeta.app/Contents/PlugIns/Zeta AU.appex", .auv3),
        (home, plugIns + "Components/Eta.component", .au), (home, plugIns + "VST/Theta.vst", .vst), (home, plugIns + "VST3/Iota.vst3", .vst3),
        (home, plugIns + "CLAP/Kappa.clap", .clap), (home, "Applications/Lambda.app/Contents/PlugIns/Lambda.appex", .auv3),
    ]
    #expect(found.count == expected.count, "\(found.keys.sorted())")
    for (base, path, format) in expected { #expect(found[base.appendingPathComponent(path).path] == format, "\(path)") }
}

/// A real installer receipt in the fixture root: its plist, and a BOM made by `mkbom` from a staging copy of `paths`.
private func receipt(_ id: String, listing paths: [String], in root: URL) throws {
    let receipts = root.appendingPathComponent("var/db/receipts"), staging = try fixtureFolder("Staging")
    defer { try? FileManager.default.removeItem(at: staging) }
    try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
    for path in paths { try FileManager.default.createDirectory(at: staging.appendingPathComponent(path + "/Contents"), withIntermediateDirectories: true) }
    let info: [String: Any] = ["PackageIdentifier": id, "PackageVersion": "1.0", "InstallPrefixPath": "/"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: receipts.appendingPathComponent(id + ".plist"))
    let mkbom = Process()
    mkbom.executableURL = URL(fileURLWithPath: "/usr/bin/mkbom")
    mkbom.arguments = [staging.path, receipts.appendingPathComponent(id + ".bom").path]
    try mkbom.run(); mkbom.waitUntilExit()
    #expect(mkbom.terminationStatus == 0)
}

@Test func aProductWithSeveralFormatsIsOneRowWithItsDetails() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    let au = "Library/Audio/Plug-Ins/Components/Pro Synth.component", aax = "Library/Application Support/Avid/Audio/Plug-Ins/ProSynthAAX.aaxplugin"
    try plugIn(au, in: root, id: "com.maker.prosynth.au", version: "2.1", component: "Maker Audio: Pro Synth", architectures: [arm64, x86_64])
    try plugIn(aax, in: root, id: nil, version: "2.1", architectures: [arm64])
    // Installed by the same receipt, so one product though their names and bundle IDs differ.
    try receipt("com.maker.prosynth.pkg", listing: [au, aax], in: root)
    // No receipt: the VST3 joins by its bundle ID's vendor and its name.
    try plugIn("Library/Audio/Plug-Ins/VST3/Pro Synth.vst3", in: home, id: "com.maker.vst3.Pro Synth", version: "2.0")

    let products = scan(root, home).products
    #expect(products.count == 1)
    let product = try #require(products.first)
    #expect(product.name == "Pro Synth")
    #expect(product.maker == "Maker Audio")
    #expect(product.formats == [.au, .vst3, .aax])
    #expect(product.versions == ["2.1", "2.0"])
    #expect(product.architectures == ["Apple silicon", "Intel"])
    #expect(product.grouping == .receipt)
    #expect(product.removable)
    guard case .measured(let bytes) = product.size else { Issue.record("Expected a measured size, got \(product.size)"); return }
    #expect(bytes >= 3 * 4096)
}

@Test func filesNothingTiesTogetherStandAloneAndOwnersStayApart() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    let vst3 = "Library/Audio/Plug-Ins/VST3/"
    // Same name, different makers: two products.
    try plugIn(vst3 + "Reverb.vst3", in: root, id: "com.alpha.Reverb")
    try plugIn("Library/Audio/Plug-Ins/Components/Reverb.component", in: root, id: "com.beta.reverb.au")
    // A receipt for one maker's file doesn't take in the other maker's file beside it.
    try receipt("com.alpha.reverb.pkg", listing: [vst3 + "Reverb.vst3"], in: root)
    // No bundle ID and no receipt: on their own, even with the same name.
    try plugIn(vst3 + "Loose.vst3", in: root, id: nil)
    try plugIn("Library/Audio/Plug-Ins/CLAP/Loose.clap", in: home, id: nil)

    let products = scan(root, home).products
    #expect(products.count == 4)
    #expect(products.allSatisfy { $0.files.count == 1 })
    let byPath = Dictionary(uniqueKeysWithValues: products.map { ($0.files[0].url.path, $0) })
    #expect(byPath[root.appendingPathComponent(vst3 + "Reverb.vst3").path]?.grouping == .receipt)
    #expect(byPath[root.appendingPathComponent("Library/Audio/Plug-Ins/Components/Reverb.component").path]?.grouping == .bundleID)
    #expect(byPath[root.appendingPathComponent(vst3 + "Loose.vst3").path]?.grouping == PlugInProduct.Grouping.none)
    #expect(byPath[home.appendingPathComponent("Library/Audio/Plug-Ins/CLAP/Loose.clap").path]?.grouping == PlugInProduct.Grouping.none)
}

@Test func missingReceiptsAndMissingFoldersLeaveTheRestListed() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    // No plug-in folder, no Applications and no receipts folder: nothing, and no error.
    #expect(scan(root, home).products.isEmpty)
    let a = "Library/Audio/Plug-Ins/VST3/Drum A.vst3", b = "Library/Audio/Plug-Ins/VST3/Drum B.vst3"
    try plugIn(a, in: root, id: nil)
    try plugIn(b, in: root, id: nil)
    try receipt("com.drums.pkg", listing: [a, b], in: root)
    #expect(scan(root, home).products.count == 1)
    // The receipt's BOM is gone: the files are no longer tied, and each is listed on its own.
    try FileManager.default.removeItem(at: root.appendingPathComponent("var/db/receipts/com.drums.pkg.bom"))
    let products = scan(root, home).products
    #expect(products.count == 2)
    #expect(products.allSatisfy { $0.grouping == .none })
}

@Test func applesOwnAudioUnitsAreNeverRemovable() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    try plugIn("Library/Audio/Plug-Ins/Components/AUNetSend.component", in: root, id: "com.apple.audio.units.netsend")
    try plugIn("Applications/GarageBand.app/Contents/PlugIns/Sampler.appex", in: root, id: "com.apple.garageband10.sampler", extensionPoint: "com.apple.AudioUnit")
    try plugIn("Library/Audio/Plug-Ins/Components/Synth.component", in: root, id: "com.maker.synth")
    let products = scan(root, home).products
    #expect(products.count == 3)
    #expect(products.filter(\.isApple).count == 2)
    #expect(products.filter(\.removable).map(\.name) == ["Synth"])
}

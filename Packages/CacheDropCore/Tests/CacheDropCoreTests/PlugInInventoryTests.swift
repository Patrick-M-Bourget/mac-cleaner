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
    #expect(!product.isApple)
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
    #expect(products.filter { !$0.isApple }.map(\.name) == ["Synth"])
}

@Test func theAudioPlugInsGuidanceCountsAAXAndCarriesTheInventory() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    try plugIn("Library/Application Support/Avid/Audio/Plug-Ins/Big.aaxplugin", in: root, id: "com.maker.big", bytes: 40_960)
    try plugIn("Library/Audio/Plug-Ins/VST3/Big.vst3", in: home, id: "com.maker.vst3.big", bytes: 8192)
    let finding = try #require(Catalog(rules: fixtureRules).guidance(home: home, systemRoot: root, snapshots: FixtureSnapshots()).first { $0.ruleID == "audio-plug-ins" })
    guard case .estimate(.measured(let bytes)) = finding.size else { Issue.record("Expected a measured size, got \(finding.size)"); return }
    #expect(bytes >= 40_960 + 8192)
    #expect(finding.plugIns?.products.map(\.formats) == [[.vst3, .aax]])
    #expect(finding.plugIns?.summary == "1 product · VST3, AAX")
}

// Real shapes from the #199 printout (#239). Names, bundle IDs and versions are copied; the files are fixtures.
private let components = "Library/Audio/Plug-Ins/Components/", vst = "Library/Audio/Plug-Ins/VST/", vst3s = "Library/Audio/Plug-Ins/VST3/",
            aaxs = "Library/Application Support/Avid/Audio/Plug-Ins/"

@Test func aUADxAudioUnitJoinsItsFormatsThatShareItsBundleID() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    try plugIn(components + "uaudio_polymax.component", in: root, id: "com.uaudio.effects.UI06", version: "1.0.16",
               component: "Universal Audio (UADx): UADx PolyMAX Synth")
    try plugIn(vst3s + "uaudio_polymax.vst3", in: root, id: "com.uaudio.effects.UI06", version: "1.0.16")
    try plugIn(aaxs + "uaudio_polymax.aaxplugin", in: root, id: "com.uaudio.effects.UI06", version: "1.0.16")

    let products = scan(root, home).products
    #expect(products.count == 1)
    let product = try #require(products.first)
    #expect(product.formats == [.au, .vst3, .aax])
    #expect(product.name == "UADx PolyMAX Synth")
    #expect(product.maker == "Universal Audio (UADx)")
    #expect(product.grouping == .bundleID)
}

@Test func aBundleIDSeveralProductsOfOneFormatShareTiesNothing() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    // Philspeiser ships every AAX with this one ID; Avid's AIR plug-ins share "com.wizoo.AIR" the same way.
    try plugIn(aaxs + "THE_YEAR.aaxplugin", in: root, id: "com.myPhilspeiser.product", version: "1.1.0")
    try plugIn(aaxs + "THE_FX.aaxplugin", in: root, id: "com.myPhilspeiser.product", version: "1.0.0")
    try plugIn(vst3s + "THE_FX.vst3", in: root, id: "com.myPhilspeiser.product", version: "1.0.0")
    let products = scan(root, home).products
    #expect(products.map(\.name).sorted() == ["THE_FX", "THE_YEAR"])
    #expect(products.first { $0.name == "THE_FX" }?.formats == [.vst3, .aax])
}

@Test func triggerTwoAndTrigger_2AreOneProduct() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    // As installed: every format carries this (doubled) bundle ID; only the Audio Unit says "Trigger 2" and who made it.
    let id = "com.stevenslate.Trigger_2com.stevenslate.Trigger_2"
    try plugIn(components + "Trigger_2.component", in: root, id: id, version: "2.1.9", component: "Steven Slate: Trigger 2")
    for path in [vst + "Trigger_2.vst", vst3s + "Trigger_2.vst3", aaxs + "Trigger_2.aaxplugin"] { try plugIn(path, in: root, id: id, version: "2.1.9") }

    let products = scan(root, home).products
    #expect(products.count == 1)
    let product = try #require(products.first)
    #expect(product.name == "Trigger 2")
    #expect(product.maker == "Steven Slate")
    #expect(product.formats == [.au, .vst, .vst3, .aax])
    #expect(product.versions == ["2.1.9"])
}

@Test func namesThatDifferOnlyByUnderscoreOrCaseJoinWithinOneMaker() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    // Trigger with a different ID per format and no Audio Unit to name it: joined by maker and name, "_" and case aside.
    try plugIn(vst3s + "Trigger_2.vst3", in: root, id: "com.stevenslate.trigger2.vst3", version: "2.1.9")
    try plugIn(aaxs + "TRIGGER 2.aaxplugin", in: root, id: "com.stevenslate.trigger2.aax", version: "2.1.9")
    let products = scan(root, home).products
    #expect(products.count == 1)
    #expect(products.first?.formats == [.vst3, .aax])
}

@Test func aFabFilterMonoVSTJoinsItsMainProduct() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    // As installed: every format names its Audio Unit "FabFilter: Pro-C 2"; the extra VST2 is "Pro-C 2 (Mono)".
    for (path, id) in [(components + "FabFilter Pro-C 2.component", "com.fabfilter.Pro-C.AU.2"), (vst + "FabFilter Pro-C 2.vst", "com.fabfilter.Pro-C.Vst.2"),
                       (vst3s + "FabFilter Pro-C 2.vst3", "com.fabfilter.Pro-C.Vst3.2"), (aaxs + "FabFilter Pro-C 2.aaxplugin", "com.fabfilter.Pro-C.AAX.2"),
                       ("Library/Audio/Plug-Ins/CLAP/FabFilter Pro-C 2.clap", "com.fabfilter.Pro-C.Clap.2")] {
        try plugIn(path, in: root, id: id, version: "2.20", component: "FabFilter: Pro-C 2")
    }
    try plugIn(vst + "FabFilter Pro-C 2 (Mono).vst", in: root, id: "com.fabfilter.Pro-C.Mono.Vst.2", version: "2.20", component: "FabFilter: Pro-C 2 (Mono)")

    let products = scan(root, home).products
    #expect(products.count == 1)
    let product = try #require(products.first)
    #expect(product.name == "Pro-C 2")
    #expect(product.files.count == 6)
    #expect(product.formats == [.au, .vst, .vst3, .aax, .clap])
}

@Test func aVersionKeepsOnlyItsLeadingNumber() throws {
    let root = try fixtureFolder("Root"), home = try fixtureFolder("Home")
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: home) }
    try plugIn(components + "Crystallizer.component", in: root, id: "com.soundtoys.audiounit.Crystallizer",
               version: "5.5.5.19885 Authorization: Crystallizer", component: "Soundtoys: Crystallizer")
    try plugIn(vst3s + "Reason Rack Plugin.vst3", in: root, id: "se.propellerheads.reasonrackplugin.vst", version: "14.0d381 build 20109")
    try plugIn(aaxs + "NoteStack.aaxplugin", in: root, id: "com.avid.aax.notestack", version: "26.4.1.179 Release")
    try plugIn(aaxs + "Splice INSTRUMENT.aaxplugin", in: root, id: "com.splice.Instrument", version: "1.0.6-921181f")
    let versions = Dictionary(uniqueKeysWithValues: scan(root, home).products.map { ($0.name, $0.versions) })
    #expect(versions["Crystallizer"] == ["5.5.5.19885"])
    #expect(versions["Reason Rack Plugin"] == ["14.0d381"])
    #expect(versions["NoteStack"] == ["26.4.1.179"])
    #expect(versions["Splice INSTRUMENT"] == ["1.0.6-921181f"])
}

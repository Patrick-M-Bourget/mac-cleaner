import Foundation

/// An audio plug-in format CacheDrop inventories (#174).
public enum PlugInFormat: String, Sendable, CaseIterable, Comparable {
    case au = "AU", vst = "VST", vst3 = "VST3", aax = "AAX", clap = "CLAP", auv3 = "AUv3"
    public static func < (a: Self, b: Self) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
    var bundleExtension: String {
        switch self { case .au: "component"; case .vst: "vst"; case .vst3: "vst3"; case .aax: "aaxplugin"; case .clap: "clap"; case .auv3: "appex" }
    }
}

/// One plug-in bundle, read from its Info.plist and its executable's Mach-O header. Its code is never loaded.
public struct PlugInFile: Sendable, Equatable {
    public let url: URL
    public let format: PlugInFormat
    public let bundleID: String?
    /// The bundle's name without its extension, or its Audio Unit's name.
    public let name: String
    public let maker: String?
    public let version: String?
    /// "Apple silicon", "Intel": from the executable's header.
    public let architectures: [String]
    public let size: SizeEstimate
    /// True when `name` is its Audio Unit's display name rather than the bundle's file name.
    var isNamedByAudioUnit = false
    /// Apple's own Audio Units (bundle ID `com.apple.`): never offered for removal.
    public var isApple: Bool { bundleID?.lowercased().hasPrefix("com.apple.") == true }
    /// The name as grouping compares it: case, "_" against " " and a channel suffix ("Pro-C 2 (Mono)") aside.
    var groupingName: String {
        let name = name.replacingOccurrences(of: "_", with: " ").lowercased()
        return name.hasSuffix(" (mono)") ? String(name.dropLast(7)) : name
    }
    /// The bundle ID's first two parts, `com.maker`: who made it, as far as the bundle says.
    var vendor: String? {
        guard let parts = bundleID?.lowercased().split(separator: "."), parts.count > 2 else { return nil }
        return parts.prefix(2).joined(separator: ".")
    }
}

/// The audio plug-ins on this Mac, grouped into products (Decision 42). Read-only: CacheDrop never changes, moves or
/// loads them. Nothing is called unused or a duplicate.
public struct PlugInInventory: Sendable, Equatable {
    public let products: [PlugInProduct]

    /// "12 products · AU, VST3, AAX".
    public var summary: String {
        let formats = Array(Set(products.flatMap(\.formats))).sorted().map(\.rawValue).joined(separator: ", ")
        return (products.count == 1 ? "1 product" : "\(products.count) products") + (formats.isEmpty ? "" : " · " + formats)
    }

    /// The plug-in folders, system ones first. Locations starting with `/` are read under the system root.
    public static let folders: [(format: PlugInFormat, location: String)] = {
        let audio: [(PlugInFormat, String)] = [(.au, "Components"), (.vst, "VST"), (.vst3, "VST3"), (.clap, "CLAP")]
        let user = audio.map { ($0.0, "Library/Audio/Plug-Ins/" + $0.1) }
        return user.map { ($0.0, "/" + $0.1) } + [(.aax, "/Library/Application Support/Avid/Audio/Plug-Ins")] + user
    }()

    /// Finds every plug-in in `folders` and every AUv3 extension in apps in `/Applications` and `~/Applications`.
    /// Folders that don't exist or can't be read are skipped. Reads metadata only.
    /// `receipts` is the scan's one read of the installer receipts (`ReceiptListings.read`, #318).
    public static func scan(home: URL, systemRoot: URL = URL(fileURLWithPath: "/"), sizer: KnownLocationSizer = KnownLocationSizer(),
                            receipts: ReceiptListings) -> PlugInInventory {
        PlugInInventory(products: group(files(home: home, systemRoot: systemRoot, sizer: sizer), receipts: owners(receipts)))
    }

    /// Every plug-in file `scan` finds, ungrouped. Without a sizer, sizes are left unknown, so nothing is walked: for telling
    /// whether a maker's products are installed (#251).
    static func files(home: URL, systemRoot: URL, sizer: KnownLocationSizer?) -> [PlugInFile] {
        func resolve(_ location: String) -> URL {
            location.hasPrefix("/") ? systemRoot.appendingPathComponent(String(location.dropFirst())) : home.appendingPathComponent(location)
        }
        var seen = Set<String>(), files: [PlugInFile] = []
        func add(_ url: URL, _ format: PlugInFormat) {
            guard seen.insert(url.standardizedFileURL.path).inserted, let file = read(url, format, sizer: sizer) else { return }
            files.append(file)
        }
        for (format, location) in folders {
            for url in bundles(in: resolve(location), withExtension: format.bundleExtension) { add(url, format) }
        }
        for apps in [resolve("/Applications"), home.appendingPathComponent("Applications")] {
            for app in bundles(in: apps, withExtension: "app") {
                for appex in bundles(in: app.appendingPathComponent("Contents/PlugIns"), withExtension: "appex", depth: 1) where isAudioExtension(appex) { add(appex, .auv3) }
            }
        }
        return files
    }

    /// Groups files into products (Decision 42): files one installer receipt lists, files in different formats that share
    /// a full bundle ID, then files with the same bundle ID vendor (`com.maker`) and name. A bundle ID two files of one
    /// format share (a maker's template ID) ties nothing, and a receipt that lists two files of one format (a suite) ties
    /// only files with the same name. A file nothing ties stands alone; nothing is guessed from a name alone.
    static func group(_ files: [PlugInFile], receipts: [String: Set<String>]) -> [PlugInProduct] {
        var parent = Array(files.indices)
        func root(_ i: Int) -> Int { parent[i] == i ? i : root(parent[i]) }
        var first: [String: Int] = [:]
        func tie(_ key: String, _ i: Int) { if let j = first[key] { parent[root(i)] = root(j) } else { first[key] = i } }
        let perFormat = Dictionary(grouping: files.compactMap { f in f.bundleID.map { "\($0.lowercased())|\(f.format.rawValue)" } }, by: { $0 })
        // A receipt that lists two files of one format installs several products (a suite, #246): it ties only files
        // with the same name, as the bundle ID rules below tie the rest.
        var listed: [String: [PlugInFormat]] = [:]
        for file in files { for id in receipts[file.url.standardizedFileURL.path] ?? [] { listed[id, default: []].append(file.format) } }
        let suites = Set(listed.filter { Set($0.value).count < $0.value.count }.keys)
        for (i, file) in files.enumerated() {
            for id in receipts[file.url.standardizedFileURL.path] ?? [] { tie(suites.contains(id) ? "receipt|\(id)|\(file.groupingName)" : "receipt|" + id, i) }
            if let id = file.bundleID?.lowercased(), perFormat["\(id)|\(file.format.rawValue)"]?.count == 1 { tie("id|" + id, i) }
            if let vendor = file.vendor { tie("bundle|\(vendor)|\(file.groupingName)", i) }
        }
        let groups = Dictionary(grouping: files.indices, by: root).values
        // Biggest first; an unknown size counts as 0 for ordering only.
        func bytes(_ size: SizeEstimate) -> Int64 {
            switch size { case .measured(let b), .atLeast(let b), .about(let b): b; case .unknown: 0 }
        }
        return groups.map { indices in
            let members = indices.map { files[$0] }
            let installedBy = Set(members.flatMap { receipts[$0.url.standardizedFileURL.path] ?? [] }).sorted()
            return PlugInProduct(files: members, grouping: !installedBy.isEmpty ? .receipt : members.contains { $0.vendor != nil } ? .bundleID : .none,
                                 receipts: installedBy)
        }.sorted { (bytes($0.size), $1.name) > (bytes($1.size), $0.name) }
    }

    /// The receipts that list each plug-in bundle path. Receipts that can't be read are left out, so their files stand alone
    /// or group by bundle ID.
    static func owners(_ receipts: ReceiptListings) -> [String: Set<String>] {
        let extensions = Set(PlugInFormat.allCases.filter { $0 != .auv3 }.map(\.bundleExtension))
        return receipts.byPath.filter { extensions.contains(URL(fileURLWithPath: $0.key).pathExtension.lowercased()) }
    }

    /// Bundles with `ext` in `folder`, also inside vendor subfolders, never inside a bundle.
    static func bundles(in folder: URL, withExtension ext: String, depth: Int = 3) -> [URL] {
        // Names are appended to `folder`, so paths keep the caller's spelling (`/var` and `/private/var` differ as strings).
        guard depth > 0, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.sorted().flatMap { name -> [URL] in
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return [] }
            if url.pathExtension.lowercased() == ext { return [url] }
            return url.pathExtension.isEmpty ? bundles(in: url, withExtension: ext, depth: depth - 1) : []
        }
    }

    static func info(_ bundle: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    static func isAudioExtension(_ appex: URL) -> Bool {
        let point = (info(appex)?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        return point == "com.apple.AudioUnit" || point == "com.apple.AudioUnit-UI"
    }

    static func read(_ url: URL, _ format: PlugInFormat, sizer: KnownLocationSizer?) -> PlugInFile? {
        let info = info(url) ?? [:]
        let attributes = (info["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any]
        let components = (attributes?["AudioComponents"] ?? info["AudioComponents"]) as? [[String: Any]]
        // An Audio Unit is named "Maker: Name".
        let component = (components?.first?["name"] as? String)?.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let maker = component.flatMap { $0.count == 2 ? $0[0] : nil } ?? vst3Vendor(url) ?? (format == .aax ? copyrightHolder(info) : nil)
        let name = component.flatMap { $0.count == 2 ? $0[1] : nil } ?? url.deletingPathExtension().lastPathComponent
        let executable = (info["CFBundleExecutable"] as? String).map { url.appendingPathComponent("Contents/MacOS/" + $0) }
        return PlugInFile(url: url, format: format, bundleID: info["CFBundleIdentifier"] as? String, name: name, maker: maker,
                          version: leadingVersion((info["CFBundleShortVersionString"] ?? info["CFBundleVersion"]) as? String),
                          architectures: executable.map(MachOArchitectures.read) ?? [], size: sizer.map { Catalog.estimate($0.size(url)) } ?? .unknown,
                          isNamedByAudioUnit: component?.count == 2)
    }

    /// Who an AAX bundle's copyright line names: "©2000-2026 Propellerhead Software AB, all rights reserved." reads
    /// "Propellerhead Software AB". Nil without a copyright line, or when it names a template's placeholder.
    static func copyrightHolder(_ info: [String: Any]) -> String? {
        for key in ["NSHumanReadableCopyright", "CFBundleGetInfoString"] {
            guard let line = info[key] as? String,
                  let mark = line.range(of: #"copyright|©|\(c\)"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            var holder = String(line[mark.lowerBound...])
            if let end = holder.range(of: #"[.,;]?\s*all rights reserved.*$"#, options: [.regularExpression, .caseInsensitive]) {
                holder.removeSubrange(end)
            }
            // Strip the marks and years in front: "Copyright © 1991-2026 ".
            holder = holder.replacingOccurrences(of: #"^(\s|,|copyright|©|\(c\)|\d{4}(\s*[-–]\s*\d{4})?)+"#, with: "",
                                                 options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
            let placeholders: Set = ["company", "my company", "your company", "yourcompany"]
            guard holder.contains(where: \.isLetter), !placeholders.contains(holder.lowercased()) else { return nil }
            return holder
        }
        return nil
    }

    /// A version's leading number: "5.5.5.19885 Authorization: Crystallizer" reads "5.5.5.19885". A version that
    /// doesn't start with a digit is kept as it is.
    static func leadingVersion(_ version: String?) -> String? {
        guard let version = version?.trimmingCharacters(in: .whitespaces), !version.isEmpty else { return nil }
        guard version.first?.isNumber == true, let token = version.split(whereSeparator: \.isWhitespace).first else { return version }
        return String(token).trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
    }

    /// A VST3's vendor, from its `moduleinfo.json` (VST 3.7 SDK) when it ships one.
    static func vst3Vendor(_ url: URL) -> String? {
        guard url.pathExtension == "vst3", let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Resources/moduleinfo.json")),
              let json = try? JSONSerialization.jsonObject(with: data, options: .json5Allowed) as? [String: Any] else { return nil }
        return (json["Factory Info"] as? [String: Any])?["Vendor"] as? String
    }
}

/// The CPU types in a Mach-O header, thin or universal. Reads the first bytes of the file only.
enum MachOArchitectures {
    static func read(_ executable: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), data.count >= 8 else { return [] }
        let bytes = [UInt8](data)
        func big(_ at: Int) -> UInt32 { at + 4 <= bytes.count ? bytes[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) } : 0 }
        func little(_ at: Int) -> UInt32 { big(at).byteSwapped }
        let cpus: [UInt32]
        switch big(0) {
        case 0xcafe_babe, 0xcafe_babf:
            let stride = big(0) == 0xcafe_babe ? 20 : 32
            cpus = (0..<Int(min(big(4), 16))).map { big(8 + $0 * stride) }
        case 0xcffa_edfe, 0xcefa_edfe: cpus = [little(4)]
        default: cpus = []
        }
        var names: [String] = []
        for cpu in cpus {
            let name: String? = switch cpu { case 0x0100_000c: "Apple silicon"; case 0x0100_0007, 7: "Intel"; default: nil }
            if let name, !names.contains(name) { names.append(name) }
        }
        return names
    }
}

/// Plug-in files that belong together: one installer receipt, or one bundle ID vendor and name, ties them.
public struct PlugInProduct: Sendable, Equatable, Identifiable {
    /// What tied the files: an installer receipt, a bundle ID, or nothing (a file on its own).
    public enum Grouping: Sendable, Equatable { case receipt, bundleID, none }
    public let files: [PlugInFile]
    public let grouping: Grouping
    /// The installer receipts (package IDs) that list any of its files, for uninstalling it later (#176).
    public let receipts: [String]
    public var id: String { files.map(\.url.path).min() ?? "" }
    init(files: [PlugInFile], grouping: Grouping, receipts: [String] = []) {
        self.files = files.sorted { ($0.format, $0.url.path) < ($1.format, $1.url.path) }; self.grouping = grouping
        self.receipts = receipts
    }
    /// The most common name among its files, preferring an Audio Unit's display name to bundle file names.
    public var name: String {
        let named = files.filter(\.isNamedByAudioUnit)
        let counts = Dictionary(grouping: (named.isEmpty ? files : named).map(\.name), by: { $0 }).mapValues(\.count)
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? ""
    }
    public var maker: String? { files.lazy.compactMap(\.maker).first }
    public var formats: [PlugInFormat] { Array(Set(files.map(\.format))).sorted() }
    public var versions: [String] { Self.unique(files.compactMap(\.version)) }
    public var architectures: [String] { Self.unique(files.flatMap(\.architectures)) }
    public var size: SizeEstimate { SizeEstimate(sum: files.map(\.size)) }
    /// Apple's own plug-ins are never offered for removal.
    public var isApple: Bool { files.allSatisfy(\.isApple) }
    private static func unique(_ values: [String]) -> [String] { values.reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
}


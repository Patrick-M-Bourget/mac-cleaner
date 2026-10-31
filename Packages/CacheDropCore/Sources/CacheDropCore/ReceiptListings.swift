import Foundation

/// Every non-Apple installer receipt's listed paths, read once (#291): what each receipt lists, and which receipts list each
/// path. A plug-in support item is a product's own only while no other receipt, plug-in or not, lists it or anything in it.
public struct ReceiptListings: Sendable {
    /// Each receipt's listed paths, absolute.
    public let byReceipt: [String: Set<String>]
    let byPath: [String: Set<String>]
    /// Installer records that couldn't be read (#291): while there is any, no support item is offered or moved, since an
    /// unread record is never "lists nothing".
    public let unread: [String]
    /// The same validated listings, in receipt order: what leftovers and app uninstall read (#318).
    let listed: [Listed]
    /// One receipt as `lsbom` listed it.
    struct Listed: Sendable { let id: String; let paths: Set<String> }
    public init(_ byReceipt: [String: Set<String>], unread: [String] = []) {
        self.init(byReceipt, unread: unread, listed: byReceipt.sorted { $0.key < $1.key }.map { Listed(id: $0.key, paths: $0.value) })
    }
    init(_ byReceipt: [String: Set<String>], unread: [String], listed: [Listed]) {
        self.byReceipt = byReceipt; self.unread = unread; self.listed = listed
        var byPath: [String: Set<String>] = [:]
        for (id, paths) in byReceipt { for path in paths { byPath[path, default: []].insert(id) } }
        self.byPath = byPath
    }

    /// The receipts that list `path` or anything on disk inside it; nil when there is too much inside to look at.
    func listers(of path: String, limit: Int = 20_000) -> Set<String>? {
        var found = byPath[path] ?? []
        // An unreadable folder anywhere in it may hold what another receipt lists (#291).
        let ending = FileTree.entries(below: path, limit: limit) { entry, _ in found.formUnion(byPath[entry] ?? []); return false }
        return ending == .finished ? found : nil
    }

    /// Every non-Apple receipt in `<systemRoot>/var/db/receipts`, listed with `lsbom` once each (#318). Absolute, empty and
    /// relative prefixes all name paths under this known system root (#329), never a guessed home or relocated folder.
    /// Unreadable, oversized, timed-out or malformed listings remain `unread` (#291).
    public static func read(under systemRoot: URL) -> ReceiptListings { read(under: systemRoot, lsbom: lsbom) }
    /// `read(under:)` with `lsbom` standing in for the tool in tests: it gets the BOM and returns what `lsbom -s` prints,
    /// nil when it fails.
    static func read(under systemRoot: URL, lsbom: (URL) -> String?) -> ReceiptListings {
        let folder = systemRoot.appendingPathComponent("var/db/receipts")
        var found: [String: Set<String>] = [:], unread: [String] = [], listed: [Listed] = []
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return ReceiptListings([:], unread: [folder.path])
        }
        for name in names.sorted() where name.hasSuffix(".plist") && !name.hasPrefix("com.apple.") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = info["PackageIdentifier"] as? String, let prefix = info["InstallPrefixPath"] as? String,
                  let listing = lsbom(folder.appendingPathComponent(String(name.dropLast(6)) + ".bom")),
                  let paths = resolvedPaths(prefix: prefix, listing: listing, under: systemRoot) else { unread.append(name); continue }
            listed.append(Listed(id: id, paths: paths))
            found[id] = paths
        }
        return ReceiptListings(found, unread: unread, listed: listed)
    }
    /// A receipt is usable only as a whole: dropping an unsafe entry could hide another installer's shared files.
    private static func resolvedPaths(prefix: String, listing: String, under systemRoot: URL) -> Set<String>? {
        func relative(_ path: Substring) -> Bool {
            path.first != "/" && !path.utf8.contains(0) && !path.split(separator: "/").contains("..")
        }
        let prefix = prefix.drop { $0 == "/" }, lines = listing.split(separator: "\n")
        guard relative(prefix), !lines.isEmpty else { return nil }
        let base = systemRoot.appendingPathComponent(String(prefix))
        var paths: Set<String> = []
        for line in lines {
            // lsbom can exit 0 with only an error message; real paths are `.` or `./…` (#291).
            guard line == "." || line.hasPrefix("./") else { return nil }
            let entry = line == "." ? Substring() : line.dropFirst(2)
            guard relative(entry) else { return nil }
            paths.insert(base.appendingPathComponent(String(entry)).standardizedFileURL.path)
        }
        return paths
    }

    /// `lsbom -s` on a BOM, nil when it fails, takes over 20 seconds or prints more than 64 MB.
    static func lsbom(_ bom: URL) -> String? {
        try? BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/lsbom"), arguments: ["-s", bom.path], timeout: 20, outputLimit: 64 << 20)
    }
}

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
    /// Every receipt `lsbom` listed, by receipt name, relative install prefixes included (read under the system root):
    /// what leftovers and app uninstall read (#318). `byReceipt` leaves those prefixes out.
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

    /// Every non-Apple receipt in `<systemRoot>/var/db/receipts`, listed with `lsbom` once each (#318). One that can't be read, or
    /// lists more than 64 MB or takes over 20 seconds, is `unread`, as is one with a relative install prefix (#291).
    public static func read(under systemRoot: URL) -> ReceiptListings { read(under: systemRoot, lsbom: lsbom) }
    /// `read(under:)` with `lsbom` standing in for the tool in tests: it gets the BOM and returns what `lsbom -s` prints,
    /// nil when it fails.
    static func read(under systemRoot: URL, lsbom: (URL) -> String?) -> ReceiptListings {
        let folder = systemRoot.appendingPathComponent("var/db/receipts")
        var found: [String: Set<String>] = [:], unread: [String] = [], listed: [Listed] = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where name.hasSuffix(".plist") && !name.hasPrefix("com.apple.") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = info["PackageIdentifier"] as? String, let prefix = info["InstallPrefixPath"] as? String,
                  let listing = lsbom(folder.appendingPathComponent(String(name.dropLast(6)) + ".bom")),
                  // lsbom exits 0 when it can't read a BOM, with only its complaint; a real one lists `.` and paths under it (#291).
                  case let lines = listing.split(separator: "\n"), !lines.isEmpty, lines.allSatisfy({ $0.hasPrefix(".") }) else { unread.append(name); continue }
            let base = systemRoot.appendingPathComponent(String(prefix.drop { $0 == "/" }))
            let paths = Set(lines.map { line in
                base.appendingPathComponent(line.hasPrefix("./") ? String(line.dropFirst(2)) : String(line)).standardizedFileURL.path
            })
            listed.append(Listed(id: id, paths: paths))
            if prefix.hasPrefix("/") || prefix.isEmpty { found[id] = paths } else { unread.append(name) }
        }
        return ReceiptListings(found, unread: unread, listed: listed)
    }
    /// `lsbom -s` on a BOM, nil when it fails, takes over 20 seconds or prints more than 64 MB.
    static func lsbom(_ bom: URL) -> String? {
        try? BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/lsbom"), arguments: ["-s", bom.path], timeout: 20, outputLimit: 64 << 20)
    }
}

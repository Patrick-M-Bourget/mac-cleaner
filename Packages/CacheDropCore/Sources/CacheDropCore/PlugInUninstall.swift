import Foundation
import Darwin

/// Uninstalling a plug-in product as a whole (#176, Decisions 42, 50, 51): every format of it, plus the support files its own
/// installer receipt lists. Items a suite receipt lists for several products, and vendor content (Decision 52), are shared:
/// listed under each product that shares them, ticked one by one only and counted once. Only what macOS lets the user move to
/// the Trash without a password is offered, checked at the scan and again before acting. It goes through `AppUninstall`'s
/// path: its `Target`, review lines, History and Put back.
public enum PlugInUninstall {
    public static let formatsRuleID = "uninstall-plugin"
    public static let filesRuleID = "uninstall-plugin-files"
    public static let sharedRuleID = "uninstall-plugin-shared"
    public static let rules: [CleanupRule] = [
        CleanupRule(id: formatsRuleID, category: .apps, title: "Formats", detail: "The product's plug-in formats.", consequence: AppUninstall.consequence,
                    regen: .userFile, action: .trash, locations: [], owner: nil),
        CleanupRule(id: filesRuleID, category: .apps, title: "Its support files", detail: "Presets and support files its own installer lists.",
                    consequence: AppUninstall.consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth),
        CleanupRule(id: sharedRuleID, category: .apps, title: "Shared with other products",
                    detail: "Suite support files and content.",
                    consequence: AppUninstall.consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth,
                    itemByItem: true),
    ]

    /// Plug-in hosts that must be closed first (Decision 51, a curated list). Bundle IDs checked on this Mac: Ableton Live
    /// (`com.ableton.live`) and Pro Tools (`com.avid.ProTools`); the rest are their makers' published IDs, and every host is
    /// also matched by its executable's name.
    public static let hosts: [RuleOwner] = [
        RuleOwner(name: "Logic Pro", bundleIDs: ["com.apple.logic10"], executables: ["Logic Pro*"]),
        RuleOwner(name: "GarageBand", bundleIDs: ["com.apple.garageband10"], executables: ["GarageBand"]),
        RuleOwner(name: "MainStage", bundleIDs: ["com.apple.mainstage3"], executables: ["MainStage*"]),
        RuleOwner(name: "Ableton Live", bundleIDs: ["com.ableton.live"], executables: ["Live"]),
        RuleOwner(name: "Reason", bundleIDs: ["com.reasonstudios.reason", "com.propellerheads.reason"], executables: ["Reason", "Reason [0-9]*"]),
        RuleOwner(name: "Pro Tools", bundleIDs: ["com.avid.ProTools"], executables: ["Pro Tools"]),
        RuleOwner(name: "Cubase", executables: ["Cubase*"]),
        RuleOwner(name: "Studio One", executables: ["Studio One*"]),
        RuleOwner(name: "Bitwig Studio", bundleIDs: ["com.bitwig.BitwigStudio"], executables: ["Bitwig*"]),
        RuleOwner(name: "FL Studio", bundleIDs: ["com.image-line.flstudio"], executables: ["FL Studio*"]),
        RuleOwner(name: "REAPER", bundleIDs: ["com.cockos.reaper"], executables: ["REAPER", "reaper"]),
    ]

    /// Where a receipt's support files may be: anything else it lists (the system, launch daemons, apps) is never offered.
    static let supportPlaces = ["Library/Application Support/", "Library/Audio/Presets/", "Library/Preferences/"]
    /// Apple's folders (Decision 41): its loops and the Logic library, never offered even when a receipt lists them.
    static let appleFolders: Set<String> = ["apple", "logic", "garageband", "mainstage", "apple loops", "logic pro library.bundle"]

    /// Every product's items, ready to tick. `receipts` is every installer receipt's listing (`ReceiptListings.read`); `content`
    /// the vendor content tied to products (`MusicContent`, by product ID). What `offered` already holds stays there.
    public static func scan(_ inventory: PlugInInventory, apps: [InstalledApp], receipts: ReceiptListings, content: [MusicContentItem] = [],
                            systemRoot: URL, offered: [Candidate] = [], exclusions: ExclusionPolicy = ExclusionPolicy(),
                            sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        let products = inventory.products.filter { !$0.isApple }
        let catalog = Catalog(rules: rules)
        // Every product whose receipts list a path, or anything in it, shares it (#288); so does any other receipt, one that
        // installs no plug-in included (#291). Nil: too much in it to tell.
        func sharers(_ path: String) -> [String]? {
            guard let listers = receipts.listers(of: path) else { return nil }
            let owned = products.filter { !listers.isDisjoint(with: $0.receipts) }
            let others = listers.subtracting(owned.flatMap(\.receipts)).sorted().map { "receipt:" + $0 }
            return owned.map(\.id) + others
        }
        var shared: [String: Candidate] = [:], items: [Candidate] = []
        func item(_ rule: CleanupRule, _ url: URL) -> Candidate? {
            var info = stat()
            guard lstat(url.path, &info) == 0, [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT), !isNeverTouched(url, below: systemRoot),
                  let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(url, volumeID: volume) else { return nil }
            let size = sizer.size(url)
            return catalog.candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
                .found(under: url.deletingLastPathComponent())
        }
        let taken = RemovedAppLeftovers.notOffered
        let productNames = Set(products.map { RemovedAppLeftovers.token($0.name) }.filter { !$0.isEmpty })
        var targets: [String: AppUninstall.Target] = [:]
        let appEntries = apps.map { InventoryEntry(id: $0.path, name: $0.name, maker: $0.maker, volume: nil, parts: [], bundleID: $0.bundleID) }
        for product in products {
            let bundleID = product.files.lazy.compactMap(\.bundleID).first ?? ""
            let standalone = ownApp(of: product, among: apps)
            // The vendor's tool, from the one lookup the Applications page uses (#288).
            let tool = ApplicationsInventory.vendorTool(for: InventoryEntry(id: product.id, name: product.name, maker: nil, volume: nil, parts: [], bundleID: bundleID),
                                                        among: appEntries)
            var target = AppUninstall.Target(name: product.name, bundleID: standalone?.bundleID ?? bundleID, path: product.id,
                                             helpers: standalone.map { AppUninstall.helperIDs(of: URL(fileURLWithPath: $0.path)) } ?? [])
            target.otherPaths = product.files.map(\.url.path) + (standalone.map { [$0.path] } ?? [])
            target.hosts = hosts; target.tool = tool?.name
            targets[product.id] = target
        }
        /// A shared item waits for every sharer (#288): the first's target, with each other sharer's own app as a host.
        func sharedTarget(_ ids: [String]) -> AppUninstall.Target? {
            guard var target = ids.lazy.compactMap({ targets[$0] }).first else { return nil }
            target.hosts += ids.compactMap { targets[$0] }.filter { $0.path != target.path }.map(\.owner)
            return target
        }
        for product in products {
            guard var target = targets[product.id] else { continue }
            var own: [Candidate] = []
            for file in product.files {
                // An AUv3 lives inside its app and goes with it.
                if file.format == .auv3 { target.insideApp += 1; continue }
                guard var format = item(rules[0], file.url) else { continue }
                guard Removability.canMoveToTrash(file.url) else { target.needsPassword += 1; continue }
                format.leftover = LeftoverTie(app: product.name, bundleID: file.bundleID, vendor: RemovedAppLeftovers.vendor(of: file.bundleID ?? ""), evidence: .bundleID)
                own.append(format)
            }
            for receipt in product.receipts {
                let listed = receipts.byReceipt[receipt] ?? []
                for url in supportRoots(listed, systemRoot: systemRoot, receipts: receipts, products: productNames) {
                    guard let listers = receipts.listers(of: url.path), let ids = sharers(url.path) else { continue }
                    if ids.count > 1 { if shared[url.path] == nil, let found = item(rules[2], url) { shared[url.path] = found.shared(by: ids, receipt: receipt).installed(by: listers) }; continue }
                    guard var file = item(rules[1], url).map({ $0.installed(by: listers) }) else { continue }
                    guard taken(offered, [file]).count == 1 else { target.inPlan += 1; continue }
                    guard Removability.canMoveToTrash(url) else { target.needsPassword += 1; target.passwordPaths.append(url.path); continue }
                    file.leftover = LeftoverTie(app: product.name, bundleID: nil, vendor: RemovedAppLeftovers.vendor(of: receipt), evidence: .receipt(receipt))
                    own.append(file)
                }
            }
            targets[product.id] = target
            items += own.map { var item = $0; item.uninstall = target; return item }
        }
        for (key, item) in shared { shared[key]?.uninstall = sharedTarget(item.sharedBy) }
        for piece in content where piece.kind == .installed {
            let ids = piece.owners.filter { id in products.contains { $0.id == id } }
            guard shared[piece.url.path] == nil, let target = sharedTarget(ids), var found = item(rules[2], piece.url) else { continue }
            found = found.shared(by: ids, receipt: nil, vendor: piece.vendors.first); found.uninstall = target
            shared[piece.url.path] = found
        }
        let sharedItems = taken(offered + items, shared.values.sorted { $0.url.path < $1.url.path }).filter { Removability.canMoveToTrash($0.url) && $0.uninstall != nil }
        return items + sharedItems
    }

    /// The product's own standalone app: one of its vendor named like it, or the app an AUv3 of it is in.
    static func ownApp(of product: PlugInProduct, among apps: [InstalledApp]) -> InstalledApp? {
        let vendors = Set(product.files.compactMap(\.vendor)), name = RemovedAppLeftovers.token(product.name)
        let containers = product.files.filter { $0.format == .auv3 }.map { $0.url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path }
        return apps.first { containers.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path) }
            ?? apps.first { vendors.contains(RemovedAppLeftovers.vendor(of: $0.bundleID)) && RemovedAppLeftovers.token($0.name) == name }
    }

    /// The items a receipt installed whole: the shallowest listed paths in a support place whose every entry on disk the
    /// receipt lists, so a maker's folder that other products also fill is never taken, only this product's folder in it.
    static func supportRoots(_ listed: Set<String>, systemRoot: URL, receipts: ReceiptListings = ReceiptListings([:]), products: Set<String> = []) -> [URL] {
        let base = systemRoot.standardizedFileURL.path.hasSuffix("/") ? systemRoot.standardizedFileURL.path : systemRoot.standardizedFileURL.path + "/"
        var roots: [String] = []
        for path in listed.sorted(by: { ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1) }) {
            guard path.hasPrefix(base), !roots.contains(where: { path.hasPrefix($0 + "/") }) else { continue }
            let relative = String(path.dropFirst(base.count))
            guard let place = supportPlaces.first(where: relative.hasPrefix), relative.count > place.count, !touchesPlugIns(path, listed, systemRoot: systemRoot),
                  isWhollyListed(path, listed), !holdsOthers(path, receipts: receipts, products: products) else { continue }
            roots.append(path)
        }
        return roots.map { URL(fileURLWithPath: $0) }
    }
    /// Plug-ins are formats, never support files (#288): a path that is or is in a plug-in bundle or a plug-in folder (AAX's is
    /// in Application Support), or that holds either, is never a support root.
    static func touchesPlugIns(_ path: String, _ listed: Set<String>, systemRoot: URL) -> Bool {
        let extensions = Set(PlugInFormat.allCases.map(\.bundleExtension))
        if path.split(separator: "/").contains(where: { extensions.contains((String($0) as NSString).pathExtension.lowercased()) }) { return true }
        let folders = PlugInInventory.folders.filter { $0.location.hasPrefix("/") }.map { systemRoot.appendingPathComponent(String($0.location.dropFirst())).standardizedFileURL.path }
        if folders.contains(where: { $0 == path || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) { return true }
        return listed.contains { $0.hasPrefix(path + "/") && extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
    }
    /// The narrowest roots (#291): never a folder holding things different receipts installed (each product's folder in a
    /// maker's), nor one holding a folder named for a product (a suite's `Vendor/ProductA`); its folders are offered instead.
    static func holdsOthers(_ path: String, receipts: ReceiptListings, products: Set<String>) -> Bool {
        guard let walk = FileManager.default.enumerator(atPath: path) else { return false }
        var installers: Set<Set<String>> = []
        while let relative = walk.nextObject() as? String {
            if relative.split(separator: "/").contains(where: { products.contains(RemovedAppLeftovers.token(String($0))) }) { return true }
            if let listers = receipts.byPath[path + "/" + relative] { installers.insert(listers) }
            if installers.count > 1 { return true }
        }
        return false
    }
    static func isWhollyListed(_ path: String, _ listed: Set<String>) -> Bool { listed.contains(path) && listingRefusal(path, listed) == nil }
    /// Why a support item may not be moved as its receipt installed it (#288): it holds license data (refused by name), or an
    /// entry the receipt doesn't list, which may be the user's or another product's (or more than `limit` to look at).
    static func listingRefusal(_ path: String, _ listed: Set<String>, limit: Int = 20_000) -> CheckRefusal? {
        if let name = licenceData(path) { return .protected(name) }
        guard let walk = FileManager.default.enumerator(atPath: path) else { return nil }
        var seen = 0
        while let relative = walk.nextObject() as? String {
            seen += 1
            if let name = licenceData(path + "/" + relative) { return .protected(name) }
            if seen > limit || !listed.contains(path + "/" + relative) { return .changed }
        }
        return nil
    }

    /// Licence and activation data, by name or by content (#291): a licence word in its name, a `.lic` or `.key` file, an
    /// opaque data file (`.dat`, `.bin`, or a file with no extension), or a preference list with licence-like keys. Its name, or nil.
    static func licenceData(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path), name = url.lastPathComponent, kind = url.pathExtension.lowercased()
        if RemovedAppLeftovers.isNeverOffered(name) { return name }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT != S_IFDIR else { return nil }
        if ["lic", "key", "dat", "bin", ""].contains(kind) { return name }
        guard kind == "plist", let data = try? Data(contentsOf: url),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return hasLicenceKeys(list) ? name : nil
    }
    /// Keys such as SerialNumber, LicenseKey, ActivationCode, Registration, AuthToken or UserKey, at any depth.
    static func hasLicenceKeys(_ list: Any, depth: Int = 0) -> Bool {
        guard depth < 8 else { return true }
        if let array = list as? [Any] { return array.contains { hasLicenceKeys($0, depth: depth + 1) } }
        guard let dictionary = list as? [String: Any] else { return false }
        return dictionary.contains { key, value in
            key.range(of: #"serial|licen[cs]|activat|registr|auth|(user|email|account).*key"#, options: [.regularExpression, .caseInsensitive]) != nil
                || hasLicenceKeys(value, depth: depth + 1)
        }
    }

    /// Never offered or acted on: license and macOS data and Apple's folders anywhere on the path below the system root, and
    /// anything that is or holds an app or plug-in other than the item itself.
    static func isNeverTouched(_ url: URL, below systemRoot: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents.dropFirst(systemRoot.standardizedFileURL.pathComponents.count)
        return parts.contains { RemovedAppLeftovers.isNeverOffered($0) || appleFolders.contains($0.lowercased()) }
            || parts.dropLast().contains { $0.lowercased().hasSuffix(".app") }
    }

    /// The check just before acting (Decision 50): never license, macOS or Apple data by its name (its folders were checked at
    /// the scan, and the item can't leave them and keep its path); a format is still the bundle the scan tied to the product;
    /// and macOS still lets the user move it to the Trash without a password.
    static func refusal(for candidate: Candidate, receipts: LazyReceipts) -> CheckRefusal? {
        let url = candidate.url
        if isNeverTouched(url, below: url.deletingLastPathComponent()) { return .protected(url.lastPathComponent) }
        if candidate.ruleID == formatsRuleID {
            guard let tie = candidate.leftover, PlugInInventory.info(url)?["CFBundleIdentifier"] as? String == tie.bundleID else { return .changed }
        }
        // A support item: with the receipts read again, no other receipt lists it or anything in it, and they still list all of
        // it (#288, #291).
        if let allowed = candidate.installedBy {
            let now = receipts.value
            guard let listers = now.listers(of: url.path), listers.isSubset(of: allowed) else { return .changed }
            let listed = Set(allowed.flatMap { now.byReceipt[$0] ?? [] })
            guard listed.contains(url.path) else { return .changed }
            if let refusal = listingRefusal(url.path, listed) { return refusal }
        }
        return Removability.canMoveToTrash(url) ? nil : .notPermitted
    }
}

extension Candidate {
    /// A shared item, under every product in `products` ("Shared with <N> products").
    func shared(by products: [String], receipt: String?, vendor: String? = nil) -> Candidate {
        var item = self
        item.sharedBy = products
        item.leftover = LeftoverTie(app: vendor ?? "", bundleID: nil, vendor: receipt.map(RemovedAppLeftovers.vendor(of:)) ?? "", evidence: receipt.map { .receipt($0) } ?? .bundleID)
        return item
    }
    /// With the receipts that list it, to read again before acting (#291).
    func installed(by receipts: Set<String>) -> Candidate {
        var item = self
        item.installedBy = receipts
        return item
    }
    /// "Shared with <N> products", or vendor content's "Shared by <Vendor> products" (Decision 52); nil when not shared.
    public var sharedLabel: String? {
        guard !sharedBy.isEmpty else { return nil }
        if let vendor = leftover?.app, !vendor.isEmpty { return "Shared by \(vendor) products" }
        // Another receipt that installs no plug-in (a vendor's content or app pkg) shares it too (#291).
        let products = sharedBy.filter { !$0.hasPrefix("receipt:") }.count, others = sharedBy.count - products
        if others == 0 { return "Shared with \(products) products" }
        return products > 1 ? "Shared with \(products) products and another installer" : "Shared with another installer"
    }
    /// Whether it is uninstalled with the app or product whose row is `id`: its own, or one it is shared with.
    public func isUninstalled(with id: String) -> Bool { uninstall?.path == id || sharedBy.contains(id) }
}

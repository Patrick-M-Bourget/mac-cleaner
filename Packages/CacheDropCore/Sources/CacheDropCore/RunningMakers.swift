import AppKit
import Foundation

/// A running process (#240): its executable, its bundle ID when it is an app macOS lists as one, and its command line (argv)
/// when the current user owns it and it can be read (#261).
public struct RunningProcess: Sendable, Hashable {
    public let path: String
    public let bundleID: String?
    public let arguments: [String]?
    public init(path: String, bundleID: String? = nil, arguments: [String]? = nil) { self.path = path; self.bundleID = bundleID; self.arguments = arguments }
}

/// Lists the running processes. Injected so tests list fixture processes, never this Mac's.
public protocol ProcessListing: Sendable {
    /// Every running process whose executable can be read; nil when the list can't be read.
    func processes() -> [RunningProcess]?
}

/// The running apps and every process whose executable can be read, background helpers and daemons included.
public struct SystemProcessListing: ProcessListing {
    public init() {}
    public func processes() -> [RunningProcess]? {
        guard let pids = UserProcesses.allPids() else { return nil }
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningProcess? in
            (app.executableURL ?? app.bundleURL).map { RunningProcess(path: $0.path, bundleID: app.bundleIdentifier) }
        }
        let uid = getuid()
        return apps + pids.compactMap { pid in
            UserProcesses.executablePath(pid).map { RunningProcess(path: $0, arguments: UserProcesses.owner(pid) == uid ? UserProcesses.arguments(pid) : nil) }
        }
    }
}

/// The makers of what is running (#240), by #251's maker-wide rules: a process belongs to the maker of every bundle it runs
/// from, by bundle ID or by the maker its bundle names, and to the maker a folder in `Application Support` is named for.
struct RunningMakers {
    let products: [InstalledApp]
    let makers: InstalledMakers

    init(_ processes: [RunningProcess], resolve: (RunningProcess) -> [InstalledApp] = Self.products) {
        products = Set(processes).flatMap(resolve)
        makers = InstalledMakers(products)
    }

    /// Whether anything of an owner's makers (`bundleIDPrefixes`) is running.
    func runs(_ owner: RuleOwner) -> Bool {
        owner.bundleIDPrefixes.contains { prefix in
            products.contains { !$0.bundleID.isEmpty && ($0.bundleID.lowercased() + ".").hasPrefix(prefix) } || makers.makes(String(prefix.dropLast()))
        }
    }

    /// What a process says about its maker: its app's ID, each bundle it runs from, an embedded Info.plist or a file named
    /// by bundle ID, and the folder it sits in under `Application Support`. macOS's own and CacheDrop's bundles say nothing.
    static func products(_ process: RunningProcess) -> [InstalledApp] {
        let executable = URL(fileURLWithPath: process.path)
        var found: [InstalledApp] = process.bundleID.map { [InstalledApp(name: "", bundleID: $0, path: process.path)] } ?? []
        var folder = executable.deletingLastPathComponent()
        var bundles: [URL] = []
        while folder.pathComponents.count > 1 {
            if bundleExtensions.contains(folder.pathExtension.lowercased()) { bundles.append(folder) }
            folder = folder.deletingLastPathComponent()
        }
        found += bundles.compactMap { url in
            guard let info = PlugInInventory.info(url), let id = info["CFBundleIdentifier"] as? String else { return nil }
            return InstalledApp(name: url.deletingPathExtension().lastPathComponent, bundleID: id, path: url.path, maker: PlugInInventory.copyrightHolder(info))
        }
        if bundles.isEmpty {
            if let info = CFBundleCopyInfoDictionaryForURL(executable as CFURL) as? [String: Any], let id = info["CFBundleIdentifier"] as? String {
                found.append(InstalledApp(name: executable.lastPathComponent, bundleID: id, path: process.path, maker: PlugInInventory.copyrightHolder(info)))
            } else if AppCaches.isBundleID(executable.lastPathComponent) {
                found.append(InstalledApp(name: "", bundleID: executable.lastPathComponent, path: process.path))
            }
        }
        let parts = executable.pathComponents
        if let index = parts.firstIndex(of: "Application Support"), index + 2 < parts.count, parts[index + 1].lowercased() != "apple" {
            found.append(InstalledApp(name: parts[index + 1], bundleID: "", path: process.path, maker: parts[index + 1]))
        }
        // A process of macOS or CacheDrop names no maker, whatever folder it runs from.
        if found.contains(where: { !$0.bundleID.isEmpty && AppCaches.isMacOSOrOwn($0.bundleID) }) { return [] }
        return found
    }
    static let bundleExtensions = InstalledBundles.extensions.union(PlugInFormat.allCases.map(\.bundleExtension))
}

/// Each process's maker products read once per executable: a bundle on disk doesn't change maker while CacheDrop checks.
final class RunningMakerCache: @unchecked Sendable {
    private let lock = NSLock()
    private var products: [RunningProcess: [InstalledApp]] = [:]
    func products(_ process: RunningProcess) -> [InstalledApp] {
        lock.lock(); defer { lock.unlock() }
        if let known = products[process] { return known }
        let found = RunningMakers.products(process)
        products[process] = found
        return found
    }
}

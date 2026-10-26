import Foundation
import Darwin
import CryptoKit
import Security

public struct ChromeCacheAccess: Sendable {
    public let applicationURL: URL
    public let dataRootURL: URL
    public let cacheRootURL: URL
    public let customLocation: Bool
    public init(applicationURL: URL, dataRootURL: URL, cacheRootURL: URL, customLocation: Bool) {
        self.applicationURL = applicationURL.standardizedFileURL; self.dataRootURL = dataRootURL.standardizedFileURL
        self.cacheRootURL = cacheRootURL.standardizedFileURL; self.customLocation = customLocation
    }
}
/// OS/browser identity and activity boundary. Production never uses fixture observations.
public protocol ChromeCacheEnvironment: Sendable {
    func validateInstallation(at url: URL) throws
    func browserIsRunning(bundleURL: URL) throws -> Bool
    func now() -> Date
}
public struct NativeChromeCacheEnvironment: ChromeCacheEnvironment {
    public init() {}
    public func now() -> Date { Date() }
    public func validateInstallation(at url: URL) throws {
        guard url.isFileURL, url.resolvingSymlinksInPath().path == url.path else { throw ChromeCacheFailure("Chrome application location is unsupported.") }
        try verifyChromeLocalLocation(url)
        try verifyChromeLocalLocation(url.appendingPathComponent("Contents/Info.plist"))
        try verifyChromeLocalLocation(url.appendingPathComponent("Contents/MacOS/Google Chrome"))
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var machine = utsname(); uname(&machine)
        let architecture = withUnsafeBytes(of: machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard os.majorVersion == 26, os.minorVersion == 6, os.patchVersion == 2, architecture == "arm64",
              let bundle = Bundle(url: url), bundle.bundleIdentifier == "com.google.Chrome",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "156.0.8078.48" else {
            throw ChromeCacheFailure("This Chrome or macOS version has not been qualified.")
        }
        var code: SecStaticCode?; var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple generic and identifier \"com.google.Chrome\" and certificate leaf[subject.OU] = \"EQHXZ8M8AV\"" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess else {
            throw ChromeCacheFailure("Chrome's verified Google signature is unavailable.")
        }
        let binary = try Data(contentsOf: url.appendingPathComponent("Contents/MacOS/Google Chrome"), options: .mappedIfSafe)
        guard SHA256.hash(data: binary).map({ String(format: "%02x", $0) }).joined() == "4f71e9dbe725fec1110977b6a6dd0708fb32fbde9c905b4b461cef880ac08288" else {
            throw ChromeCacheFailure("This Chrome executable has not been qualified.")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Query only layout-policy keys; ordinary macOS window preferences are
        // neither management evidence nor reason to block supported users.
        for key in ["DiskCacheDir", "UserDataDir"] {
            guard CFPreferencesCopyAppValue(key as CFString, "com.google.Chrome" as CFString) == nil else {
                throw ChromeCacheFailure("Chrome cache or user-data directory overrides are unsupported.")
            }
        }
        for path in [home.appendingPathComponent("Library/Managed Preferences/com.google.Chrome.plist"), URL(fileURLWithPath: "/Library/Managed Preferences/com.google.Chrome.plist"), URL(fileURLWithPath: "/Library/Preferences/com.google.Chrome.plist")] {
            var info = stat()
            guard lstat(path.path, &info) != 0 && errno == ENOENT else { throw ChromeCacheFailure("Managed Chrome layouts are not supported.") }
        }
    }
    public func browserIsRunning(bundleURL: URL) throws -> Bool {
        // Observe executable ownership, not browsing arguments or account values.
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { throw ChromeCacheFailure("Browser activity could not be checked.") }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, Int(count) < pids.count else { throw ChromeCacheFailure("Browser activity is uncertain.") }
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &bytes, UInt32(bytes.count))
            if length <= 0 {
                var details = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size)
                if read == size, details.pbi_uid == getuid() { throw ChromeCacheFailure("A current-user process could not be identified.", .unknown) }
                continue
            }
            let path = String(cString: bytes)
            if path.hasPrefix(bundleURL.path + "/") || path.hasSuffix("/Contents/MacOS/Google Chrome") || path.contains("/Google Chrome Framework.framework/") { return true }
        }
        return false
    }
}
public enum ChromeCacheAvailability: String, Sendable { case eligible, empty, running, denied, unsupported, unknown }
public struct ChromeCacheGroup: Identifiable, Sendable {
    public let id: String
    public let profileIdentifier: String
    public let estimatedBytes: Int64?
    public let observedAt: Date
    public let availability: ChromeCacheAvailability
}
public struct ChromeCacheInspection: Sendable {
    public let groups: [ChromeCacheGroup]
    public let unavailableReason: String?
    public let availability: ChromeCacheAvailability
    public let observedAt: Date
}
public struct ChromeCacheApproval: Sendable {
    let serviceID: UUID
    let generation: UUID
    let groupIDs: Set<String>
    public let groups: [ChromeCacheGroup]
    public let approvedAt: Date
}
public enum ChromeCacheGroupStatus: String, Codable, Sendable { case succeeded, failed, skipped, cancelled, unknown }
public struct ChromeCacheGroupResult: Codable, Sendable {
    public let profileIdentifier: String
    public let status: ChromeCacheGroupStatus
    public let removedFiles: Int
    public let removedBytes: Int64
    public let reason: String?
}
public struct ChromeCacheRun: Identifiable, Codable, Sendable {
    public let id: UUID
    public var groups: [ChromeCacheGroupResult]
    public var unresolved: Bool
    public let approvedAt: Date
    public let observedAt: Date
}
public struct ChromeCacheFailure: Error, CustomStringConvertible {
    public let description: String
    public let availability: ChromeCacheAvailability
    public init(_ message: String, _ availability: ChromeCacheAvailability = .unsupported) { description = message; self.availability = availability }
}
struct ChromeObjectIdentity: Equatable, Codable, Sendable {
    let device: Int32; let inode: UInt64; let owner: UInt32
    init(_ info: stat) { device = info.st_dev; inode = info.st_ino; owner = info.st_uid }
}
struct ChromeDirectory: Sendable {
    let url: URL; let identity: ChromeObjectIdentity
}
struct ChromeGroupAuthority: Sendable {
    let group: ChromeCacheGroup; let access: ChromeCacheAccess
    let chain: [ChromeDirectory]
}

/// Browser group capability is deliberately separate from the personal-file plan/executor.
public actor ChromeCacheService {
    let environment: any ChromeCacheEnvironment
    let journalURL: URL
    let serviceID = UUID()
    var generation = UUID()
    var authorities: [String: ChromeGroupAuthority] = [:]
    var cancelled = false
    var executing = false
    public init(environment: any ChromeCacheEnvironment = NativeChromeCacheEnvironment(), journalURL: URL) {
        self.environment = environment; self.journalURL = journalURL
    }
    public func inspect(_ access: ChromeCacheAccess) -> ChromeCacheInspection {
        let observedAt = environment.now(); let prior = authorities
        guard !executing else { return .init(groups: [], unavailableReason: "Cleanup is in progress.", availability: .unknown, observedAt: observedAt) }
        generation = UUID(); authorities = [:]
        do {
            try environment.validateInstallation(at: access.applicationURL)
            guard try !environment.browserIsRunning(bundleURL: access.applicationURL) else { throw ChromeCacheFailure("Quit Chrome and its helpers, then check again.", .running) }
            try validateMapping(access)
            _ = try directoryChain([access.dataRootURL, access.cacheRootURL])
            let ownership = try readChromeOwnership(access.dataRootURL.appendingPathComponent("Local State"))
            guard !ownership.hasOverride, ownership.identifiers.count <= 100 else {
                throw ChromeCacheFailure("Chrome profile ownership or cache configuration is unsupported.")
            }
            for identifier in ownership.identifiers.sorted() {
                guard identifier == "Default" || identifier.range(of: #"^Profile [1-9][0-9]*$"#, options: .regularExpression) != nil else {
                    throw ChromeCacheFailure("A custom or shared profile layout is unsupported.")
                }
                let profileURL = access.dataRootURL.appendingPathComponent(identifier)
                try verifyChromeProfileMetadata(profileURL.appendingPathComponent("Preferences"))
                let target = access.cacheRootURL.appendingPathComponent(identifier + "/Cache/Cache_Data")
                var info = stat()
                if lstat(target.path, &info) != 0, errno == ENOENT { continue }
                let chain = try directoryChain([access.dataRootURL, profileURL, access.cacheRootURL,
                    access.cacheRootURL.appendingPathComponent(identifier), target.deletingLastPathComponent(), target])
                let leaves = try ChromeOpenGroup(chain: chain).entries()
                let existing = prior.values.first { $0.access.dataRootURL == access.dataRootURL && $0.group.profileIdentifier == identifier && $0.chain == chain }
                let key = identifier + chain.map { "\($0.identity.device):\($0.identity.inode):\($0.identity.owner)" }.joined(separator: "/")
                let stableID = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                let group = ChromeCacheGroup(id: existing?.group.id ?? stableID, profileIdentifier: identifier,
                    estimatedBytes: leaves.reduce(0) { $0 + $1.bytes }, observedAt: observedAt,
                    availability: leaves.isEmpty ? .empty : .eligible)
                authorities[group.id] = .init(group: group, access: access, chain: chain)
            }
            return .init(groups: authorities.values.map(\.group).sorted { $0.profileIdentifier < $1.profileIdentifier }, unavailableReason: nil, availability: authorities.isEmpty ? .empty : .eligible, observedAt: observedAt)
        } catch {
            authorities = [:]
            return .init(groups: [], unavailableReason: (error as? ChromeCacheFailure)?.description ?? "Chrome metadata or access could not be verified.", availability: (error as? ChromeCacheFailure)?.availability ?? .unknown, observedAt: observedAt)
        }
    }
    public func approve(groupIDs: Set<String>) throws -> ChromeCacheApproval {
        guard !executing, !groupIDs.isEmpty, groupIDs.isSubset(of: Set(authorities.keys)),
              groupIDs.allSatisfy({ authorities[$0]?.group.availability == .eligible }) else { throw ChromeCacheFailure("Check the selected cache groups again.") }
        return .init(serviceID: serviceID, generation: generation, groupIDs: groupIDs,
                     groups: groupIDs.compactMap { authorities[$0]?.group }.sorted { $0.profileIdentifier < $1.profileIdentifier }, approvedAt: environment.now())
    }
    public func cancel() { cancelled = true }
    func validateMapping(_ access: ChromeCacheAccess) throws {
        let data = access.dataRootURL.standardizedFileURL
        let cache = access.cacheRootURL.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        let expectedData = support.appendingPathComponent("Google/Chrome")
        guard access.dataRootURL.path == data.path, access.cacheRootURL.path == cache.path else { throw ChromeCacheFailure("Choose a canonical Chrome location.") }
        if !access.customLocation {
            guard data.path == expectedData.path, cache.path == home.appendingPathComponent("Library/Caches/Google/Chrome").path else { throw ChromeCacheFailure("Standard Chrome locations do not match.") }
        } else if data.path.hasPrefix(support.path + "/") {
            guard cache.path == home.appendingPathComponent("Library/Caches").path + String(data.path.dropFirst(support.path.count)) else { throw ChromeCacheFailure("Custom cache mapping is unsupported.") }
        } else {
            guard cache.path == data.path else { throw ChromeCacheFailure("Redirected or shared cache roots are unsupported.") }
        }
    }
}
extension ChromeDirectory: Equatable {}
private struct ChromeMetadataKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ key: String) { stringValue = key }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
struct ChromeProfileOwnership: Decodable {
    let identifiers: [String]
    let hasOverride: Bool
    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: ChromeMetadataKey.self)
        hasOverride = root.contains(.init("disk_cache_dir")) || root.contains(.init("DiskCacheDir"))
        let profile = try root.nestedContainer(keyedBy: ChromeMetadataKey.self, forKey: .init("profile"))
        let cache = try profile.nestedContainer(keyedBy: ChromeMetadataKey.self, forKey: .init("info_cache"))
        identifiers = cache.allKeys.map(\.stringValue)
        for key in cache.allKeys {
            // Validate the ownership record's object shape; never decode its name,
            // account, address, URL or other private values.
            _ = try cache.nestedContainer(keyedBy: ChromeMetadataKey.self, forKey: key)
        }
    }
}
func readChromeOwnership(_ url: URL) throws -> ChromeProfileOwnership {
    try verifyChromeLocalLocation(url)
    var info = stat()
    guard url.isFileURL, url.resolvingSymlinksInPath().path == url.path, lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1,
          info.st_size <= 5 * 1024 * 1024 else { throw ChromeCacheFailure("Chrome metadata is inaccessible or unsupported.") }
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw ChromeCacheFailure("Chrome metadata could not be opened safely.", (errno == EACCES || errno == EPERM) ? .denied : .unknown) }
    defer { close(fd) }
    var opened = stat(); guard fstat(fd, &opened) == 0, ChromeObjectIdentity(info) == ChromeObjectIdentity(opened) else { throw ChromeCacheFailure("Chrome metadata changed.") }
    let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: 5 * 1024 * 1024 + 1) ?? Data()
    guard data.count <= 5 * 1024 * 1024 else { throw ChromeCacheFailure("Chrome metadata exceeds the supported limit.") }
    return try JSONDecoder().decode(ChromeProfileOwnership.self, from: data)
}
func directoryChain(_ urls: [URL]) throws -> [ChromeDirectory] {
    var result: [ChromeDirectory] = []
    for url in urls {
        try verifyChromeLocalLocation(url)
        var info = stat()
        guard url.isFileURL, url.resolvingSymlinksInPath().path == url.path, lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else {
            throw ChromeCacheFailure("Chrome cache ownership, access or directory identity is uncertain.")
        }
        result.append(.init(url: url, identity: .init(info)))
    }
    return result
}

func verifyChromeProfileMetadata(_ url: URL) throws {
    try verifyChromeLocalLocation(url)
    var info = stat()
    guard url.isFileURL, url.resolvingSymlinksInPath().path == url.path,
          lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_uid == getuid(), info.st_nlink == 1 else {
        throw ChromeCacheFailure("Profile metadata identity is inaccessible or unsupported.")
    }
}

/// Resource facts only: never request a download or open a cloud placeholder.
func verifyChromeLocalLocation(_ url: URL) throws {
    let path = url.standardizedFileURL.path
    guard url.isFileURL, url.resolvingSymlinksInPath().path == path,
          !path.contains("/Library/CloudStorage/"), !path.contains("/Library/Mobile Documents/") else {
        throw ChromeCacheFailure("Cloud, redirected or provider Chrome locations are not supported.")
    }
    var info = stat()
    guard lstat(path, &info) == 0 else {
        throw ChromeCacheFailure("Local Chrome location could not be verified.", (errno == EACCES || errno == EPERM) ? .denied : .unknown)
    }
    guard info.st_flags & UInt32(SF_DATALESS) == 0 else {
        throw ChromeCacheFailure("Cloud placeholders are not eligible for Chrome cleanup.")
    }
    let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsLocalKey])
    guard values.isUbiquitousItem != true, !FileManager.default.isUbiquitousItem(at: url), values.volumeIsLocal == true else {
        throw ChromeCacheFailure("Chrome cleanup requires a verified local, non-cloud location.")
    }
}

import Foundation
import Darwin
import Security

/// Metadata at the public native-adapter boundary; never process arguments or source contents.
public struct XcodeProcessRecord: Sendable {
    public let pid: Int32
    public let uid: UInt32?
    public let shortName: String
    public let executable: String?
    public let started: UInt64?
    public let exited: Bool
    public let consistent: Bool
    public init(pid: Int32, uid: UInt32?, shortName: String, executable: String?, started: UInt64?, exited: Bool = false, consistent: Bool = true) {
        self.pid = pid; self.uid = uid; self.shortName = shortName
        self.executable = executable; self.started = started; self.exited = exited; self.consistent = consistent
    }
}
public struct XcodeOwnerSnapshot: Sendable {
    public let currentUID: UInt32
    public let records: [XcodeProcessRecord]
    public let complete: Bool
    public init(currentUID: UInt32, records: [XcodeProcessRecord], complete: Bool) {
        self.currentUID = currentUID; self.records = records; self.complete = complete
    }
}
public protocol XcodeOwnerSnapshotReading: Sendable {
    func snapshot() throws -> XcodeOwnerSnapshot
}
public struct XcodeInstallationObservation: Sendable {
    public let version: String
    /// Authenticated CFBundleVersion, not the separately distributed version.plist ProductBuildVersion.
    public let build: String
    public let codeDirectoryHash: String
    public let developerURL: URL
}

/// Explicit native calls only, bounded to the observed #16 toolchain/layout; app delivery stays gated.
public struct NativeXcodeBuildEnvironment: XcodeBuildEnvironment {
    private let ownerReader: any XcodeOwnerSnapshotReading
    private let applicationURL: URL
    public init(ownerReader: any XcodeOwnerSnapshotReading = NativeXcodeOwnerSnapshotReader(), applicationURL: URL = URL(fileURLWithPath: "/Applications/Xcode.app", isDirectory: true)) {
        self.ownerReader = ownerReader; self.applicationURL = applicationURL
    }
    public func now() -> Date { Date() }
    public func standardDerivedDataURL() throws -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
    }
    public func validateInstallation() throws {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var machine = utsname(); uname(&machine)
        let architecture = withUnsafeBytes(of: machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard os.majorVersion == 26, os.minorVersion == 6, os.patchVersion == 2, architecture == "arm64" else {
            throw NativeXcodeObservationFailure("This macOS version or architecture has not been qualified for Xcode cleanup.")
        }
        let installation = try installationObservation()
        guard installation.version == "26.6", installation.build == "24959",
              installation.codeDirectoryHash == "502eca5e95e1b8eaaf52e9b38617e8e7d23f46db" else {
            throw NativeXcodeObservationFailure("This Xcode version/build has not been qualified for intermediate cleanup.")
        }
    }
    public func projects(in root: URL) throws -> XcodeProjectMapping {
        try XcodeDerivedDataMapping.projects(in: root)
    }
    /// Toolchain facts are observations, not an allowlist or cleanup authority.
    public func installationObservation() throws -> XcodeInstallationObservation {
        let application = applicationURL.resolvingSymlinksInPath()
        guard applicationURL.isFileURL, application.isFileURL else {
            throw NativeXcodeObservationFailure("Xcode application location is not canonical.")
        }
        var code: SecStaticCode?; var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(application as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple and identifier \"com.apple.dt.Xcode\"" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSDoNotValidateResources), requirement) == errSecSuccess else {
            throw NativeXcodeObservationFailure("The Xcode installation signature could not be verified.")
        }
        // Resource traversal is deliberately excluded: the native executable,
        // CodeDirectory, secured Info.plist and strict bundle structure remain checked.
        // ProductBuildVersion from version.plist is not authenticated by this policy.
        var signingDictionary: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingDictionary) == errSecSuccess,
              let signing = signingDictionary as? [String: Any],
              signing[kSecCodeInfoIdentifier as String] as? String == "com.apple.dt.Xcode",
              let info = signing[kSecCodeInfoPList as String] as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode",
              let number = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              let unique = signing[kSecCodeInfoUnique as String] as? Data,
              let executable = signing[kSecCodeInfoMainExecutable as String] as? URL,
              executable.path == application.appendingPathComponent("Contents/MacOS/Xcode").path else {
            throw NativeXcodeObservationFailure("Authenticated Xcode version/build/code identity could not be observed.")
        }
        return .init(version: number, build: build,
                     codeDirectoryHash: unique.map { String(format: "%02x", $0) }.joined(),
                     developerURL: application.appendingPathComponent("Contents/Developer", isDirectory: true))
    }
    public func ownerObservation() throws -> XcodeOwnerObservation {
        let snapshot: XcodeOwnerSnapshot
        do { snapshot = try ownerReader.snapshot() }
        catch { return .init(activity: .unknown, reason: "Xcode build-owner enumeration is unavailable.") }
        guard snapshot.complete else { return .init(activity: .unknown, reason: "Xcode build-owner enumeration is incomplete.") }
        var uncertain = false
        for record in snapshot.records where record.pid > 1 && !record.exited {
            if let uid = record.uid, uid != snapshot.currentUID { continue }
            let name = record.executable.map { URL(fileURLWithPath: $0).lastPathComponent } ?? record.shortName
            guard Self.candidate(name) || Self.candidate(record.shortName) else { continue }
            guard record.consistent, let path = record.executable, path.hasPrefix("/"), record.uid != nil, record.started != nil else {
                uncertain = true; continue
            }
            guard recognizedDeveloperPath(path, name: name) else { uncertain = true; continue }
            return .init(activity: .running, reason: "Xcode or a relevant build owner is still running. Close it normally, then recheck.")
        }
        return uncertain ? .init(activity: .unknown, reason: "A possible Xcode build owner's identity could not be verified. Recheck before cleanup.") : .init(activity: .closed, reason: nil)
    }
    fileprivate static func candidate(_ name: String) -> Bool {
        ["Xcode", "xcodebuild", "SWBBuildService", "SWBBuildServiceBundle", "XCBBuildService", "swift-driver", "swift-frontend", "swiftc", "clang", "clang++", "ld", "dsymutil"].contains(name)
            || name.hasPrefix("SWBBuildService") || name.hasPrefix("XCBBuildService")
    }
    private func recognizedDeveloperPath(_ path: String, name: String) -> Bool {
        let selected = Set([applicationURL.path, applicationURL.resolvingSymlinksInPath().path])
        if name == "Xcode" { return selected.contains { path == $0 + "/Contents/MacOS/Xcode" } }
        if name == "xcodebuild", path == "/usr/bin/xcodebuild" { return true }
        return selected.contains { root in
            ["Contents/Developer/", "Contents/SharedFrameworks/", "Contents/Frameworks/"].contains { path.hasPrefix(root + "/" + $0) }
        } || path.hasPrefix("/Library/Developer/CommandLineTools/")
    }
}
private struct NativeXcodeObservationFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// No call occurs at initialization. Only an explicit public observation inventories metadata.
public struct NativeXcodeOwnerSnapshotReader: XcodeOwnerSnapshotReading {
    public init() {}
    public func snapshot() throws -> XcodeOwnerSnapshot {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0, estimated < 100_000 else { throw NativeXcodeObservationFailure("Process enumeration is unavailable.") }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 256)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, count < pids.count else { return .init(currentUID: getuid(), records: [], complete: false) }
        var records: [XcodeProcessRecord] = []
        for pid in pids.prefix(Int(count)) where pid > 1 {
            var details = proc_bsdinfo()
            errno = 0
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &details, size)
            let metadataError = errno
            var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &bytes, UInt32(bytes.count))
            let path = length > 0 ? String(cString: bytes) : nil
            if read != size {
                if let path {
                    records.append(.init(pid: pid, uid: nil, shortName: URL(fileURLWithPath: path).lastPathComponent, executable: path, started: nil))
                } else if metadataError == ESRCH { continue }
                // No successful metadata exists: never interpret zero-filled UID/state.
                // Unrecognized inaccessible entries do not become build owners by assumption.
                continue
            }
            guard details.pbi_uid == getuid() else { continue }
            let shortName = withUnsafeBytes(of: details.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let candidate = NativeXcodeBuildEnvironment.candidate(shortName)
                || path.map { NativeXcodeBuildEnvironment.candidate(URL(fileURLWithPath: $0).lastPathComponent) } == true
            var consistent = true
            if candidate {
                var latest = proc_bsdinfo()
                let second = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &latest, size)
                var latestBytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                let latestLength = proc_pidpath(pid, &latestBytes, UInt32(latestBytes.count))
                let latestPath = latestLength > 0 ? String(cString: latestBytes) : nil
                consistent = second == size && latest.pbi_pid == details.pbi_pid && latest.pbi_uid == details.pbi_uid
                    && latest.pbi_start_tvsec == details.pbi_start_tvsec && latest.pbi_start_tvusec == details.pbi_start_tvusec
                    && latestPath == path
            }
            let seconds = details.pbi_start_tvsec.multipliedReportingOverflow(by: 1_000_000)
            let start = seconds.partialValue.addingReportingOverflow(details.pbi_start_tvusec)
            records.append(.init(pid: pid, uid: details.pbi_uid, shortName: shortName, executable: path,
                started: seconds.overflow || start.overflow ? nil : start.partialValue,
                exited: details.pbi_status == UInt32(SZOMB), consistent: consistent))
        }
        return .init(currentUID: getuid(), records: records, complete: true)
    }
}

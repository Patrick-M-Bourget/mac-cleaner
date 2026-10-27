import Foundation
import Darwin

/// What `simctl list devices -j` and `simctl runtime list -j` say. Read once per scan, and again just before acting on each simulator item.
struct SimulatorInventory: Sendable {
    struct Device: Decodable, Sendable {
        let udid: String
        let name: String
        let state: String?
        let isAvailable: Bool?
        let lastBootedAt: String?
    }
    struct Runtime: Decodable, Sendable {
        let identifier: String
        let runtimeIdentifier: String?
        let version: String?
        let build: String?
        let sizeBytes: Int64?
        let lastUsedAt: String?
        let deletable: Bool?
    }
    /// Devices by the runtime identifier they run (`com.apple.CoreSimulator.SimRuntime.iOS-18-0`).
    let devices: [String: [Device]]
    let runtimes: [Runtime]

    static let timeout: TimeInterval = 30
    static func parse(devices: String, runtimes: String) throws -> SimulatorInventory {
        struct DeviceList: Decodable { let devices: [String: [Device]] }
        let devices = try JSONDecoder().decode(DeviceList.self, from: Data(devices.utf8)).devices
        let runtimes = try JSONDecoder().decode([String: Runtime].self, from: Data(runtimes.utf8))
        return SimulatorInventory(devices: devices, runtimes: runtimes.keys.sorted().compactMap { runtimes[$0] })
    }
    /// Runs both listings with the tool's own folder first on PATH, as tool actions run.
    static func read(_ simctl: URL) -> Result<SimulatorInventory, ToolPreviewError> {
        var environment = BoundedTool.defaultEnvironment
        environment["PATH"] = simctl.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        do {
            let devices = try BoundedTool.run(executable: simctl, arguments: ["list", "devices", "-j"], timeout: timeout, outputLimit: 4_000_000, environment: environment)
            let runtimes = try BoundedTool.run(executable: simctl, arguments: ["runtime", "list", "-j"], timeout: timeout, outputLimit: 4_000_000, environment: environment)
            return .success(try parse(devices: devices, runtimes: runtimes))
        } catch let error as ToolPreviewError { return .failure(error) }
        catch { return .failure(.invalidOutput) }
    }
    static let notice = "Couldn’t read the simulator list, so simulators aren’t shown. Scan again."

    /// Runtimes any device runs, available or not.
    var usedRuntimeIdentifiers: Set<String> { Set(devices.filter { !$0.value.isEmpty }.keys) }

    /// Why a simulator device or runtime can't be acted on now, from simctl's lists read again just before acting (#143);
    /// nil when it still can. A list that can't be read refuses.
    static func refusal(for candidate: Candidate, items: CatalogItems) -> CheckRefusal? {
        guard let simctl = candidate.toolURL, let item = candidate.toolItem else { return .changed }
        guard case .success(let inventory) = read(simctl) else { return .inUseUnknown("a simulator") }
        if items == .simulatorDevices {
            guard let device = inventory.devices.values.joined().first(where: { $0.udid == item }) else { return .missing }
            guard device.isAvailable == true else { return .changed }
            return device.state == "Shutdown" ? nil : .ownerRunning("This simulator")
        }
        guard let runtime = inventory.runtimes.first(where: { $0.identifier == item }) else { return .missing }
        guard runtime.deletable == true, let identifier = runtime.runtimeIdentifier else { return .changed }
        return inventory.usedRuntimeIdentifiers.contains(identifier) ? .inUse("A simulator") : nil
    }

    /// "iOS 18.0" from `com.apple.CoreSimulator.SimRuntime.iOS-18-0`; nil when it isn't one.
    static func runtimeName(_ identifier: String, version: String? = nil) -> String? {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        guard identifier.hasPrefix(prefix) else { return nil }
        let parts = identifier.dropFirst(prefix.count).split(separator: "-").map(String.init)
        guard let platform = parts.first, !platform.isEmpty else { return nil }
        let name = platform == "xrOS" ? "visionOS" : platform
        let number = version ?? parts.dropFirst().joined(separator: ".")
        return number.isEmpty ? name : name + " " + number
    }

    /// simctl's dates, with or without fractional seconds.
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// Only a canonical UUID ever becomes simctl's argument, so nothing read from its output can be an option.
    static func isIdentifier(_ text: String) -> Bool {
        UUID(uuidString: text)?.uuidString == text.uppercased() && text.count == 36 && !text.hasPrefix("-")
    }
}

extension Catalog {
    /// Each simulator that is available and shut down, as its own folder in `devices`, sized on disk.
    func simulatorDevices(in devices: URL, rule: CleanupRule, toolURL: URL?, inventory: SimulatorInventory, sizer: KnownLocationSizer) -> [Candidate] {
        inventory.devices.keys.sorted().flatMap { runtime in
            (inventory.devices[runtime] ?? []).compactMap { device -> Candidate? in
                guard device.isAvailable == true, device.state == "Shutdown", SimulatorInventory.isIdentifier(device.udid) else { return nil }
                let url = devices.appendingPathComponent(device.udid)
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR else { return nil }
                let size = sizer.size(url)
                let lastUsed = SimulatorInventory.date(device.lastBootedAt) ?? Self.lastUsedInside(url, info)
                var found = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: lastUsed, toolURL: toolURL)
                found.itemName = SimulatorInventory.runtimeName(runtime).map { "\(device.name) (\($0))" } ?? device.name
                found.toolItem = device.udid
                return found
            }
        }
    }

    /// Each deletable runtime no simulator uses, anchored on the user's CoreSimulator folder, sized as simctl reports it.
    func simulatorRuntimes(anchor: URL, rule: CleanupRule, toolURL: URL?, inventory: SimulatorInventory) -> [Candidate] {
        var info = stat()
        guard lstat(anchor.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR else { return [] }
        let used = inventory.usedRuntimeIdentifiers
        return inventory.runtimes.compactMap { runtime in
            guard runtime.deletable == true, SimulatorInventory.isIdentifier(runtime.identifier),
                  let identifier = runtime.runtimeIdentifier, !used.contains(identifier), let name = SimulatorInventory.runtimeName(identifier, version: runtime.version) else { return nil }
            var found = candidate(rule, anchor, info, logical: max(runtime.sizeBytes ?? 0, 0), allocated: nil, complete: runtime.sizeBytes != nil,
                                  lastUsed: SimulatorInventory.date(runtime.lastUsedAt), toolURL: toolURL)
            found.itemName = runtime.build.map { name + " (\($0))" } ?? name
            found.toolItem = runtime.identifier
            return found
        }
    }
}

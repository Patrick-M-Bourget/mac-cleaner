import Foundation
import Darwin

/// Simulator runtimes and devices, Android system images and virtual devices (#134). Each is chosen on its own,
/// with its size and when it was last used. Simulators go through simctl only (Decision 21), never by deleting folders.
extension BuiltInCatalog {
    /// CoreSimulator's own simctl first: `xcrun` fails while xcode-select points at the Command Line Tools,
    /// and Xcode's wrapper may run first-launch setup, which can ask for an admin password (Decision 4).
    static let simctlExecutables = ["/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl",
                                    "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"]
    static let simulatorOwner = RuleOwner(name: "Simulator or Xcode", bundleIDs: ["com.apple.iphonesimulator", "com.apple.dt.Xcode"], executables: ["Simulator", "Xcode"])
    static let simulatorRuntimes = CleanupRule(
        id: "simulator-runtimes", category: .developer, title: "Simulator runtimes",
        detail: "Simulator OS versions no available simulator uses.",
        consequence: "Runs `simctl runtime delete` for each runtime, which permanently removes it. Xcode downloads it again when you need it.",
        // The user's CoreSimulator folder anchors the rule in the home folder; the runtimes themselves live outside it.
        regen: .build, action: .tool, locations: ["Library/Developer/CoreSimulator"], owner: simulatorOwner,
        tool: ToolCommand(executables: simctlExecutables, arguments: ["runtime", "delete", "<runtime>"], timeout: 600, itemPlaceholder: "<runtime>"),
        items: .simulatorRuntimes)
    static let simulatorDevices = CleanupRule(
        id: "simulator-devices", category: .developer, title: "Simulators",
        detail: "Simulator devices that aren’t running.",
        consequence: "Runs `simctl delete` for each simulator, which permanently removes it with its apps and data. Create it again in Xcode if you need it.",
        regen: .build, action: .tool, locations: ["Library/Developer/CoreSimulator/Devices"], owner: simulatorOwner,
        tool: ToolCommand(executables: simctlExecutables, arguments: ["delete", "<device>"], timeout: 120, itemPlaceholder: "<device>"),
        items: .simulatorDevices)

    static let androidOwner = RuleOwner(name: "Android Studio or the emulator", bundleIDs: ["com.google.android.studio"], executables: ["emulator", "qemu-system-*"])
    /// An emulator's disk images and data: VM images go to Trash (Decision 3), with the `.ini` file that points to them.
    static let androidVirtualDevices = CleanupRule(
        id: "android-virtual-devices", category: .developer, title: "Android emulators",
        detail: "Virtual devices Android Studio created.",
        consequence: "Moved to Trash with its settings file, including the apps and data inside it. You can restore it from the Trash.",
        regen: .model, action: .trash, locations: [".android/avd"], owner: androidOwner, items: .androidVirtualDevices)
    static let androidSystemImages = CleanupRule(
        id: "android-system-images", category: .developer, title: "Android system images",
        detail: "Emulator system images no virtual device uses.",
        consequence: "Permanently removed. Android Studio’s SDK Manager downloads them again when you need them.",
        regen: .build, action: .delete, locations: ["Library/Android/sdk/system-images"], owner: androidOwner, items: .androidSystemImages)

    static let developerDeviceRules = [simulatorRuntimes, simulatorDevices]
}

extension CatalogItems {
    /// Whether the user chooses each item the rule finds on its own.
    public var choosesEachItem: Bool {
        switch self {
        case .ollamaModels, .simulatorRuntimes, .simulatorDevices, .androidVirtualDevices, .androidSystemImages: true
        case .docker: false
        }
    }
}

/// What `simctl list devices -j` and `simctl runtime list -j` say. Read once per scan.
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

    /// Runtimes some available device runs.
    var usedRuntimeIdentifiers: Set<String> { Set(devices.filter { $0.value.contains { $0.isAvailable == true } }.keys) }

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

    /// Each deletable runtime no available simulator uses, anchored on the user's CoreSimulator folder, sized as simctl reports it.
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

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
        detail: "Simulator OS versions no simulator uses.",
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

    static let developerDeviceRules = [simulatorRuntimes, simulatorDevices, androidVirtualDevices, androidSystemImages]
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

/// Android Studio's default layout: virtual devices in `~/.android/avd`, the SDK in `~/Library/Android/sdk`.
enum AndroidSDK {
    static let avdFolder = ".android/avd"
    static let sdkFolder = "Library/Android/sdk"
    static let unreadableNotice = "Couldn’t read which system image every Android virtual device uses, so no system image is offered."
    static let maximumConfigBytes = 1_000_000

    /// The `<name>.ini` Android Studio keeps beside a `<name>.avd` folder.
    static func iniFile(of avd: URL) -> URL { avd.deletingPathExtension().appendingPathExtension("ini") }

    /// How a system image folder is compared: absolute, standardized, symlinks resolved, no trailing slash.
    static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    /// Every system image folder a virtual device uses, from each device's `config.ini` (`image.sysdir.N`).
    /// Nil when any device's settings can't be read or name no image, so nothing is guessed.
    static func referencedImages(home: URL) -> Set<String>? {
        let folder = home.appendingPathComponent(avdFolder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var devices = Set(names.filter { $0.hasSuffix(".avd") }.map { key(folder.appendingPathComponent($0)) })
        // A device kept elsewhere is found through its `.ini`.
        for name in names where name.hasSuffix(".ini") {
            guard let text = read(folder.appendingPathComponent(name)) else { return nil }
            if let path = values(in: text)["path"], path.hasPrefix("/") { devices.insert(key(URL(fileURLWithPath: path))) }
        }
        let sdk = home.appendingPathComponent(sdkFolder)
        var used = Set<String>()
        for device in devices {
            var info = stat()
            guard lstat(device, &info) == 0 else { continue }
            guard info.st_mode & S_IFMT == S_IFDIR, let text = read(URL(fileURLWithPath: device).appendingPathComponent("config.ini")) else { return nil }
            let images = values(in: text).filter { $0.key.hasPrefix("image.sysdir.") }.map(\.value).filter { !$0.isEmpty }
            guard !images.isEmpty else { return nil }
            for image in images { used.insert(key(image.hasPrefix("/") ? URL(fileURLWithPath: image) : sdk.appendingPathComponent(image))) }
        }
        return used
    }

    private static func read(_ url: URL) -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= maximumConfigBytes else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    /// `key=value` lines; the first value of each key wins.
    static func values(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces), value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if result[name] == nil { result[name] = value }
        }
        return result
    }

    /// "Android 34 · google_apis · arm64-v8a" for `android-34/google_apis/arm64-v8a`.
    static func imageName(_ parts: [String]) -> String {
        let api = parts.first.map { $0.hasPrefix("android-") ? "Android " + $0.dropFirst("android-".count) : $0 } ?? ""
        return ([api] + parts.dropFirst()).joined(separator: " · ")
    }
}

extension Catalog {
    /// Each `<name>.avd` folder in `folder`, named as Android Studio shows it, sized, with when it was last used.
    func androidVirtualDevices(in folder: URL, rule: CleanupRule, sizer: KnownLocationSizer) -> [Candidate] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".avd") && !$0.hasPrefix(".") }.sorted()
        return names.prefix(Self.childLimit).compactMap { name in
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
                  Protection(rule).protectedComponent(of: url, below: folder) == nil, CandidateCheck.protectedEntry(in: url, rule: rule) == nil else { return nil }
            let size = sizer.size(url)
            var found = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: Self.lastUsedInside(url, info))
            let config = try? String(contentsOf: url.appendingPathComponent("config.ini"), encoding: .utf8)
            let shown = config.flatMap { AndroidSDK.values(in: $0)["avd.ini.displayname"] }.flatMap { $0.isEmpty || $0.count > 100 ? nil : $0 }
            found.itemName = shown ?? (name as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
            return found
        }
    }

    /// Each system image folder (`<api>/<tag>/<abi>`) no virtual device uses. With a device whose image can't be read,
    /// nothing is offered and a note says why.
    func androidSystemImages(in root: URL, home: URL, rule: CleanupRule, sizer: KnownLocationSizer) -> ([Candidate], CatalogNote?) {
        func folders(_ url: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted().filter { name in
                var info = stat()
                return !name.hasPrefix(".") && lstat(url.appendingPathComponent(name).path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
            }
        }
        let paths = folders(root).flatMap { api in folders(root.appendingPathComponent(api)).flatMap { tag in
            folders(root.appendingPathComponent(api + "/" + tag)).map { [api, tag, $0] } } }
        guard !paths.isEmpty else { return ([], nil) }
        guard let used = AndroidSDK.referencedImages(home: home) else { return ([], CatalogNote(ruleID: rule.id, text: AndroidSDK.unreadableNotice)) }
        let found = paths.prefix(Self.childLimit).compactMap { parts -> Candidate? in
            let url = root.appendingPathComponent(parts.joined(separator: "/"))
            var info = stat()
            guard !used.contains(AndroidSDK.key(url)), lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
                  Protection(rule).protectedComponent(of: url, below: root) == nil, CandidateCheck.protectedEntry(in: url, rule: rule) == nil else { return nil }
            let size = sizer.size(url)
            var image = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: Self.lastUsedInside(url, info))
            image.itemName = AndroidSDK.imageName(parts)
            return image
        }
        return (found, nil)
    }
}

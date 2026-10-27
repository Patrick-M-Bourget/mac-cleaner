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
        tool: ToolCommand(executables: simctlExecutables, arguments: ["runtime", "delete", "<runtime>"], timeout: 600, itemPlaceholder: "<runtime>", daemonBacked: true),
        items: .simulatorRuntimes)
    static let simulatorDevices = CleanupRule(
        id: "simulator-devices", category: .developer, title: "Simulators",
        detail: "Simulator devices that aren’t running.",
        consequence: "Runs `simctl delete` for each simulator, which permanently removes it with its apps and data. Create it again in Xcode if you need it.",
        regen: .build, action: .tool, locations: ["Library/Developer/CoreSimulator/Devices"], owner: simulatorOwner,
        tool: ToolCommand(executables: simctlExecutables, arguments: ["delete", "<device>"], timeout: 120, itemPlaceholder: "<device>", daemonBacked: true),
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
        case .docker, .unavailableSimulators: false
        }
    }
}

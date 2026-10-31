import AppKit
import DiskArbitration
import Observation
import Security
import SwiftUI
import CacheDropCore

/// Offers to move a copy opened from a disk image to Applications, before onboarding (#559, Decision 124).
/// CacheDropCore decides where it is and what the move replaces; this performs the move, the relaunch and the eject.
@MainActor @Observable final class MoveToApplicationsModel {
    static let shared = MoveToApplicationsModel()
    /// Decided once per launch, so "Not now" holds for this copy only and the next launch from a disk image asks again.
    var isShowing = false
    private(set) var moving = false
    private(set) var failure = ""
    private(set) var detail = ""
    private var location = AppBundleLocation.other

    func decideAtLaunch() {
        location = Self.runningLocation()
        guard location.offersMove else { return }
        switch decide() {
        case .move(let plan): detail = plan.isInHomeFolder ? Self.homeFolderDetail : Self.applicationsDetail
        case .refused(let reason): detail = Self.applicationsDetail; failure = reason
        }
        isShowing = true
    }
    static let applicationsDetail = "From the disk image, CacheDrop can’t install updates."
    static let homeFolderDetail = "It goes to the Applications folder in your home folder."

    func notNow() { isShowing = false }

    /// Decides again at the click, copies and checks the copy off the main thread, then relaunches it and quits.
    func move() async {
        guard !moving else { return }
        moving = true; failure = ""
        defer { moving = false }
        guard case .move(let plan) = decide() else {
            if case .refused(let reason) = decide() { failure = reason }
            return
        }
        let source = Bundle.main.bundleURL.path, steps = FileMoveSteps(trash: TrashModel.mover)
        if let reason = await Task.detached(operation: { ApplicationsMove.perform(plan, source: source, steps: steps) }).value {
            failure = reason; return
        }
        do { try await relaunch(URL(fileURLWithPath: plan.destination)) }
        catch { failure = "CacheDrop is in Applications but couldn’t open from there."; return }
        NSApp.terminate(nil)
    }

    private func decide() -> ApplicationsMove.Decision {
        let folders = Self.folders
        let running = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return ApplicationsMove.decide(applications: folders.applications, applicationsAccess: Self.access(folders.applications),
                                       userApplications: folders.user, userApplicationsAccess: Self.access(folders.user),
                                       existing: { path in
            guard FileManager.default.fileExists(atPath: path) else { return .none }
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            let open = real == running || NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.resolvingSymlinksInPath().path == real }
            return .present(isRunning: open)
        }, token: UUID().uuidString)
    }

    private func relaunch(_ app: URL) async throws {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            // A journey never opens a second copy: it records what would open and quits.
            try Data(app.path.utf8).write(to: LocalStateLocation.root(create: true).appendingPathComponent("moved-to-applications"))
            return
        }
        #endif
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        if let volume = location.diskImageToEject {
            configuration.arguments = ApplicationsMove.ejectArguments(volume: volume, afterProcess: ProcessInfo.processInfo.processIdentifier)
        }
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    /// In the relaunched copy: once the copy that ran from the disk image has quit, eject that image. Best effort.
    static func ejectIfAsked() {
        guard let request = ApplicationsMove.ejectRequest(in: CommandLine.arguments) else { return }
        Task { @MainActor in
            var waits = 0
            while NSRunningApplication(processIdentifier: request.afterProcess) != nil, waits < 60 {
                try? await Task.sleep(for: .milliseconds(500)); waits += 1
            }
            let volume = URL(fileURLWithPath: request.volume)
            guard let mounted = mountedVolume(containing: volume.appendingPathComponent("CacheDrop.app").path),
                  mounted.path == request.volume, mounted.isReadOnly || mounted.isDiskImage else { return }
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }
    }

    // MARK: Facts read from the system

    private static var folders: (applications: String, user: String) {
        #if DEBUG
        if LocalStateLocation.isDisposableTest, let home = CatalogCleanupModel.home {
            return (home.appendingPathComponent("cachedrop-test-Applications").path, home.appendingPathComponent("Applications").path)
        }
        #endif
        return ("/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)
    }

    private static func runningLocation() -> AppBundleLocation {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            // Journeys force each state; without a fixture home there is nowhere safe to move to.
            guard CatalogCleanupModel.home != nil else { return .buildProducts }
            switch ProcessInfo.processInfo.environment["CACHEDROP_TEST_APP_LOCATION"] {
            case "disk-image": return .diskImage(volume: "/Volumes/cachedrop-test-image")
            case "translocated": return .translocated(original: nil, diskImageVolume: nil)
            case "applications": return .applications
            case "user-applications": return .userApplications
            case "other": return .other
            default: return .buildProducts
            }
        }
        #endif
        return AppBundleLocation.classify(bundle: Bundle.main.bundleURL.path, home: FileManager.default.homeDirectoryForCurrentUser.path,
                                          original: translocatedOriginal, volume: mountedVolume)
    }

    private static func access(_ path: String) -> FolderAccess {
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &directory) {
            return directory.boolValue && FileManager.default.isWritableFile(atPath: path) ? .writable : .unwritable
        }
        return FileManager.default.isWritableFile(atPath: (path as NSString).deletingLastPathComponent) ? .creatable : .unwritable
    }

    /// The volume holding `path`: read-only from its resource values, a disk image from Disk Arbitration's device model.
    nonisolated static func mountedVolume(containing path: String) -> MountedVolume? {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeURLKey, .volumeIsReadOnlyKey]),
              let volume = values.volume else { return nil }
        var diskImage = false
        if let session = DASessionCreate(kCFAllocatorDefault),
           let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
           let description = DADiskCopyDescription(disk) as? [CFString: Any] {
            diskImage = description[kDADiskDescriptionDeviceModelKey] as? String == "Disk Image"
        }
        return MountedVolume(path: volume.path, isReadOnly: values.volumeIsReadOnly ?? false, isDiskImage: diskImage)
    }

    /// Where macOS says a translocated bundle really is. Security's translocation calls aren't in the public headers,
    /// so they're looked up at run time; when they're missing the original is unknown and the move is still offered.
    nonisolated static func translocatedOriginal(_ path: String) -> String? {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
        typealias CreateOriginal = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let url = URL(fileURLWithPath: path) as CFURL
        var translocated = false
        guard unsafeBitCast(isSymbol, to: IsTranslocated.self)(url, &translocated, nil), translocated,
              let original = unsafeBitCast(originalSymbol, to: CreateOriginal.self)(url, nil)?.takeRetainedValue() else { return nil }
        return (original as URL).path
    }
}

/// The move's file work. `FileManager.copyItem` copies with copyfile(3), keeping extended attributes, permissions and
/// symbolic links as they are, like `ditto`, without running another program; the signature check then proves the copy
/// is intact. The old copy goes through CacheDrop's own Trash path, never a permanent delete. Gatekeeper's quarantine is
/// left exactly as the copy carries it.
private struct FileMoveSteps: ApplicationsMoveSteps, Sendable {
    let trash: any TrashMoving
    func createFolder(_ path: String) throws { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false) }
    func copy(_ source: String, to staging: String) throws { try FileManager.default.copyItem(atPath: source, toPath: staging) }
    /// Valid in full, nested code included, and signed as this running copy is (its designated requirement).
    func verifySignature(_ path: String) throws {
        var running: SecCode?, runningStatic: SecStaticCode?, requirement: SecRequirement?, copy: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &copy) == errSecSuccess, let copy,
              SecStaticCodeCheckValidity(copy, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate),
                                         requirement) == errSecSuccess else { throw CocoaError(.fileReadCorruptFile) }
    }
    func moveToTrash(_ path: String) throws { _ = try trash.moveToTrash(URL(fileURLWithPath: path)) }
    func rename(_ path: String, to destination: String) throws { try FileManager.default.moveItem(atPath: path, toPath: destination) }
    func removeStaging(_ path: String) { try? FileManager.default.removeItem(atPath: path) }
}

struct MoveToApplicationsView: View {
    let model: MoveToApplicationsModel
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            AppBrand()
            VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                Text("Move CacheDrop to your Applications folder?").font(CacheDropDesign.TypeStyle.sheet).fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("moveToApplicationsTitle")
                Text(model.detail).font(CacheDropDesign.TypeStyle.note).foregroundStyle(.secondary)
                    .accessibilityIdentifier("moveToApplicationsDetail")
            }
            if !model.failure.isEmpty {
                StatusRow(text: model.failure, symbol: "exclamationmark.circle", role: .failure, identifier: "moveToApplicationsFailure")
            }
            Divider()
            SheetFooter {
                EmptyView()
            } actions: {
                Button("Not now") { model.notNow() }.keyboardShortcut(.cancelAction).disabled(model.moving)
                    .accessibilityIdentifier("moveToApplicationsNotNow")
                Button("Move to Applications") { Task { await model.move() } }.keyboardShortcut(.defaultAction).disabled(model.moving)
                    .accessibilityIdentifier("moveToApplicationsMove")
            }
        }
        .padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading).cacheDropButtonRule()
        .interactiveDismissDisabled()
    }
}

import Foundation
import Testing
@testable import CacheDropCore

/// #559: where the running copy of CacheDrop is, and whether to offer moving it to Applications.
@Suite struct AppBundleLocationTests {
    private let home = "/Users/someone"
    private func classify(_ bundle: String, original: String? = nil, volumes: [MountedVolume] = []) -> AppBundleLocation {
        AppBundleLocation.classify(bundle: bundle, home: home, original: { _ in original },
                                   volume: { path in volumes.first { path.hasPrefix($0.path + "/") } })
    }

    @Test func aCopyOnAMountedDiskImageIsOfferedTheMoveAndItsImageIsEjected() {
        let image = MountedVolume(path: "/Volumes/CacheDrop", isReadOnly: true, isDiskImage: true)
        let location = classify("/Volumes/CacheDrop/CacheDrop.app", volumes: [image])
        #expect(location == .diskImage(volume: "/Volumes/CacheDrop"))
        #expect(location.offersMove)
        #expect(location.diskImageToEject == "/Volumes/CacheDrop")
    }

    @Test func aTranslocatedCopyIsOfferedTheMoveWithItsOriginalAndTheImageItCameFrom() {
        let translocated = "/private/var/folders/x1/abc/T/AppTranslocation/0A1B2C3D/d/CacheDrop.app"
        let image = MountedVolume(path: "/Volumes/CacheDrop 0.9.4", isReadOnly: true, isDiskImage: true)
        let fromImage = classify(translocated, original: "/Volumes/CacheDrop 0.9.4/CacheDrop.app", volumes: [image])
        #expect(fromImage == .translocated(original: "/Volumes/CacheDrop 0.9.4/CacheDrop.app", diskImageVolume: "/Volumes/CacheDrop 0.9.4"))
        #expect(fromImage.offersMove)
        #expect(fromImage.diskImageToEject == "/Volumes/CacheDrop 0.9.4")
        let fromDownloads = classify(translocated, original: "/Users/someone/Downloads/CacheDrop.app")
        #expect(fromDownloads == .translocated(original: "/Users/someone/Downloads/CacheDrop.app", diskImageVolume: nil))
        #expect(fromDownloads.offersMove, "Any translocated copy can't update")
        #expect(fromDownloads.diskImageToEject == nil)
        let unknown = classify(translocated)
        #expect(unknown == .translocated(original: nil, diskImageVolume: nil), "Without macOS's answer the move of the running copy is still offered")
        #expect(unknown.offersMove)
    }

    @Test(arguments: [
        ("/Applications/CacheDrop.app", AppBundleLocation.applications),
        ("/Applications/Utilities/CacheDrop.app", .applications),
        ("/Users/someone/Applications/CacheDrop.app", .userApplications),
        ("/Users/someone/Library/Developer/Xcode/DerivedData/CacheDrop-abc/Build/Products/Debug/CacheDrop.app", .buildProducts),
        ("/Users/someone/Workspace/mac-cleaner/.build/xcode/Build/Products/Release/CacheDrop.app", .buildProducts),
        ("/Users/someone/Downloads/CacheDrop.app", .other),
        ("/Applications Old/CacheDrop.app", .other),
        ("/Volumes/Backup/CacheDrop.app", .other),
    ])
    func aCopyAnywhereElseIsNeverOfferedTheMove(_ bundle: String, _ expected: AppBundleLocation) {
        let writableDrive = MountedVolume(path: "/Volumes/Backup", isReadOnly: false, isDiskImage: false)
        let location = classify(bundle, volumes: [writableDrive])
        #expect(location == expected)
        #expect(!location.offersMove)
    }

    @Test func aWritableDiskImageStillCountsAsADiskImage() {
        let image = MountedVolume(path: "/Volumes/CacheDrop", isReadOnly: false, isDiskImage: true)
        #expect(classify("/Volumes/CacheDrop/CacheDrop.app", volumes: [image]) == .diskImage(volume: "/Volumes/CacheDrop"))
    }
}

/// #559: which Applications folder the copy goes to, and whether an existing copy goes to the Trash.
@Suite struct ApplicationsMoveDecisionTests {
    private func decide(applications: FolderAccess = .writable, user: FolderAccess = .creatable,
                        existing: [String: ExistingCopy] = [:]) -> ApplicationsMove.Decision {
        ApplicationsMove.decide(applications: "/Applications", applicationsAccess: applications,
                                userApplications: "/Users/someone/Applications", userApplicationsAccess: user,
                                existing: { existing[$0] ?? .none }, token: "T1")
    }

    @Test func itGoesToApplicationsThroughAStagingCopyBesideIt() {
        #expect(decide() == .move(.init(folder: "/Applications", destination: "/Applications/CacheDrop.app",
                                        staging: "/Applications/.CacheDrop-T1.app", createsFolder: false, trashesExisting: false)))
    }

    @Test func anExistingCopyGoesToTheTrash() {
        let decision = decide(existing: ["/Applications/CacheDrop.app": .present(isRunning: false)])
        guard case .move(let plan) = decision else { Issue.record("\(decision)"); return }
        #expect(plan.trashesExisting)
    }

    @Test func anExistingCopyThatIsRunningIsNeverReplaced() {
        #expect(decide(existing: ["/Applications/CacheDrop.app": .present(isRunning: true)])
                == .refused("The CacheDrop in Applications is open, so it wasn’t replaced."))
    }

    @Test func withoutWriteAccessToApplicationsItOffersTheHomeFolderOne() {
        #expect(decide(applications: .unwritable) == .move(.init(folder: "/Users/someone/Applications",
                                                                 destination: "/Users/someone/Applications/CacheDrop.app",
                                                                 staging: "/Users/someone/Applications/.CacheDrop-T1.app",
                                                                 createsFolder: true, trashesExisting: false)))
        guard case .move(let plan) = decide(applications: .unwritable, user: .writable) else { Issue.record("no move"); return }
        #expect(!plan.createsFolder)
        #expect(plan.isInHomeFolder)
    }

    @Test func withNoWritableApplicationsFolderItSaysWhy() {
        #expect(decide(applications: .unwritable, user: .unwritable)
                == .refused("CacheDrop can’t write to an Applications folder, so it stays where it is."))
    }
}

/// Records each step; `failing` makes that step throw.
private final class RecordedSteps: ApplicationsMoveSteps, @unchecked Sendable {
    var log: [String] = []
    let failing: String?
    init(failing: String? = nil) { self.failing = failing }
    private func step(_ entry: String) throws {
        log.append(entry)
        if let failing, entry.hasPrefix(failing) { throw CocoaError(.fileWriteNoPermission) }
    }
    func createFolder(_ path: String) throws { try step("create \(path)") }
    func copy(_ source: String, to staging: String) throws { try step("copy \(source) \(staging)") }
    func verifySignature(_ path: String) throws { try step("verify \(path)") }
    func moveToTrash(_ path: String) throws { try step("trash \(path)") }
    func rename(_ path: String, to destination: String) throws { try step("rename \(path) \(destination)") }
    func removeStaging(_ path: String) { log.append("remove \(path)") }
}

/// #559: the old copy goes to the Trash only after the new one is copied and verified; a failure says why and undoes the staging copy.
@Suite struct ApplicationsMovePerformTests {
    private let plan = ApplicationsMove.Plan(folder: "/A", destination: "/A/CacheDrop.app", staging: "/A/.CacheDrop-T.app",
                                             createsFolder: true, trashesExisting: true)

    @Test func itCopiesVerifiesThenTrashesTheOldCopyAndPutsTheNewOneInPlace() {
        let steps = RecordedSteps()
        #expect(ApplicationsMove.perform(plan, source: "/V/CacheDrop.app", steps: steps) == nil)
        #expect(steps.log == ["create /A", "copy /V/CacheDrop.app /A/.CacheDrop-T.app", "verify /A/.CacheDrop-T.app",
                              "trash /A/CacheDrop.app", "rename /A/.CacheDrop-T.app /A/CacheDrop.app"])
    }

    @Test func aCopyThatFailsItsSignatureCheckReplacesNothing() {
        let steps = RecordedSteps(failing: "verify")
        #expect(ApplicationsMove.perform(plan, source: "/V/CacheDrop.app", steps: steps)
                == "The copy’s signature couldn’t be verified, so nothing was replaced.")
        #expect(!steps.log.contains { $0.hasPrefix("trash") || $0.hasPrefix("rename") })
        #expect(steps.log.last == "remove /A/.CacheDrop-T.app")
    }

    @Test(arguments: [
        ("create", "CacheDrop couldn’t be copied to Applications."),
        ("copy", "CacheDrop couldn’t be copied to Applications."),
        ("trash", "The CacheDrop in Applications couldn’t be moved to the Trash, so it wasn’t replaced."),
        ("rename", "CacheDrop couldn’t be put in Applications."),
    ])
    func eachFailureSaysWhyInOneLine(_ failing: String, _ reason: String) {
        let steps = RecordedSteps(failing: failing)
        #expect(ApplicationsMove.perform(plan, source: "/V/CacheDrop.app", steps: steps) == reason)
        if failing != "create" { #expect(steps.log.last == "remove /A/.CacheDrop-T.app", "The staging copy never stays behind") }
    }

    @Test func withNothingThereNothingGoesToTheTrash() {
        var plain = plan; plain.trashesExisting = false; plain.createsFolder = false
        let steps = RecordedSteps()
        #expect(ApplicationsMove.perform(plain, source: "/V/CacheDrop.app", steps: steps) == nil)
        #expect(steps.log == ["copy /V/CacheDrop.app /A/.CacheDrop-T.app", "verify /A/.CacheDrop-T.app", "rename /A/.CacheDrop-T.app /A/CacheDrop.app"])
    }
}

/// #559: the copy in Applications ejects the disk image once the copy that ran from it has quit.
@Suite struct DiskImageEjectHandoffTests {
    @Test func theRelaunchedCopyReadsBackWhichImageToEjectAfterWhichProcess() {
        let arguments = ApplicationsMove.ejectArguments(volume: "/Volumes/CacheDrop 0.9.4", afterProcess: 4242)
        #expect(ApplicationsMove.ejectRequest(in: ["/Applications/CacheDrop.app/Contents/MacOS/CacheDrop"] + arguments)
                == .init(volume: "/Volumes/CacheDrop 0.9.4", afterProcess: 4242))
    }

    @Test(arguments: [
        [String](),
        ["--cachedrop-eject-after-move", "/Users/someone", "42"],
        ["--cachedrop-eject-after-move", "/Volumes/A/../..", "42"],
        ["--cachedrop-eject-after-move", "/Volumes/A/B", "42"],
        ["--cachedrop-eject-after-move", "/Volumes/A", "0"],
        ["--cachedrop-eject-after-move", "/Volumes/A"],
    ])
    func onlyAMountedVolumeAndARealProcessAreAccepted(_ arguments: [String]) {
        #expect(ApplicationsMove.ejectRequest(in: ["CacheDrop"] + arguments) == nil)
    }
}

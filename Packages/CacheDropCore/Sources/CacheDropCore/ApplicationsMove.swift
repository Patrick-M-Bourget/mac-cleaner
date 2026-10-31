import Foundation

/// Whether CacheDrop can put a copy in a folder: write to it, create it, or neither.
public enum FolderAccess: Equatable, Sendable { case writable, creatable, unwritable }
/// What's already at the destination.
public enum ExistingCopy: Equatable, Sendable { case none, present(isRunning: Bool) }

/// The file work of a move, done by the app: a copy keeping extended attributes, a code-signature check, the Trash.
public protocol ApplicationsMoveSteps {
    func createFolder(_ path: String) throws
    func copy(_ source: String, to staging: String) throws
    func verifySignature(_ path: String) throws
    func moveToTrash(_ path: String) throws
    func rename(_ path: String, to destination: String) throws
    /// Removes the staging copy CacheDrop made itself; never anything that was there before.
    func removeStaging(_ path: String)
}

/// Moving a copy run from a disk image to Applications (#559, Decision 124). This decides where it goes and what it
/// replaces; the app copies, checks the signature, relaunches and ejects. Never asks for an admin password.
public enum ApplicationsMove {
    public static let bundleName = "CacheDrop.app"

    public struct Plan: Equatable, Sendable {
        public var folder: String
        public var destination: String
        /// The copy is made and checked here, beside the destination, before anything is replaced.
        public var staging: String
        public var createsFolder: Bool
        /// The copy already at `destination` goes to the Trash, only after the new copy passed its signature check.
        public var trashesExisting: Bool
        /// The Applications folder in the home folder, used when the main one can't be written to.
        public var isInHomeFolder: Bool { folder != "/Applications" }
    }
    public enum Decision: Equatable, Sendable {
        case move(Plan)
        /// Says why in one line; CacheDrop stays where it is (Decision 62).
        case refused(String)
    }

    public static let runningCopyReason = "The CacheDrop in Applications is open, so it wasn’t replaced."
    public static let noFolderReason = "CacheDrop can’t write to an Applications folder, so it stays where it is."

    /// `/Applications` when it can be written to, otherwise the home folder's (created if needed). `token` names the
    /// staging copy uniquely.
    public static func decide(applications: String, applicationsAccess: FolderAccess,
                              userApplications: String, userApplicationsAccess: FolderAccess,
                              existing: (String) -> ExistingCopy, token: String) -> Decision {
        let folder: String, access: FolderAccess
        if applicationsAccess == .writable { folder = applications; access = .writable }
        else if userApplicationsAccess != .unwritable { folder = userApplications; access = userApplicationsAccess }
        else { return .refused(noFolderReason) }
        let destination = (folder as NSString).appendingPathComponent(bundleName)
        let trashes: Bool
        switch existing(destination) {
        case .none: trashes = false
        case .present(isRunning: true): return .refused(runningCopyReason)
        case .present(isRunning: false): trashes = true
        }
        return .move(Plan(folder: folder, destination: destination,
                          staging: (folder as NSString).appendingPathComponent(".CacheDrop-\(token).app"),
                          createsFolder: access == .creatable, trashesExisting: trashes))
    }

    /// Copies to the staging path, checks the copy's signature, then trashes the old copy and puts the new one in place.
    /// Returns nil once the new copy is in place, or why it isn't; the staging copy never stays behind.
    public static func perform(_ plan: Plan, source: String, steps: some ApplicationsMoveSteps) -> String? {
        let notCopied = "CacheDrop couldn’t be copied to Applications."
        if plan.createsFolder { do { try steps.createFolder(plan.folder) } catch { return notCopied } }
        func failed(_ reason: String) -> String { steps.removeStaging(plan.staging); return reason }
        do { try steps.copy(source, to: plan.staging) } catch { return failed(notCopied) }
        do { try steps.verifySignature(plan.staging) } catch { return failed("The copy’s signature couldn’t be verified, so nothing was replaced.") }
        if plan.trashesExisting {
            do { try steps.moveToTrash(plan.destination) } catch { return failed("The CacheDrop in Applications couldn’t be moved to the Trash, so it wasn’t replaced.") }
        }
        do { try steps.rename(plan.staging, to: plan.destination) } catch { return failed("CacheDrop couldn’t be put in Applications.") }
        return nil
    }

    /// A disk image can't be ejected while the copy that ran from it is still open, so the relaunched copy ejects it,
    /// once that process has quit. Best effort: an image that won't eject stays mounted.
    public struct EjectRequest: Equatable, Sendable {
        public var volume: String
        public var afterProcess: Int32
    }
    static let ejectFlag = "--cachedrop-eject-after-move"
    public static func ejectArguments(volume: String, afterProcess: Int32) -> [String] { [ejectFlag, volume, String(afterProcess)] }
    /// Only a volume mounted directly in `/Volumes` and a real process id.
    public static func ejectRequest(in arguments: [String]) -> EjectRequest? {
        guard let index = arguments.firstIndex(of: ejectFlag), arguments.count > index + 2,
              let process = Int32(arguments[index + 2]), process > 0 else { return nil }
        let volume = arguments[index + 1]
        let parts = volume.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].isEmpty, parts[1] == "Volumes", !parts[2].isEmpty, parts[2] != ".", parts[2] != ".." else { return nil }
        return EjectRequest(volume: volume, afterProcess: process)
    }
}

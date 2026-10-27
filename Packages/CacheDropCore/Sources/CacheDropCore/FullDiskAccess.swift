import Foundation

/// Whether Still has Full Disk Access (SPEC section 7). It's optional; Still works without it.
public enum FullDiskAccessStatus: Sendable, Equatable {
    case granted, notGranted
    /// No protected folder to check was found, so Still can't tell.
    case unknown
}

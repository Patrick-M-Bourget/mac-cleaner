import Foundation

/// Whether CacheDrop has Full Disk Access (SPEC section 7). It's optional; CacheDrop works without it.
public enum FullDiskAccessStatus: Sendable, Equatable {
    case granted, notGranted
    /// No protected folder to check was found, so CacheDrop can't tell.
    case unknown
}

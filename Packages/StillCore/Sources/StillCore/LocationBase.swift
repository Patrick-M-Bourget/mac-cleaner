import Foundation

/// Where a rule's locations are relative to.
public enum LocationBase: Sendable {
    /// The user's home folder.
    case home
    /// The user's own `/private/var/folders/<xx>/<id>` folder, which holds `T` (temp), `C` (cache) and `X`.
    case userFolder
}

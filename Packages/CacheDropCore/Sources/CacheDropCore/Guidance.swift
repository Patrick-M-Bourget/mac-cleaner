import Foundation

/// How a guidance-only rule (SPEC section 3) is sized and where the user manages it. Still never changes these.
public struct Guidance: Sendable {
    public enum Sizing: Sendable, Equatable {
        /// Each location's whole tree, metadata only.
        case locations
        /// Only folders with this name inside the locations (Mail keeps attachments in `Attachments` folders).
        case foldersNamed(String)
        /// Time Machine local snapshots: counted, never sized, since macOS reports no size per snapshot.
        case localSnapshots
        /// Each location's whole tree, plus the git status of the agent workspaces inside (#140).
        case agentWorkspaces
    }
    /// Where "Open …" goes.
    public enum Place: Sendable, Equatable {
        /// The first existing location, in Finder.
        case folder
        /// The owning app.
        case app(bundleID: String)
        /// A System Settings pane or other URL.
        case url(URL)
    }
    public let sizing: Sizing
    public let place: Place
    /// The place's name, as in "Open Photos".
    public let placeName: String
    public init(sizing: Sizing = .locations, place: Place, placeName: String) {
        self.sizing = sizing; self.place = place; self.placeName = placeName
    }
    public var openTitle: String { "Open " + placeName }
}

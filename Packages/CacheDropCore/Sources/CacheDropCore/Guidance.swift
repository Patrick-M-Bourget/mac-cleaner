import Foundation

/// How a guidance-only rule (SPEC section 3) is sized and where the user manages it. CacheDrop never changes these.
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
        /// The plug-in folders' trees, plus the per-product plug-in inventory (#174).
        case plugIns
        /// Every library package with this extension in the home folder and on connected volumes (#180, #178), each
        /// sized whole; nothing inside one is read. The rule's locations aren't used.
        case libraries(extension: String)
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
    /// The vendor's own help page for these steps, when there is one.
    public let learnMore: URL?
    /// Shown without Full Disk Access only when the `.app` place is installed (#245): an optional app's libraries, such as
    /// Final Cut Pro's. With access, the row appears whenever something is found.
    public let onlyWhenInstalled: Bool
    public init(sizing: Sizing = .locations, place: Place, placeName: String, learnMore: URL? = nil, onlyWhenInstalled: Bool = false) {
        self.sizing = sizing; self.place = place; self.placeName = placeName; self.learnMore = learnMore; self.onlyWhenInstalled = onlyWhenInstalled
    }
    public var openTitle: String { "Open " + placeName }
}

import AppKit
import Foundation

/// The plan's line for an owner that was running at the scan. An open app can be quit from here (#138);
/// a command-line tool isn't an app, so the user quits it and checks again.
public struct RunningOwnerNotice: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// A link button with this title that asks the app to quit, like ⌘Q.
        case quitApp(String)
        case checkAgain
    }
    public let text: String
    public let action: Action
    /// `appOpen`: the owner's app itself is open, not only its command-line tools.
    /// `stillOpen`: the app was asked to quit and is still open (unsaved work, or it refused).
    public init(name: String, appOpen: Bool, stillOpen: Bool = false) {
        if appOpen {
            text = stillOpen ? "\(name) is still open" : "\(name) is running"
            action = .quitApp("Quit \(name)")
        } else {
            text = "Quit \(name) to include this"
            action = .checkAgain
        }
    }
}

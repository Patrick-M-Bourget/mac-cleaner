import AppKit

/// The one way CacheDrop hands a place to Finder: opening a folder or link (the Trash, guidance places), or showing items selected in a Finder window.
enum Finder {
    /// Opens a folder in Finder, or a link in its app. Returns whether it opened.
    @discardableResult
    static func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    /// Shows the items selected in Finder.
    static func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }
}

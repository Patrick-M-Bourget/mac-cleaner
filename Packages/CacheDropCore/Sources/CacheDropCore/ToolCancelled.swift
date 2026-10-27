import Foundation

/// A tool action stopped because the user cancelled, with what it printed until then.
/// `started` is false when the cancel came before the tool was launched, so nothing ran.
public struct ToolCancelled: Error { public let output: String; public let started: Bool }

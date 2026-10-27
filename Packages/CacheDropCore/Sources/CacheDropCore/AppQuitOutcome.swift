import AppKit
import Foundation

public enum AppQuitOutcome: Sendable, Equatable { case quit, stillOpen, notAnApp }

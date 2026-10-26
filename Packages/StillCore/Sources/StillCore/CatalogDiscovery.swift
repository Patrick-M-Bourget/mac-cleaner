import Foundation

/// Something discovery wants the user to know about a rule, such as why it offered nothing.
public struct CatalogNote: Sendable, Equatable {
    public let ruleID: String
    public let text: String
    public init(ruleID: String, text: String) { self.ruleID = ruleID; self.text = text }
}

public struct CatalogDiscovery: Sendable {
    public let candidates: [Candidate]
    public let notes: [CatalogNote]
    /// Rules whose locations this scan looked at, in catalog order: not overridden by a setting, with their base folder and tool present.
    /// A rule in `notAccessible` counts as looked at, though nothing in it was read.
    public var scannedRuleIDs: [String] = []
    /// Rules whose locations macOS protects and Still can't read without Full Disk Access. They were not read or
    /// sized, so they are shown as not accessible, never as 0 (SPEC section 7).
    public var notAccessible: [CleanupRule] = []
    /// Locations, by rule id, that were looked at but not measured: a folder that exists but can't be read, or every
    /// location of a rule whose tool didn't answer (Docker's daemon down). What grew records them as coverage, never as 0.
    public var notMeasured: [String: Set<String>] = [:]
}

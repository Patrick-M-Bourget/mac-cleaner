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
    /// Rules whose locations macOS protects and Still can't read without Full Disk Access. They were not read or
    /// sized, so they are shown as not accessible, never as 0 (SPEC section 7).
    public var notAccessible: [CleanupRule] = []
}

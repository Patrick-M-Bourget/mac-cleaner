import Foundation

/// Whether a rule's locations can be read with the current access. A row or catalog rule declares the
/// requirement with `CleanupRule.requiresFullDiskAccess`; views show `needsFullDiskAccess` as "Not accessible".
public enum RuleAccess: Sendable, Equatable { case available, needsFullDiskAccess }

extension CleanupRule {
    /// Only a known refusal blocks the rule. When access is unknown, sizing still reports what it couldn't read.
    public func access(given status: FullDiskAccessStatus) -> RuleAccess {
        requiresFullDiskAccess && status == .notGranted ? .needsFullDiskAccess : .available
    }
}

import Foundation

/// What a planned item's space is keyed on, so the same space is offered, planned and counted once: the item itself,
/// or for a tool command, the item and the rule, since a folder a tool leaves in place (Docker's prunes, `pnpm store
/// prune`) only anchors each command's own space.
enum SpaceKey {
    /// `item` keeps apart the items one tool rule offers on the same anchor folder (each simulator runtime).
    static func of(resourceID: String, ruleID: String?, action: CleanupAction?, item: String? = nil) -> String {
        action == .tool ? resourceID + "|" + (ruleID ?? "") + (item.map { "|" + $0 } ?? "") : resourceID
    }
}

import Foundation

/// The Cleanup plan's test-facing identifier for an item, after `planItem-` and `planItemReveal-`: `<rule ID>-<name>`, like
/// `planProfile-<rule ID>-<profile>`, so same-named items of two rules stay apart (#744). When two items of one rule share a
/// name (two `Setup.dmg` files in different Downloads folders), each also ends in `-<path tag>` (#749). Display names are
/// unchanged; the tag keeps a short identifier within the 128 characters an XCUITest subscript query allows.
public enum PlanItemIdentifier {
    /// The names more than one of `names` has.
    public static func repeatedNames(_ names: some Sequence<String>) -> Set<String> {
        var seen = Set<String>(), repeated = Set<String>()
        for name in names where !seen.insert(name).inserted { repeated.insert(name) }
        return repeated
    }

    /// `<rule ID>-<name>`, plus `-<path tag>` when `name` is one of the rule's `repeated` names.
    public static func make(ruleID: String, name: String, path: String, repeated: Set<String>) -> String {
        ruleID + "-" + name + (repeated.contains(name) ? "-" + pathTag(path) : "")
    }

    /// Eight hex digits of the path's 32-bit FNV-1a hash: the same every launch, unlike Swift's seeded `Hasher`, so a journey
    /// can work it out from its fixture's path.
    public static func pathTag(_ path: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for byte in path.utf8 { hash = (hash ^ UInt32(byte)) &* 0x01000193 }
        return String(format: "%08x", hash)
    }
}

import Foundation

#if DEBUG
/// Made-up items for the Design gallery's review and Trash sheets (#794). Debug only: nothing on disk is read, and they never
/// reach a check or a run.
extension Candidate {
    /// An item `rule` found at `url`, sized `bytes`; `itemName` and `toolItem` as a model or a simulator has them.
    public static func gallerySample(rule: CleanupRule, url: URL, bytes: Int64, itemName: String? = nil, toolItem: String? = nil) -> Candidate {
        var item = Candidate(ruleID: rule.id, action: rule.action, url: url, resourceID: "gallery:" + url.path, isDirectory: url.hasDirectoryPath,
                             toolURL: nil, volumeID: nil, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: bytes, allocatedBytes: bytes,
                             sizeComplete: true, lastUsed: nil, observedAt: Date(timeIntervalSince1970: 0), profile: nil)
        item.itemName = itemName
        item.toolItem = toolItem
        return item
    }
}

extension TrashItem {
    /// An item at the top of the Trash at `url`, sized `bytes`.
    public static func gallerySample(url: URL, bytes: Int64) -> TrashItem {
        TrashItem(url: url, resourceID: "gallery:" + url.path, modifiedSeconds: 0, modifiedNanoseconds: 0, logicalBytes: bytes, allocatedBytes: bytes,
                  volumeID: nil)
    }
}
#endif

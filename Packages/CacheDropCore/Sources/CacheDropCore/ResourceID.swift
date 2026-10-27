import Darwin

extension stat {
    /// "dev:ino": an item's identity on disk, as candidates and journal records keep it.
    var resourceID: String { "\(st_dev):\(st_ino)" }
}

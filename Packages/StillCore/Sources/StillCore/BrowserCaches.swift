import Foundation

/// Browser cache rules (#101). Each rule allowlists the cache folders inside every profile and nothing else;
/// the profile's own data (logins, cookies, history, site storage, sessions, settings) is never a location,
/// and its names are protected in case a cache folder ever holds or sits under one.
///
/// Only layouts confirmed from the browser's own documentation or source are listed. Safari, Arc and Edge are not:
/// Apple, The Browser Company and Microsoft don't document where their macOS caches live.
public enum BrowserCaches {
    static let consequence = "Permanently removed. Logins, cookies, history, site data and settings are kept. The cache refills as you browse; pages may load more slowly at first."

    /// Chromium on macOS keeps a profile's caches under ~/Library/Caches, at the profile's path relative to
    /// ~/Library/Application Support (docs/user_data_dir.md; `chrome::GetUserCacheDirectory`). The HTTP cache is
    /// `<profile>/Cache` and generated code is `<profile>/Code Cache` (`kCacheDirname`, StoragePartitionImpl).
    static func chromium(id: String, title: String, dataDir: String, bundleIDs: [String], executables: [String]) -> CleanupRule {
        CleanupRule(id: id, category: .browser, title: title,
                    detail: "Cached images, files and scripts, per profile.", consequence: consequence,
                    regen: .cache, action: .delete,
                    locations: ["Library/Caches/\(dataDir)/*/Cache", "Library/Caches/\(dataDir)/*/Code Cache"],
                    owner: RuleOwner(name: title, bundleIDs: bundleIDs, executables: executables),
                    protectedNames: chromiumProfileData)
    }

    /// Codex's Chrome protected-data list, plus the rest of what a Chromium profile keeps.
    static let chromiumProfileData = ["Cookies", "Network", "History", "Login Data", "Login Data For Account", "Web Data", "Preferences",
                                      "Secure Preferences", "Bookmarks", "Sessions", "Current Session", "Current Tabs", "Last Session", "Last Tabs",
                                      "Local Storage", "Session Storage", "IndexedDB", "Service Worker", "File System", "databases",
                                      "Extension State", "Extensions", "Local Extension Settings", "Sync Data", "Local State", "Downloads"]

    public static let rules: [CleanupRule] = [
        chromium(id: "chrome-cache", title: "Google Chrome", dataDir: "Google/Chrome", bundleIDs: ["com.google.Chrome"],
                 executables: ["Google Chrome", "Google Chrome Helper*"]),
    ]
}

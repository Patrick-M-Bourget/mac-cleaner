import Foundation

/// Browser cache rules (#101). Each rule allowlists the cache folders inside every profile and nothing else;
/// the profile's own data (logins, cookies, history, site storage, sessions, settings) is never a location,
/// and its names are protected in case a cache folder ever holds or sits under one.
///
/// Only layouts confirmed from the browser's own documentation or source are listed. Safari, Arc and Edge are not:
/// Apple, The Browser Company and Microsoft don't document where their macOS caches live. Arc and Edge are Chromium,
/// so once their data folder is confirmed each is one `chromium(...)` line.
public enum BrowserCaches {
    static let consequence = "Permanently removed. Logins, cookies, history, site data and settings are kept. The cache refills as you browse; pages may load more slowly at first."

    /// Chromium on macOS keeps a profile's caches under ~/Library/Caches, at the profile's path relative to
    /// ~/Library/Application Support (docs/user_data_dir.md; `chrome::GetUserCacheDirectory`). The HTTP cache is
    /// `<profile>/Cache` and generated code is `<profile>/Code Cache` (`kCacheDirname`, StoragePartitionImpl).
    static func chromium(id: String, name: String, dataDir: String, bundleIDs: [String], executables: [String]) -> CleanupRule {
        CleanupRule(id: id, category: .browser, title: name + " cache",
                    detail: "Cached images, files and scripts, per profile.", consequence: consequence,
                    regen: .cache, action: .delete,
                    locations: ["Library/Caches/\(dataDir)/*/Cache", "Library/Caches/\(dataDir)/*/Code Cache"],
                    owner: RuleOwner(name: name, bundleIDs: bundleIDs, executables: executables),
                    protectedNames: chromiumProfileData, layoutOverrides: chromiumOverrides(dataDir: dataDir, domain: bundleIDs[0]))
    }

    /// A moved disk cache (`DiskCacheDir` policy, `browser.disk_cache_dir` in Local State) or user data folder
    /// (`UserDataDir`) means the default folders aren't the live cache. Policies can be set per user, by an
    /// administrator, or by device management.
    static func chromiumOverrides(dataDir: String, domain: String) -> [LayoutOverride] {
        let policies = ["Library/Preferences/\(domain).plist", "Library/Managed Preferences/\(domain).plist",
                        "/Library/Managed Preferences/\(domain).plist", "/Library/Managed Preferences/$USER/\(domain).plist",
                        "/Library/Preferences/\(domain).plist"]
        return policies.flatMap { [LayoutOverride.key(file: $0, keyPath: "DiskCacheDir"), .key(file: $0, keyPath: "UserDataDir")] }
            + [.key(file: "Library/Application Support/\(dataDir)/Local State", keyPath: "browser.disk_cache_dir")]
    }

    /// Codex's Chrome protected-data list, plus the rest of what a Chromium profile keeps.
    static let chromiumProfileData = ["Cookies", "Network", "History", "Login Data", "Login Data For Account", "Web Data", "Preferences",
                                      "Secure Preferences", "Bookmarks", "Sessions", "Current Session", "Current Tabs", "Last Session", "Last Tabs",
                                      "Local Storage", "Session Storage", "IndexedDB", "Service Worker", "File System", "databases",
                                      "Extension State", "Extensions", "Local Extension Settings", "Sync Data", "Local State", "Downloads"]

    /// What a Firefox profile keeps besides its caches. None of it lives in the cache folder; this guards the folder.
    static let firefoxProfileData = ["cookies.sqlite", "places.sqlite", "favicons.sqlite", "logins.json", "key4.db", "cert9.db",
                                     "formhistory.sqlite", "permissions.sqlite", "webappsstore.sqlite", "prefs.js", "user.js",
                                     "sessionstore.jsonlz4", "sessionstore-backups", "storage", "extensions", "bookmarkbackups"]

    public static let rules: [CleanupRule] = [
        chromium(id: "chrome-cache", name: "Google Chrome", dataDir: "Google/Chrome", bundleIDs: ["com.google.Chrome"],
                 executables: ["Google Chrome", "Google Chrome Helper*"]),
        // Firefox puts each profile's local folder under ~/Library/Caches/Firefox/Profiles (nsXREDirProvider, the
        // Caches folder on macOS) and its HTTP cache in `<profile>/cache2` (Firefox source docs, networking/cache2).
        // Release, Developer Edition and Nightly share that folder, and every channel's binary is `firefox`.
        CleanupRule(id: "firefox-cache", category: .browser, title: "Firefox cache",
                    detail: "Cached images, files and scripts, per profile.", consequence: consequence,
                    regen: .cache, action: .delete, locations: ["Library/Caches/Firefox/Profiles/*/cache2"],
                    owner: RuleOwner(name: "Firefox", bundleIDs: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"],
                                     executables: ["firefox", "plugin-container"]),
                    protectedNames: firefoxProfileData,
                    // A pref that moves the cache (`browser.cache.disk.parent_directory`) leaves cache2 here stale or reused.
                    layoutOverrides: ["prefs.js", "user.js"].map {
                        .text(file: "Library/Application Support/Firefox/Profiles/*/\($0)", contains: "browser.cache.disk.parent_directory")
                    }),
    ]
}

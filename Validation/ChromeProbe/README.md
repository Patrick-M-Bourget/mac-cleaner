# Chrome cache qualification probe

**Decision: Chrome mutation unsupported; guidance only.** No browser/version is on the production positive allowlist. `qualifiedBrowserVersions` is intentionally empty. This harness has no deletion API and cannot qualify real Chrome cleanup by itself.

## Reproduce

Requires macOS 14+, Swift 6. From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Validation/ChromeProbe
```

Tests create and remove their own temporary `StillChromeProbe-<UUID>` trees only. They never enumerate user Library folders, read personal Chrome metadata, launch an installed browser, or request credentials. The library's explicit fixture scope is a guard against accidental invocation, not proof that arbitrary caller-supplied data is disposable.

Four public-seam tests passed on macOS 27.0.1 (26A434), Apple silicon, Swift 6.4. They include nine synthetic environment scenarios. Red/green cycles established missing capability API, missing environmental guidance and absent fixture inspection before implementations passed. The package compiles for minimum macOS 14; no macOS-14/Intel runtime qualification is claimed.

## What is and is not proven

| Boundary | Observed evidence | Production qualification |
|---|---|---|
| Version allowlist | Unknown version receives unsupported | No Chrome versions tested |
| Custom/multiple profiles | Explicit synthetic manifest finds two profile asset groups, including nested custom names | Real profile/configured root discovery untested |
| Asset groups | `fixture-only-1` positive allowlist contains only `Cache/Cache_Data` | Fixture name is not a qualified Chrome storage contract |
| Shared ownership | Unknown shared owners blocks capability | Real shared cache ownership identification untested |
| Browser/helpers, writes, reopen, denial | Nine injected states fail closed when activity/ownership uncertain | Native process identity, helper association, race closure and real access denial untested |
| Symlink substitution | Actual disposable cache directory symlink rejected | Check/use races still unqualified; no mutation exists |
| Protected data | Real disposable sentinel bytes unchanged after fixture inspection | No real browser cleanup or semantic protected-data validation |
| Relaunch | No browser launched or cache mutated | Successful relaunch not established |

Sentinels cover Cookies, Login Data (credentials), History, Web Data (autofill), Downloads, Sessions, Local Storage, IndexedDB and Service Worker/CacheStorage. The inspection returns only candidate group paths; these data remain excluded. This proves the read-only harness leaves its fixtures alone, not that deleting real caches preserves a functioning profile. It neither hashes nor reads personal files.

The capability input is an **observation contract**, not a native detector: passing `browserOrHelperRunning: false` cannot establish inactivity. All reports remain unsupported even with apparently healthy inputs. No path is eligible merely because it contains Chrome, Default, Profile or Cache. Fixture profile paths are explicit, bounded, deduplicated and rejected on traversal or symlink resolution changes. No production shared caches are inferred.

## Primary-source findings

[Chromium's user-data-directory documentation](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md) describes profile paths, browser branding/channel differences and explicit `--user-data-dir` overrides. On macOS, cache roots beneath Library/Application Support map to the corresponding Library/Caches subtree; other profile locations use their own profile root. Thus a custom profile cannot be mapped safely from its last directory component alone.

[Chromium UserDataDir policy](https://chromium.googlesource.com/chromium/src/+/HEAD/components/policy/resources/templates/policy_definitions/Miscellaneous/UserDataDir.yaml) can override command-line root configuration. Configured roots, channel/product identity and ownership must be established together. These documents do not qualify `Cache/Cache_Data` deletion for a particular released browser build.

## Required future disposable qualification

1. Use a separate disposable OS account and explicit disposable Chrome for Testing profiles; record exact browser build, OS, binary identity/channel, policy, configured user-data and derived cache roots. No personal profile import or sync login.
2. Generate disposable online asset caches and protected data, across custom/multiple profiles and any observed shared group. Record ownership of each cache; omit groups with unresolved sharing. Create a version-specific positive manifest from the tested build rather than matching generic basenames.
3. Verify browser and associated helper identity and ownership using native observations. Exercise active writes, helpers surviving windows, access denial, reopen between review/execution and symlink/identity swaps. Uncertain or stale observations must block; a one-time process-name search is insufficient. Resolve how mutation can remain safe against reopen races before enabling it.
4. Only in those disposable profiles, mutate exact independently qualified asset groups under a reviewed executor. Compare protected sentinels and semantic state; relaunch and verify sessions, history, credentials, cookies, offline/site storage and downloads remain available. Record cache regeneration and race outcomes.
5. Populate production version allowlist only after the entire matrix passes; otherwise retain unsupported guidance. Tests here intentionally cannot flip production support.

This ticket's deliverable is a reproducible conservative capability decision. Native cache mutation and relaunch acceptance remain unmet gates for the downstream cleanup adapter, not implied successes.

# Chrome cache qualification probe

**Decision: Chrome mutation unsupported; guidance only.** No browser/version is on the production positive allowlist. `qualifiedBrowserVersions` is intentionally empty. The Swift fixture library has no deletion API. The separate hosted-only experiment below can remove exact generated owned-profile asset leaves, without qualifying production Chrome cleanup.

## Reproduce

Requires macOS 14+, Swift 6. From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Validation/ChromeProbe
```

Tests create and remove their own temporary `StillChromeProbe-<UUID>` trees only. They never enumerate user Library folders, read personal Chrome metadata, launch an installed browser, or request credentials. The library's explicit fixture scope is a guard against accidental invocation, not proof that arbitrary caller-supplied data is disposable.

Four public-seam tests passed on macOS 27.0.1 (26A434), Apple silicon, Swift 6.4. They include nine synthetic environment scenarios. Red/green cycles established missing capability API, missing environmental guidance and absent fixture inspection before implementations passed. The package compiles for minimum macOS 14; no macOS-14/Intel runtime qualification is claimed.

## What the original Swift fixture suite proves

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

## Genuine owned Chrome experiment (hosted-only)

`genuine.mjs` adds an explicit, bounded native-browser experiment. It refuses
outside GitHub Actions/macOS/arm64 and requires Node 22+, Python 3, at least 1 GiB
free, and the explicitly downloaded **Chrome for Testing 156.0.8078.47** bundle.
It does not launch installed Chrome or use Launch Services. Provision the
[exact official archive](https://storage.googleapis.com/chrome-for-testing-public/156.0.8078.47/mac-arm64/chrome-mac-arm64.zip)
into an owned runner-temporary directory with `provision.py`; record the archive SHA-256 and
[version manifest](https://googlechromelabs.github.io/chrome-for-testing/156.0.8078.47.json)
as run artifacts. Never install it into `/Applications` or run its updater.

```sh
python3 Validation/ChromeProbe/provision.py "$RUNNER_TEMP/chrome-probe"
node Validation/ChromeProbe/genuine.mjs \
  "$RUNNER_TEMP/chrome-probe/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  "$RUNNER_TEMP/chrome-probe/evidence/report.json"
```

The script verifies the exact independently observed official archive byte/hash pin, version and executable hash, and records native signature verification results. This exact vendor archive omits CodeResources: strict bundle verification fails; no sealed Developer ID bundle claim is made. This hosted-only development experiment may directly spawn those untouched official bytes if the OS accepts them. It never re-signs, changes quarantine/xattrs, bypasses Gatekeeper or changes OS policy. A fresh UUID tree contains an explicit custom user-data
root and two sequential native profiles, `Default` and `Profile 1`. A server bound
only to `127.0.0.1` generates a 512 KiB asset and disposable persistent cookie,
local storage, IndexedDB and CacheStorage values. CDP observes the owned browser
and helper process types. Browser background networking, updates, extensions,
sync and default-browser prompts are disabled through command-line flags;
mock keychain avoids real keychain access. **Flags are not a network trace**, so
this does not claim all outbound traffic is absent. No login or personal profile
is imported and no credentials are collected.

The public experiment checks first-load asset requests, a warm relaunch's actual
disk-cache hit, refusal while its browser is active and after reopening, and
closed-only removal of the exact generated `Cache/Cache_Data` regular leaves.
`remove-owned-cache.py` opens directory descriptors without following links and
checks each manifest leaf's identity, modification time, type and link count.
It never recursively deletes a supplied directory. Generated protected browser
files are hashed immediately before/after removal, and persistent cookie/local
storage/IndexedDB/offline response semantics are checked after genuine relaunch.
The fixture server must observe another asset request and Chrome must regenerate
cache files. Browser shutdown uses `Browser.close`, with termination restricted
to the fresh detached process group it launched; it never searches/kills by name.
The ephemeral runner performs final disposal. Reports contain aggregate evidence
and synthetic relative profile paths, never personal paths or browsing data.

Local checks that launch no browser:

```sh
node --check Validation/ChromeProbe/genuine.mjs
python3 Validation/ChromeProbe/test_owned_cache.py
```

Two public helper-command tests exercise an exact owned leaf versus a protected
sibling, symlink substitution, replaced identity and an escaping manifest. The
first was red when the helper command was absent, then green with the guarded
operation. These are helper safety checks, not Chrome qualification.

**Evidence status:** the genuine experiment is implemented but awaits its first
hosted execution. Do not interpret the fixture tests or a syntax check as a native
browser pass. The report's `passed` field is set only after both profiles finish.

This is deliberately **not** the production executor. Its owned process lifetime
and fresh UUID root do not establish native inactivity for arbitrary installed
browsers, shared ownership, enterprise policies, OS access denial or closure of
external reopen/leaf-swap races. Empty native Login Data/Web Data byte preservation
does not establish authenticated sessions, credentials or autofill semantics.
Downloads, history/session restoration, real offline applications, minimum OS and
Intel remain separate gates. The production version allowlist stays empty and
#19 receives no mutation authority from this partial experiment.

Provisioning is hosted-only and refuses an existing output directory. Download time/size, archive entries and unpacked size are bounded; member traversal, escaping symlinks, duplicate paths and files beneath archive symlinks are rejected before `ditto` extraction. A 3 GiB initial budget and unpacked-size-plus-1-GiB check guard storage. `provision.json` distinguishes the observed archive digest from a publisher checksum and includes signature, OS, Python and CI provenance. No downloaded archive is added to Git.

Flags follow [Google’s Chrome launcher reference](https://github.com/GoogleChrome/chrome-launcher/blob/main/docs/chrome-flags-for-tools.md) and [Chromium’s macOS development instructions](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/mac_build_instructions.md); these describe test switches rather than a production cleanup contract.

The official 156.0.8078.47 mac-arm64 archive was independently downloaded over HTTPS and observed as **194,932,023 bytes**, SHA-256 **`ad7f2b49a4dc679af286b1b1b386670d93ca7868079f69012d21ba0ac8293df3`**. Both are required before extraction/execution. This is a reproducibility pin derived from our download, not a Google-published checksum. The ZIP has 673 members and no CodeResources. First hosted attempt [40003124836](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40003124836) stopped before browser launch at strict bundle verification; the refined experiment preserves that failure prominently while permitting only this exact unchanged vendor artifact on ephemeral GitHub-hosted runners. Both provisioning and runtime require `RUNNER_ENVIRONMENT=github-hosted`; self-hosted runners are refused. Production vendor trust and distribution qualification remain separate gates.

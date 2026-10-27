# Still: reset plan

Execution order is the tickets in #75. The phase sections below are background; the **Decisions** section at the end is binding.

## Context
Codex has worked on Still for 4 days. The result:
- 681 commits, about 12k lines of app code, 132 MB of docs and evidence, and 37% of CI runs failing.
- On the user's Mac the only cleanup that actually works is Downloads → Trash.
- Chrome cleanup is locked to exact OS/Chrome builds the user doesn't run. Xcode cleanup is locked to one Xcode build and is not connected to the UI. Homebrew, pip and Docker are locked to single versions or disabled.
- The real 53 GB from the 10-24 field scan came from folders the app never looks at.

**Goal:** a feature-complete Still as fast as possible, built by Claude Code with Codex removed from the project, covering far more than Downloads.

**How:** keep the solid foundations (scanner, Trash executor, journal, design system, shell). Replace the one-off cleanup code for each source with one shared cleanup layer driven by a data catalog. Delete the paperwork machinery.

## Phase 0: Remove Codex, set up the workshop (½ session)
1. **User:** stop any Codex sessions or automations on this repo.
2. **Canonical checkout:** `~/Workspace/mac-cleaner`, a new clone.
   - Done 2026-10-26. Codex's notes and 2 stashes are backed up as patches in `~/Workspace/mac-cleaner-codex-archive`. The user deleted Codex's 8.5 GB cache.
3. **Local builds:** use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Xcode 27.1 is installed; only `xcode-select` points at CommandLineTools). Every build and UI check happens locally. No more push-and-wait on CI.
4. **Agent harness:** the repo already uses the `docs/agents/` layout (as eq1 and comp1 do), so it keeps it. A thin `CLAUDE.md` replaces Codex's `AGENTS.md`.
5. **Issues:** close all 25 open `ready-for-agent` issues as superseded. Open new ones from this plan, one per phase step.

## Phase 1: Diet (1 session, one PR per bullet)
- **Docs:** the 23 control docs and 61 validation reports go to an `archive/codex-era` tag. Then remove them from `main`. That removes about 130 MB going forward; history is left alone. *(Delete: needs your approval.)*
- **The new authority** is the prototype (`docs/visual/preview.html`) plus one `docs/SPEC.md` of 300 lines or less. A new `DECISIONS.md` grows only from our grilling.
- **Code to delete:** the `Validation/*` probe packages, the version gates (listed below), the ~15 `--ui-test-*`/fixture flags spread through views, and `--future-milestones`. Features are either in the product or deleted.
  - Version gates: `ChromeCache.swift:33-44`, `NativeXcodeBuildEnvironment.swift:53-57`, `XcodeDerivedDataMapping.swift:48`, `DockerInventory.swift:20,133`, `PipInventory.swift:16,59`, `HomebrewPreview.swift:37`.
- **CI:** replace the 844-line `native.yml` with one job: `swift test` plus an app build plus a short smoke UI suite, on PRs only. *(CI change, L3: requires your approval.)*
- **UI tests:** cut them to a small smoke set, about 5 journeys. Delete the screenshot-ledger tests.

## Phase 2: Shared cleanup core (2 sessions)
This replaces the bespoke Chrome/Xcode/pip/Docker/Homebrew paths with one model in CacheDropCore:
```
CleanupRule (data): id, category, path patterns, owner app bundle id(s),
  regen class (cache | download | build | model | installer | user file),
  action (.trash | .delete | .evict | .tool(cmd) | .guidance), risk copy
Candidate: rule + url + logical/allocated size + lastUsed + inUse state
Preflight per candidate: still exists, unchanged, owner app not running, not excluded, not protected
Executor: one journal, per-item result, cancel, measure free space before/after each item
```
- **Reuse:**
  - `TrashExecutor`, `SQLiteCleanupJournal`, `CleanupRecovery` and `CleanupTargetValidation`: generalize these from "Downloads + Trash" to "any Candidate + action".
  - `BoundedTool` for `.tool` actions.
  - `ScopeRegistry` and `Exclusions` as they are.
- **Running-app check:** via `NSRunningApplication`, replacing the exact-version checks.
- **Results:** report the free space measured around each action, not the predicted bytes. That handles APFS clones honestly (the Chrome code-sign clones showed 52 GB but freed only 2 GB).
- **Scanner:**
  - Keep `FolderScanner` for user-chosen folders.
  - Add a fast **known-locations sizer** that sizes only the catalog's paths, so there's no whole-disk walk.
  - Raise or remove the 100k-entry and 30 s caps for those paths.
- **`PlanDraft`:** drop its `downloadsRoot` coupling. A plan becomes just a list of Candidates.

## Phase 3: Categories (feature-complete scope)
Each category is a catalog entry plus tests on temp-folder fixtures. Most need no new UI.

**Tier A: proven on your Mac, highest value**
| Category | Action |
|---|---|
| Developer caches: npm, Yarn, pnpm, uv, pip, Cargo, Gradle, CocoaPods | delete (cache dirs); pnpm and uv through their own commands (Decisions 23, 44) |
| Homebrew | `brew cleanup -s` + cache dir |
| Xcode: all of DerivedData, unavailable simulators (`simctl delete unavailable`), old iOS DeviceSupport | delete / tool |
| Browser caches: Chrome, Safari, Firefox, Arc, Edge (cache dirs only; logins, cookies and history are never touched) | delete, browser must be closed |
| Chrome `code_sign_clone` under `/private/var/folders` (keep in-use + newest) | delete |
| App updater downloads (Sparkle, vendor updaters) | delete |
| Per-app `~/Library/Caches` (owner not running; known load-bearing caches such as ccache and our own tools skipped) | delete |
| Logs and crash reports (user) | delete |
| Downloads: installers (.dmg/.pkg/.zip) and old large files | Trash |

**Tier B: needs care**
- **iCloud local copies:** `evictUbiquitousItem`, skipping files that are pinned, not yet uploaded or in conflict.
- **ML models:** Hugging Face and Ollama; show their last use.
- **App VM and disk images:** e.g. an expanded image sitting next to its compressed source.
- **Docker:** `docker system df`, then a chosen prune.
- **Large and old files explorer:** reuse `StorageExplorer`; Trash only.
- **Guidance only:**
  - iOS backups, Mail and Messages attachments, Photos, Time Machine local snapshots, release archives.
  - Purchased content such as audio plug-ins: shown, owner's call.

**Tier C: non-cleanup features**
- **Reuse existing code:** What grew (`GrowthHistory*`), storage alerts plus menu bar (`Still/Packages/StorageAlerts`), exclusions, history, diagnostics export.
- **Polish:** these come back once Tier A ships, after a check that each one still earns its place.

**Out of scope (unchanged):** uninstaller, duplicates, treemap, automatic cleanup.

## Phase 4: Product completeness (1–2 sessions)
- **Onboarding:** an optional Full Disk Access flow. Limited coverage is shown honestly.
- **Overview:** restored to the prototype, including the storage breakdown bar and "Recommended: up to X GB" driven by the catalog.
- **Settings:** scan locations, exclusions, alerts, reset.
- **App shell:** split the 963-line `StillApp.swift` along its `Destination` boundaries.
- **Distribution:** signing, notarization, DMG. This needs your Developer ID *(L3: your call on timing)*.

## Working rules (replace the Codex process)
- **PR size and flow:** about 500 lines or fewer, one logical change each. `swift test` and a local build before every commit. You do the smoke test before merging.
- **Evidence and visuals:** no committed screenshots or evidence reports. Visual checks happen locally and get shared on request.
- **Product principles kept from the PRD:**
  - Nothing preselected; explicit review with consequences.
  - Recheck before acting.
  - Trash for user files. The app never empties the Trash.
  - Never touch logins/cookies, the Photos/Mail/Messages databases, or other users' data.
  - Unknown is shown as unknown, never as 0.
- **Process rules dropped:** exact-version qualification, approved test boundaries, parity ledgers, and session handoff essays.

## Order and rough size
Phase 0 → 1 → 2 → Tier A (2–3 sessions) → Overview/onboarding → Tier B → Tier C → distribution. At the end of Tier A you have a cleaner that would have recovered your 53 GB. That's the first point to stop and use it for real (old issue #14).

## Verification
- **Unit:** `swift test --package-path Packages/CacheDropCore`, with temp-folder fixtures for every catalog rule (discover → preflight → execute → result), plus a case where the owner app is "running" and is refused.
- **App:** `DEVELOPER_DIR=… xcodebuild -project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop build test` locally, with the smoke UI set.
- **Real-world check:** a run on your Mac compared against a manual `du`/`df` survey, the field note's method. The pass bar: it finds the categories the field scan found, and its measured freed space matches `df`.

## Decisions (grilled 2026-10-26)
1. Salvage the core; replace bespoke adapters with one catalog-driven layer.
2. Target: shareable (Developer ID + notarization), but signing is gated to a later "shareable" milestone. M1 = works on the user's Mac.
3. Regenerable items (caches, build output, updater downloads, leaked app copies) are deleted permanently; user files, models, VM images and installers go to Trash.
4. User-owned scope only, including the user's own /private/var/folders entry. Never prompt for admin. Full Disk Access is an optional "see more".
5. The prototype (full mode) is the UI authority again, plus one short SPEC.md for behavior.
6. Tag main as `archive/codex-era`, then delete the control docs, validation reports and PNGs from main. Keep the prototype, PRD and field note.
7. **M1 done when:** on the user's Mac the app finds the field-scan categories (Chrome code-sign clones, developer caches, updater downloads, Xcode, browser caches, models/VM images, old Downloads), cleans what the user picks, and the freed space it reports matches `df`.
8. A dry-run switch is used for the first real passes. Tests only touch temp fixtures. *Superseded by 27.*
9. Codex's protected-data lists (Chrome logins/cookies/history/profiles; Xcode source/archives/dSYMs/products) become catalog "protected" rules. Their version gates are dropped.
10. CI becomes one PR job (unit tests + app build). L3 approved.
11. Export the Codex stashes as patches and back up its notes. The user deletes the Codex cache. Close the 25 open issues as superseded and open new ones from this plan.
12. What grew and alerts code stays in the tree but unwired; the flag is removed. Revisit after M1. *Superseded by 30 (alerts) and #119/#127 (Storage trends).*
13. iCloud is inventory only in M1; eviction comes right after.
14. Workflow: push branch → PR → CI → user smoke-tests → Claude merges.
15. Delete the 14 Codex-era UI test files and replace them with about 5 smoke journeys. Adapt the unit tests.
16. The dry run is a visible "Preview only (don't change anything)" setting, on by default in M1 builds. *Superseded by 27.*
17. "Matches `df`" means within 10% or 1 GB (whichever is larger) of the `df` change measured around the whole run.
18. "Old": Downloads installers at any age; other Downloads files at 500 MB or more and not opened in 90 days. iOS DeviceSupport keeps the 2 newest versions per platform.
19. Ollama models are removed with `ollama rm` (tool action), an exception to Decision 3. Hugging Face models still go to Trash.
20. A command-line tool's cache is refused while that tool's process is running (process-name check).
21. Caches are cleaned by deleting their folder. Tool commands are used only for Homebrew, simulators and Ollama.
22. Everything inside Xcode DerivedData, products and dSYMs included, is regenerable. Only Archives and anything outside DerivedData are protected.
23. The pnpm store is cleaned with `pnpm store prune` (tool action), never deleted: with pnpm's global virtual store, projects link into it. pnpm's metadata cache is still deleted.
24. The large and old files explorer lists files of 500 MB or more OR not opened in 90 days (you choose each file); Downloads keeps AND (Decision 18).
25. **Calm design pass (2026-10-26).** Still should feel simple and elegant, not overbearing. Rules for every screen:
    - one explanation per screen: no toolbar subtitles and no bottom-bar footnotes, except notes that report state, such as a running cleanup;
    - no long paths in rows: name plus a short location, full path in the inspector or a tooltip;
    - one short line of detail per row; consequences appear once, in the review sheet;
    - the cleanup plan groups rules by catalog category, matching Overview, with "Choose items" inside;
    - per scan, a category with one rule and one item has only its checkbox, one rule with several items lists the items without a rule row, and two or more rules keep their rule rows;
    - under "Potential space released", one secondary line says "X of this goes to Trash", only when the selection includes Trash-bound items;
    - Overview hides 0-byte categories, shows the 5 largest with "Show N more", and folds not-accessible locations into one "needs Full Disk Access · Learn more" line;
    - App-managed storage is one Overview row that leads to its own quiet page;
    - the review sheet is grouped by consequence;
    - results show outcomes first, with details on demand;
    - History is a compact list, and local records live only in Locations & access;
    - Full Disk Access is one settings row;
    - appearance follows the system, with an override in a Settings window;
    - Storage trends keeps only its retention footnote.
26. **Storage trends (2026-10-26, #127).** The growth page is named Storage trends and sits third in the sidebar.
27. **One-button cleanup (2026-10-26, #136; supersedes 8 and 16).** The review sheet is the preview: it lists exactly what will happen, and its one **Clean up** button runs it for real. Preview only is no longer a mode in the plan. "Dry run (nothing changes)" is a switch in the Settings window, off by default, for testing; with it on, the whole flow runs and nothing changes. Tests still touch only temp fixtures; UI journeys that assert nothing changed turn the dry run on.
28. **Recommended plan (2026-10-26, #137).** Nothing is preselected unless you ask for the recommended plan. Overview's **Recommended plan · X · Review** chooses, in StillCore (`RecommendedPlan`), only items that rebuild themselves and are deleted: caches, build data, updater downloads, logs and leaked app copies, that pass the checks now. Never anything going to Trash, iCloud copies, models or VM images, Docker, tool actions (even for caches), guidance, user files, anything a check would refuse or whose size is unknown. It opens the review sheet, which lists every item; Clean up runs it. Two clicks from Overview.
29. **Quit a blocking app when you ask (2026-10-26, #138).** SPEC section 2 changes from "never force-quits" to "never force-quits, and quits apps only when you ask". When an open app blocks a rule, the plan line reads "<App> is running · Quit <App>". The link sends `NSRunningApplication.terminate()` (never `forceTerminate`) through the `AppQuitting` seam, waits up to 15 seconds for the app to go, then checks the running owners again; an app that stays open (unsaved work, or it refused) reads "<App> is still open". A command-line owner, or an app whose only running part is its tools (Xcode's `xcodebuild`), reads "Quit <tool> to include this · Check again". Debug UI test runs never ask a real app to quit.
30. **Menu bar item and low-space alerts (2026-10-26, #131; supersedes 12 for alerts).** A `MenuBarExtra` shows free space ("38 GB free": whole GB from 10 GB, one decimal below, TB from 1,000 GB; only a symbol when capacity is unknown). Its menu: Open Still, Scan again, Review recommended plan… (only when Overview offers one), Settings…, Quit. It is shown by default; "Show free space in the menu bar" in the Settings window hides it. While it is shown, closing the window keeps Still running, so the item stays; capacity is reread every 5 minutes for it, metadata only. Low-space alerts reuse the StorageAlerts package and controller, are off by default and live in the Settings window (threshold, 24-hour snooze, one status line), never in the sidebar; the Storage alerts page is gone. Turning alerts on is the only time Still asks for notification permission. Alerts are capacity checks only, never background scans. Start at Login is its own toggle in the same window.
31. **Smart clean (2026-10-26, #141; amends 28 and 30).** The recommended plan moves to its own sidebar page, **Smart clean**: Overview, Smart clean, Cleanup plan, Storage trends, History, then Locations & access, with ⌘1–⌘6 in that order. The page has the header "Smart clean · X ready to clean", one line ("Rebuildable caches, build files and logs. Never your files."), the recommended items grouped by category with one line each and its size (a line per rule, or per app or profile when a rule groups them; a category with one line has only its checkbox), all ticked and each untickable, a short "Not included" note (Trash items, models, iCloud copies, your files, anything a running app is using) whose entries link to the Cleanup plan, and one **Clean up** that opens the same review sheet. The items still come from StillCore's `RecommendedPlan`, with the full checks at that click. Smart clean keeps its own selection (StillCore `CleanupSelections`): building or running it never changes the Cleanup plan's selection, and the plan never changes it; a finished run clears only the selection it came from. Overview's Recommended plan button is gone; the "Recommended for review" header has a quiet "Smart clean · X ›" link. The menu bar's "Review recommended plan…" becomes "Smart clean…" and opens the page.
32. **The app is CacheDrop (2026-10-26, #149).** "Still" was a placeholder. Users see CacheDrop everywhere: `CacheDrop.app`, bundle ID `com.patrickbourget.CacheDrop`, window title, sidebar header, menus, notifications and copy. State lives in `~/Library/Application Support/CacheDrop` and the new defaults domain. On first launch, StillCore's `LegacyStillMigration` copies Still's state folder and preferences into CacheDrop's: copy, never move; only while CacheDrop has no state folder; existing preferences are never overwritten; on any failure nothing changes and the next launch tries again; while Still is running (or that can't be checked) it waits for a later launch, and the cleanup journal is copied with SQLite's backup API so records still in its write-ahead log come along (#151); completion is recorded (`CacheDrop.migratedFromStill`) so it runs once. Start at Login is not carried over: macOS registered Still's app, so it is turned on again in Settings. Remembered folders whose security-scoped bookmarks don't resolve for the new bundle show "Choose again". Both apps' folders and bundle IDs stay protected (`Protection`). Internal names (`StillCore`, `StillDesign`, targets, `STILL_TEST_*`, defaults keys, notification identifiers, the repo) are unchanged until #150.
33. **SwiftPM's dependency clones (2026-10-26, #160; amends SPEC section 2).** A SwiftPM `.build` is offered even though `.build/checkouts/*` are git clones: SwiftPM manages and re-fetches them. The exemption is narrow and data-driven (`ProjectBuilds.managedClones`): only a `.git` folder at `<project with Package.swift>/.build/checkouts/<name>/.git` is passed over, in the one `.git` search the scan and the check share (`CandidateCheck.protectedEntry`). A `.git` anywhere else in a build folder (`.build/other/…`, nested deeper under a checkout, `node_modules/pkg/.git`, a `checkouts` folder in a non-SwiftPM build folder) still keeps it, and a project with uncommitted changes in its own repo is still refused.
34. **Internal names are CacheDrop (2026-10-26, #150).** The code follows Decision 32: `CacheDropCore` (package, module, `CacheDropCoreTests`), `CacheDrop/CacheDrop.xcodeproj`, the `CacheDrop` target and scheme, `CacheDropUITests`, `CacheDrop*` types, `CACHEDROP_TEST_*` and `.cachedrop-test-*` seams, the `CacheDrop` logger subsystem, `CacheDrop.*` notification identifiers and defaults keys (`CacheDropDryRun`, `CacheDrop.showsMenuBarItem`, `CacheDrop.startAtLogin`) and the `.cachedrop-deleting-` leftover marker. Those keys and their former names are defined once, in `PreferenceKeys` (#182). Only legacy code names Still: `RenamedPreferenceKeys` copies, once, values this Mac saved under the pre-#150 keys (`StillDryRun`, `Still.showsMenuBarItem`, `Still.startAtLogin`) to the new keys inside CacheDrop's own domain, keeping the old values and never overwriting a new key; `LegacyStillMigration` reads Still's folder, domain and keys (copying `StillDryRun` and `Still.showsMenuBarItem` under their new names, but not `Still.startAtLogin`, since login launch is registered for Still's app); both run at launch from `LocalStateLocation.migrateFromOldNames()`. `AlertOpenContext` still reads an alert delivered before #150 by its `Still.observedAt` user-info key when `CacheDrop.observedAt` is absent. Still's folders and bundle IDs stay protected, `.still-deleting-` leftovers are still offered, and the fixed `Still.lowSpace` request is still removed. No behaviour change. The GitHub repository keeps its name (`mac-cleaner`), the maintainer's call.
39. **Cancel stops a running tool mid-item (2026-10-26, #166, #185, #186; amends SPEC sections 3 and 4).** Cancelling a cleanup, or confirming "Stop and Quit", stops a running cleanup tool (such as `brew cleanup`) instead of waiting for it: its whole process group gets SIGTERM, then SIGKILL after 2 seconds. The item is recorded as failed and partly removed with the tool's output, since the tool may have cleaned part of it, and its folder is never deleted after it. A tool that finishes just as the cancel lands keeps its result, but its folder isn't deleted after it either: a cancel starts no new destructive step (#195). A tool cancelled just before launch never starts and is recorded as stopped with nothing changed. Trash moves and deletes already under way still finish; items not started stay not started. Docker's prunes and `simctl` hand their work to a daemon CacheDrop can't stop, so for them only the wait stops and the results say the work may still be finishing (#185; ollama is #189). Copy says "Stop cleanup" and "Stop it and quit?", never "after this item". (35–38 are unused: two branches claimed them at once, and the expansion Decisions moved to 40–44.)
40. **Expansion scope (2026-10-26, #168).** CacheDrop grows toward developers, music producers and video/photo creators; all three are in scope. Music first, developer fixes alongside, and video/photo starts as guidance only until there is a disposable test setup (trial apps in a separate macOS user account, never the user's own files). Guidance counts as support: it is labeled as guidance, and its bytes never count as freed. It starts after #106 and #118, except the developer slices. Research is on `product-notes` (`docs/reference/cachedrop-expansion-research.md`), reference only.
41. **Uninstall is in scope (amends SPEC section 9).** Apps, plug-ins and their leftovers go to Trash, never deleted permanently, so Put back works. Leftovers of apps already removed come first (#173), then uninstalling an installed app with its files (#177). An item belongs to an app only when its bundle ID or an installer receipt ties it to that app; name-only matches show as "possibly related" with the reason and are never preselected. Apple's folders and license files (iLok/PACE and similar) are never offered. When the vendor ships its own uninstaller or manager, CacheDrop offers it first, then checks for leftovers.
42. **Plug-ins are uninstalled as a whole product (#174, #176).** Every format (AU, VST, VST3, AAX, CLAP, AUv3) plus the support files its installer receipt lists. Content and sample libraries are listed under the product as a separate checkbox, unticked, since products often share them. Files are grouped into products by installer receipts first, then bundle ID and manufacturer; files nothing ties together stand alone. Nothing is called unused because of its age.
43. **Write scope: anything the user owns (amends 4 and SPEC sections 2 and 9).** CacheDrop changes items the current user owns wherever they are, including plug-ins and content in `/Library` that the user owns. Root-owned items in a reviewed uninstall plan go to Trash by asking Finder (Apple Event), which shows its own admin password prompt; CacheDrop itself never asks for a password and installs no helper. This waits on a spike (#172) confirming Finder's prompt and Put Back. If the spike fails, or one prompt per batch proves a real annoyance, a privileged helper is reconsidered under these rules: off by default and turned on in Settings (`SMAppService`); it only moves to Trash root-owned items of a reviewed uninstall plan, through the same checks; never system caches, `/System` or SIP-protected paths, other users' files or permanent deletion; it accepts requests only from CacheDrop, checked by code signature; it waits for #118; its PRs get `/security-review` and the user's explicit sign-off.
44. **uv is cleaned with its own command (#169; amends 21).** `uv cache prune`, never deleting its folder, as uv's docs require. Same pattern as Decision 23.

# Still: reset plan (draft to grill)

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
This replaces the bespoke Chrome/Xcode/pip/Docker/Homebrew paths with one model in StillCore:
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
| Developer caches: npm, Yarn, pnpm, uv, pip, Cargo, Gradle, CocoaPods | delete (cache dirs) |
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
- **Unit:** `swift test --package-path Packages/StillCore`, with temp-folder fixtures for every catalog rule (discover → preflight → execute → result), plus a case where the owner app is "running" and is refused.
- **App:** `DEVELOPER_DIR=… xcodebuild -scheme Still build test` locally, with the smoke UI set.
- **Real-world check:** a run on your Mac compared against a manual `du`/`df` survey, the field note's method. The pass bar: it finds the categories the field scan found, and its measured freed space matches `df`.

## Decisions (grilled 2026-10-26)
1. Salvage the core; replace bespoke adapters with one catalog-driven layer.
2. Target: shareable (Developer ID + notarization), but signing is gated to a later "shareable" milestone. M1 = works on the user's Mac.
3. Regenerable items (caches, build output, updater downloads, leaked app copies) are deleted permanently; user files, models, VM images and installers go to Trash.
4. User-owned scope only, including the user's own /private/var/folders entry. Never prompt for admin. Full Disk Access is an optional "see more".
5. The prototype (full mode) is the UI authority again, plus one short SPEC.md for behavior.
6. Tag main as `archive/codex-era`, then delete the control docs, validation reports and PNGs from main. Keep the prototype, PRD and field note.
7. **M1 done when:** on the user's Mac the app finds the field-scan categories (Chrome code-sign clones, developer caches, updater downloads, Xcode, browser caches, models/VM images, old Downloads), cleans what the user picks, and the freed space it reports matches `df`.
8. A dry-run switch is used for the first real passes. Tests only touch temp fixtures.
9. Codex's protected-data lists (Chrome logins/cookies/history/profiles; Xcode source/archives/dSYMs/products) become catalog "protected" rules. Their version gates are dropped.
10. CI becomes one PR job (unit tests + app build). L3 approved.
11. Export the Codex stashes as patches and back up its notes. The user deletes the Codex cache. Close the 25 open issues as superseded and open new ones from this plan.
12. What grew and alerts code stays in the tree but unwired; the flag is removed. Revisit after M1.
13. iCloud is inventory only in M1; eviction comes right after.
14. Workflow: push branch → PR → CI → user smoke-tests → Claude merges.
15. Delete the 14 Codex-era UI test files and replace them with about 5 smoke journeys. Adapt the unit tests.

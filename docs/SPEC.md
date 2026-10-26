# Still: behavior spec

This spec covers behavior the prototype can't show. The screens, layout and copy come from the prototype (`docs/visual/preview.html`, full mode). Where this spec and an older doc disagree, the **Decisions** in [RESET.md](RESET.md) win, then this spec. The PRD, research and field note are background.

## 1. Product principles

- Still answers four questions: what takes space, what can be removed, what happens if it is, and how much space came back.
- Size, age and location only suggest candidates. Every candidate is judged on three questions: who owns it, how it comes back, and whether anything uses it now.
- Nothing is preselected. The user picks categories or items, then reviews the consequences before anything changes.
- Every item is checked again just before Still acts on it (section 4).
- Scanning never writes. Choosing scan locations never means consent to clean.
- Unknown is shown as unknown, never as 0. A location Still can't read is listed as not accessible, not left out of the picture.
- Estimated space, space moved to Trash and measured freed space are three separate numbers, always labeled (section 6).
- No account, server, telemetry or AI service. All scanning and cleanup happen on the Mac.
- No automatic cleanup. Still only acts when the user confirms a reviewed plan.

## 2. Safety rules

These hold for every category, in every milestone.

- **User files go to Trash.** Still never empties the Trash, and never deletes anything from it.
- **Never touched:** browser logins, cookies, history, passwords, autofill, site data (IndexedDB, Local Storage, service-worker data), sessions and profile settings; the Photos, Mail and Messages databases; app binaries and signed bundles (except Chrome's leaked code-sign copies, section 3); other users' data; system files.
- **Protected rules in the catalog.** Codex's protected-data lists become catalog rules that no cleanup rule can override: Chrome logins, cookies, history and profiles; Xcode Archives and anything outside DerivedData (project source). Everything inside DerivedData, built products and dSYMs included, is regenerable build output.
- **A cache folder can hold live work.** A git working tree inside a cache folder is never a candidate. Known load-bearing caches (such as ccache) and Still's own tools are never offered.
- **Owning app must be closed.** If the app that owns a candidate is running, that candidate is refused with a reason. Still never force-quits or asks for Accessibility to quit an app. The user closes the app and rescans.
- **No admin rights.** Still never asks for an administrator password and never installs a helper. An item it can't change as the user is skipped and reported.
- **Exclusions win.** An item inside a user exclusion is never a candidate.
- **No transactional rollback.** Items are handled one at a time. Still never claims a multi-item undo.
- **Tests touch only temp fixture folders**, never real user paths.

## 3. Kinds of data and their action

Each category is a rule in a data catalog: paths, owning app, kind of data, action, protected patterns and the consequence text shown at review. There is no version gating: a rule applies whenever its paths exist, and its protected patterns and per-item checks keep it safe.

Decision 3 sets the main split: regenerable data is deleted permanently; user files, models, VM images and installers go to Trash.

| Kind | Examples | Action | How it comes back |
|---|---|---|---|
| Cache | npm, Yarn, pnpm, uv, pip, Cargo, Gradle, CocoaPods, Homebrew cache; browser cache folders; per-app `~/Library/Caches` | Delete permanently | Downloaded or rebuilt on next use |
| Build output | Xcode DerivedData project folders (products and dSYMs included), iOS DeviceSupport except the 2 newest versions per platform | Delete permanently | Rebuilt; next build is slower |
| Updater downloads | Sparkle and vendor updater caches | Delete permanently | Downloaded by the next update |
| Leaked app copies | Chrome `code_sign_clone` copies | Delete permanently, except the copy in use and the newest | Not needed again |
| Logs | User logs and crash reports | Delete permanently | Written again as apps run |
| Installers and old files | `.dmg`, `.pkg`, `.zip` in Downloads at any age; files of 500 MB or more not opened in 90 days | Move to Trash | Restore from Trash in Finder |
| Models | Hugging Face models | Move to Trash | Restore from Trash, or download again |
| Ollama models | Each model, removed with `ollama rm <model>` | Run a tool | Download again (`ollama pull`) |
| VM and disk images | e.g. an unpacked image next to its compressed source | Move to Trash | Restore from Trash, or the app unpacks or downloads again |

Other actions:

- **Run a tool**, with a time limit: `brew cleanup -s` (plus the Homebrew cache folder), `xcrun simctl delete unavailable`, `ollama rm <model>`. Every other cache is cleaned by deleting its folder, not with the tool's own purge command. The tool's output and the measured freed space appear in the results. A tool that isn't installed means its rule doesn't appear; Still never installs anything.
- **Evict local iCloud copy** (after M1): removes only the local download; the original stays in iCloud. Pinned, not-yet-uploaded and conflicted files are skipped. This is never a delete.
- **Guidance only**: Still shows the size and tells the user where to manage it. It never changes these: iOS backups, Mail and Messages attachments, Photos, Time Machine local snapshots, Xcode release archives, purchased content such as audio plug-ins ("reinstall through the vendor", owner's call).

Notes per category:

- **Browsers** (Chrome, Safari, Firefox, Arc, Edge): cache folders only, per profile, only while that browser is closed. Sizes show per browser and per profile. Review says caches are permanently removed, will refill, and pages may load slower at first.
- **Chrome code-sign clones** live in the user's own folder under `/private/var/folders`. The copy the running browser has open and the newest copy are always kept.
- **Xcode**: whole DerivedData project folders, only while Xcode and its build processes aren't running. Archives are never candidates.
- **Ollama**: shared blobs make per-file Trash unsafe, so models are removed with `ollama rm` (an exception to Decision 3).
- **Per-app caches**: only while the owning app isn't running.
- **Models and VM images** show their size and last-used date so the user can judge.
- **A cleanup rule appears only when its tool or folder exists** on this Mac.

## 4. Checks just before acting

When the user confirms, Still freezes the plan. Then, for each item in turn, right before acting, it checks that:

1. the item still exists;
2. it is unchanged since the scan (same file identity, not modified);
3. its owning app is not running, or for a command-line tool's cache (npm, pip, Cargo and the like), no process of that tool is running;
4. it is not excluded and doesn't match a protected rule;
5. Still can act on it as the current user, without admin rights.

An item that fails any check is skipped, and the results say which check failed. The rest of the plan continues. Skipped items can be reviewed again after a fresh scan; Still never silently repeats a completed action or widens a plan after a rescan.

**Cancel** stops new items from starting. The item in progress finishes or reports its failure. Every item's outcome (done, skipped, failed, not started) goes into the cleanup journal. If Still quits in the middle of a run, it recovers the journal on next launch and reports what happened.

## 5. Dry-run switch

- A visible setting, **Preview only (don't change anything)**. It's on by default in M1 builds; the user turns it off after the first pass (Decision 8). Whether it stays visible in a shareable build is decided later.
- With dry run on, the whole flow runs as normal: scan, plan, review, confirm, per-item checks, results.
- Instead of acting, Still logs each action it would take (item, action, size, check outcome) and changes nothing on disk. Tool actions are not run; the command is logged.
- Results make clear it was a dry run. No freed space is reported, because none was freed.

## 6. Estimated vs measured freed space

- **Estimated** space is what the scan sizes before cleanup, from allocated size where available. Overview's "Recommended for review: up to X GB" is the sum of current catalog candidates, labeled as an estimate.
- **Moved to Trash** is reported on its own. That space is still used until the user empties the Trash, and is never counted as freed.
- **Measured freed space** is the change in the volume's available space, read right before and right after each item. Results report the measured total, separately from the estimate.
- **Why both:** on APFS, clones share disk blocks. Deleting a clone frees only the blocks no other file uses. Chrome's code-sign copies showed 52 GB but freed about 2 GB. For categories made of clones, the estimate is labeled as an upper bound.
- **Why measure per item:** on a nearly full disk, macOS releases purgeable space on its own, so a single before/after reading for the whole run overstates what Still freed.
- Measured space is an observation. Downloads, snapshots and other activity can affect it, and the results say so.
- **Pass bar for M1:** on the user's Mac, the freed space Still reports is within 10% or 1 GB (whichever is larger) of the `df` change measured around the whole run.

## 7. Access: user-owned scope

- Still works only in what the current user owns: the home folder, `~/Library`, and the user's own entry under `/private/var/folders` (its `T`, `C` and `X` folders). It never asks for admin rights (Decision 4).
- It sizes only the catalog's known locations, plus folders the user picks. It never walks the whole disk.
- **Full Disk Access is optional**, a way to "see more" (for example Safari's cache, which macOS may protect). Without it, Still works and lists what it couldn't read as not accessible. Still explains that Full Disk Access is broad read/write authority, not a read-only permission, and that Still's own scans stay read-only.
- Still asks for access when a feature needs it, not as a launch checklist. No Accessibility, Screen Recording, notifications or login item is needed to scan or clean.

## 8. Milestone 1 vs later

**M1 is done when**, on the user's Mac, Still finds the field-scan categories, cleans what the user picks, and the freed space it reports matches `df` (Decision 7). M1 is not signed or notarized (Decision 2).

In M1 (tickets #97–#105):

- shared cleanup core: catalog, known-locations sizing, per-item checks, one executor, journal, dry run (#97);
- npm cache (#97); remaining developer caches and Homebrew (#99);
- Downloads installers and old large files to Trash (#98);
- Xcode DerivedData, unavailable simulators, old iOS DeviceSupport (#100);
- browser caches for Chrome, Safari, Firefox, Arc and Edge (#101);
- Chrome code-sign clones (#102);
- updater downloads, per-app caches, logs and crash reports (#103);
- Hugging Face and Ollama models, VM and disk images (#104);
- Overview with the storage bar and recommended total (#105);
- iCloud local copies: inventory only, no eviction (Decision 13).

After M1 (#92), in rough order:

- iCloud local eviction;
- Docker: `docker system df`, then a chosen prune;
- large and old files explorer (Trash only);
- guidance-only categories (section 3);
- What grew and storage alerts: the code stays in the tree, unwired, and is rewired only if still wanted (Decision 12);
- the optional Full Disk Access onboarding flow;
- signing, notarization and a DMG for a shareable build.

## 9. Out of scope

- Uninstaller, duplicate finder, treemap, automatic or scheduled cleanup.
- Emptying the Trash.
- Admin helpers, root daemons, system extensions, anything that needs an admin password.
- Other users' data and system files; blanket cleanup of System Data, Application Support, containers, snapshots or swap.
- Changing Photos, Mail or Messages libraries or databases.
- Speed boosts, RAM cleaning, antivirus and similar.
- Cloud accounts, cloud-wide deletion, remotely updated cleanup rules.

## Open questions

None. The first six were answered on 2026-10-26 and are folded in above (RESET Decisions 16–22).

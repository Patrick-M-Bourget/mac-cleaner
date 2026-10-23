# Downloads native Trash executor — #9

Implementation begins at integration72be4a2. This ticket connects final immutable approval to exact-file native Trash and a local SQLite journal. No personal cleanup was performed by development tools; test mutations used explicitly owned disposable trees only.

## Boundary

Selection freezes original scope URL, canonical scope identity, configured Downloads identity, exact file URL/device/inode, mtime, logical/allocated observations and action. The executor consumes one approval ID durably, validates file type, same-volume descriptor-relative ancestors, protection rules, scope/root identity, access, size/mtime and local non-cloud metadata. Native coordination repeats validation immediately before FileManager Trash. No permanent-delete fallback, folder cleanup, cloud eviction, filename search, renamed-target substitution or automatic retry exists.

Apple's [native Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)) supplies the resulting URL and may rename the file. We retain only that actual returned URL, check its identity when available, and reveal it using Finder. [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator) coordinates participating presenters. Neither API supplies an atomic expected-inode compare-and-trash operation. Descriptor checks and cooperating coordination reduce concurrent-change exposure, but an uncoordinated rename can still race the final pathname operation. This is a documented native API limit, not an atomic-batch guarantee or a new approval flow. Deterministic pre-operation swaps are rejected.

A thrown operation with a still-matching original is failed. Missing/changed original after an operation throws is unknown, never inferred success. Unknown outcomes stop later targets. Cancellation stops new targets; current native call finishes before a safe Quit boundary. Unexecuted plans remain session-only.

## Persistence and results

`SQLiteCleanupJournal` uses a private local Application Support/Still database, mode0600, schema version1, serialized writer, WAL, synchronous FULL and fullfsync ON (queried back). See [SQLite synchronous/fullfsync](https://sqlite.org/pragma.html). These are platform durability measures, not a power-loss certification. The batch and frozen target evidence commit before work; each target's intent commits before the operation and outcome afterward. SQLite and Trash are separate transactions. Intent-write failure prevents that operation. Outcome-write failure leaves durable unresolved intent, reports unknown and halts later targets. Batch uniqueness rejects replay after reopening.

Public `records()` exposes pending, intent and terminal evidence for subsequent recovery/history tickets. Pending means no operation started; intent without terminal outcome is unresolved. No launch reconciliation, retry, completed-history retention or Reset feature is claimed here (#11/#12 remain separate).

Results distinguish planned logical size, the planned allocated estimate associated with known Trash successes, per-target states, and independently sampled startup-capacity change. Unknown outcomes make the held-byte estimate unknown. APFS sharing, regrowth and other processes prevent exact reclaimed-space attribution. A source's absence alone is never success evidence.

## Validation checkpoint

- Red: missing executor/journal API. First real checks also exposed canonical `/var` versus `/private/var` scope handling; original access URL and canonical scope evidence now remain distinct.
- Red: generic operation moved source then threw; result incorrectly said failed and zero held bytes. Green: unknown, later target cancelled, held bytes unknown, durable unknown evidence.
- Disposable public tests cover changed size, scope replacement, access loss, deterministic symlink replacement before native validation, native Trash failure, actual native Trash returned identity/location, failed outcome persistence/reopen, batch replay and boundary cancellation.
- 51 merged core tests passed on local Xcode27.1. Actual native core fixture removes only its own immediately returned Trash URL after identity/content checks.
- Native 20-file bulk → mixed19 → bounded review → Cancel → Space focus → explicit final Trash →19 successes/results passed31.1seconds, with unchanged window bounds and Light/Dark captures. Minimum-window follow-up initially caught a test targeting an underlying disclosure instead of the sheet; bounded test fix/qualification pending at this checkpoint.
- The UI run left19 owned one-byte files in Trash. A later serialized-path cleanup attempt encountered macOS access denial; no broad permission, bypass or Trash-emptying was attempted. Native core tests clean their own returned URLs. Future UI qualification uses the smallest useful fixture count.

Visual evidence uses shared PageHeader, SummarySurface, SettingsRow and StatusRow with existing shell/theme. Final capture paths and minimum-window result will be appended after qualification.

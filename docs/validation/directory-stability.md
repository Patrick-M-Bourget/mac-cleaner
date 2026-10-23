# Directory stability and one bounded recheck — issue #39

The scanner records directory device/inode, modification time and change time before descending. It verifies root-first ancestry identities before entry metadata and verifies recorded directories again after enumeration. Symlink/package and volume boundaries remain protected. Changing, replaced or disappeared directories make that pass unstable. The selected root identity is pinned across both attempts, including the gap after the public recheck announcement; a replacement scope is never silently adopted.

One unstable pass may trigger **one whole-scope metadata recheck**. Both attempts share the existing 100,000-entry work budget, depth-64 protection, bounded issues and a new cooperative **30-second total deadline**. There is no unbounded retry. A large first pass can consume the work budget before a complete recheck is possible; that remains partial and offers an explicit smaller-folder/recheck route. An already blocked OS/provider call must return before cancellation or the deadline can be observed. The deadline is checked around work boundaries; it is not a hard real-time interruption guarantee.

The second pass starts fresh observations and accounting rather than combining inconsistent rows. Progress explicitly names the single recheck; inspected-work count and elapsed time remain cumulative. Shared `ScanProgressSummary` shows phase as accessible text beside the native spinner, includes the recheck state in the developer gallery and retains the existing fixed Stop action. No new screen, navigation resize or cleanup authority is introduced. Repeated instability, replacement, elapsed/entry bounds or cancellation never produce a completed growth baseline or restore pending choices from incomplete coverage.

`GrowthScanRecorder` now fingerprints scanner rules as version 2 (directory stability, one recheck and deadline policy). Earlier version-1 baselines therefore show changed coverage instead of silently comparing against the stronger observation policy. Aggregate storage and unresolved recovery journals remain separate.

## Public disposable fixtures

Eight new scanner/growth-boundary tests cover one stabilizing nested change; repeated changes with no growth baseline; root replacement; cancellation at the announced recheck boundary; shared entry-budget exhaustion; a returning metadata call past deadline; an ancestor replaced by a symlink to an owned outside fixture; and root replacement specifically between the retry gate and second enumeration. The last race failed three assertions before pinning original root evidence into both attempts, then passed. Tests observe results, public progress and baseline persistence, not private directory helpers.

The merged StillCore suite passed **95/95** on local Xcode 27.1 after integration `5e849e8`. Native build-for-testing succeeded with the bound owned-fixture helper and explicit accessible phase text. No personal directories were inspected.

The focused native journey passed **1/1 in 75.5 seconds**, covering initial and 900×640 bounds, Light/Dark appearance, the visible recheck phase, fixed Stop reachability, actual Stop acknowledgement, disabled cleanup authority and unchanged owned sentinel contents. The DEBUG mutation boundary requires the explicitly selected UUID-namespaced temporary root, current-user ownership and exact device/inode environment binding; production contains no fixture mutation.

The first native attempt failed an exact native ProgressView-label lookup while its recording showed the correct phase and fixed Stop. Replacing that label with explicit accessible Text plus a stable identifier made the public journey pass, without increasing waits or fixture size. Local result: `.build/directory-stability-final-ui.xcresult`; log: `/tmp/still-stability-final-ui.log`. Core log: `/tmp/still-stability-final-core.log`; benchmark output is linked below.

**Unobscured native visual qualification remains pending.** Exported screenshots contain an unrelated stale Gatekeeper warning for an unsigned `StillUITests-Runner` from another local test attempt. The owned warning could not be safely dismissed through available UI surfaces; warning diagnosis was stopped. No OS security settings were changed. Occluded screenshots remain local inside the result bundle and are not committed or counted as visual signoff. Behavioral assertions passed despite that overlay; they do not substitute for unobscured visual review.

## Actual 50,000-file performance delta

One new owned fixture run was performed while the native UI runner was idle. [Raw result](benchmarks/scanner-50000-directory-stability.json) records actual hardware, preflight and cleanup. The tool reserved 1,892,941,824 bytes before creating its own temporary fixture; it removed that root on exit. No million-entry rerun was performed.

| Measurement | Earlier #34 stable fixture | Current #39 stable fixture |
|---|---:|---:|
| Entries | 50,000 files + 50 directories | 50,000 files + 50 directories |
| Complete observations | 50,050 | 50,050 |
| Scan duration | 5.400 s | 7.501 s |
| First useful progress | 0.00164 s | 0.00146 s |
| Process peak resident bytes | 113,590,272 | 113,901,568 |
| Ordinary boundary cancellation upper bound | 0.00044 s | 0.00048 s |

The observed scan time increased about **38.9%** (+2.101 seconds). Observed peak increased 311,296 bytes. These numbers describe these two runs, not a universal memory-regression guarantee. The new stable run completed within the 30-second deadline. The added ancestry checks/evidence do have a cost; the old #34 numbers alone do not qualify this implementation. This remains a 16 GB, eight-processor, 245 GB-volume host running macOS 27.0.1, **not the specified 512 GB reference environment**. The earlier 100k and million-entry qualification limits remain open; no new claims are made for those workloads, arbitrary path lengths, blocked providers or a changing 50k tree.

## Limits

Metadata checks are observations over time, not an atomic APFS snapshot. Changes after the final check or in-place file-content changes that do not affect the directory evidence are not excluded by an atomicity guarantee. No content hashes/reads or cloud hydration are introduced. Actual iCloud non-hydration, real mounted-volume loss and non-returning provider cancellation still require their existing native integration gates. A complete stabilizing recheck does not imply writer attribution or exclusive reclaimable space.

# Cancellation, partial outcomes and explicit retry — #11

Based on integration7b3a718, then merged refresh42b366d and startup recoverydb3b869. Only owned disposable fixtures were mutated during qualification. Personal cleanup and broader OS permissions were not requested.

## Contract

The executor checks cancellation before a target, after durable intent and before starting its native operation. An already underway native operation finishes or is reported unknown; neither a cancellation token nor Quit forcibly interrupts FileManager/NSFileCoordinator. There is no batch rollback. The app stays alive at the existing lifecycle safe boundary until the operation worker returns. Progress reports per-target outcomes; it does not call unfinished operations successful.

Known failure/skips allow unchanged approved targets to continue. Unknown native or outcome-write failures stop further work and preserve journal evidence. The general plan is consumed before execution. Current results show each outcome separately and retain actual returned Trash locations for known successes.

**Recheck unfinished files** is read-only. It scans the original authorized scopes and forms a new draft only from complete fresh observations and matching exact source identity, original scope/root authority, volume UUID, size/mtime, protections, locality and current Trash access. Parent directory write/search permissions matter; a readable0444 file is not rejected merely for lacking file write permission. Unknown or changed evidence fails closed. Completed successes and new discoveries are excluded. Storage identities may deduplicate sizes, but different hardlink paths remain different targets.

The retry plan shows only eligible unfinished identities. Select all/refinement cannot add discoveries outside that set. Changed/unavailable identities are named with a new-scan recovery explanation. A new general folder choice leaves retry restriction explicitly; ordinary discovery still begins unchecked. **Review cleanup** and a new final **Move to Trash** approval are required. Startup recovery records remain read-only and do not reconstruct a retry/approval automatically.

## Public boundary evidence

- Red→green: after a committed intent a cancellation request still reached the operation. A second boundary check now records cancelled without starting it.
- Red→green: the retry API initially did not exist. A partial fixture now reports failed/succeeded/cancelled, continues unaffected work, excludes the success, excludes a changed original and a new discovery, and creates a different explicit approval for the unchanged unfinished path.
- Red→green: readable file plus unwritable parent was incorrectly eligible for retry. Current full Trash validation rejects that target.
- Red→green: reusing the pre-execution scan could seed a retry. Fresh observations must postdate approval; latest incomplete coverage cannot fall back to an older complete sample.
- Public progress reports0→1→2 outcomes while unchanged external failures continue. SQLite outcomes match the reported states. Existing #9 tests independently cover native Trash, identity/symlink swaps, failures, unknown outcomes, replay and cancellation between targets.
- Retry preparation indexes scope/member evidence once and uses the module-only validated candidate path; it avoids a target-by-inventory quadratic search. No public unchecked-target insertion API was added.

## Native UI qualification

The two-file fixture uses an explicit DEBUG-only delay around the real native Trash adapter, bound to the already chooser-authorized `StillSelectionUI-*` root. This permits deterministic Stop while the first target is underway; it does not simulate a successful operation or establish a maximum OS-call duration. All journals use shared identity-bound0700 `StillTestState-*` directories and marker validation; invalid roots fail closed rather than falling back to normal Application Support.

Initial/minimum journeys verify Stop, one actual success plus one cancelled original, fresh retry with only the unfinished file, new-discovery exclusion, new consequence confirmation and Cancel preserving both remaining files. Light/dark progress/result/plan captures accompany the affected journeys. The exact-file disclosure check exposed a native accessibility rectangle extending outside its bounded ScrollView; the shared spacing gutter now contains the full reported control bounds. Native label clicks and leading AX padding do not activate the arrow. The actual visible glyph is tested inside that contained frame, independently of label text, and expansion must reveal the exact target. Both focused journeys passed on macOS with Xcode27.1: initial1120×760 (47.1s) and minimum900×640 (44.9s). The merged core suite passed79 tests; native build-for-testing passed. Captures are committed in [cancel-retry](../visual/cancel-retry), covering both themes at both window sizes, stopping, partial results, the restricted retry plan and expanded exact confirmation. The minimum expanded confirmation is Dark; the initial expanded confirmation is Light.

OS Trash access prevented cleanup through serialized returned paths in earlier fixture work; no broad permission or Trash-emptying workaround is introduced. Only a few owned one-byte UI fixtures remain in Trash. Core native tests clean their own immediately returned URLs after identity checks. VoiceOver, power-loss durability, and forcibly interrupting an OS filesystem call are not certified here.

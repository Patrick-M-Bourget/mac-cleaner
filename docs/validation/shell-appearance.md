# Shell and appearance qualification — #53

## Current verification checkpoint — October 24, 2026

Integration is still blocked. Corrected Gallery run `40094091084` at `4665407` passes 4 tests with 68 original captures (48 new shell examples, 20 existing capacity/local-records examples). All 68 originals have been individually accepted, including the existing examples; exact per-image reviews are preserved beside the manifests. Staged Reset run `40094530265` at `aadc664` passes both sizes, with all 6 originals accepted: clear failure retains uniform Dark; successful appearance removal switches chrome and content to Automatic even when a later service fails. The competing live SwiftUI appearance override was removed; the native process now owns live appearance. Originals and unchanged export manifests are preserved under `docs/visual/shell-appearance/` by run ID.

The strict Retry journey still fails at `2795902` in run `40095078306`: after removing the owned write fault, clicking Retry does not save the preference. Explicit button style and increased z-order did not resolve it; neither is recorded as a successful fix. Earlier targeted instrumentation showed no action callback entry. Final affected-flow run `40094532205` passes the two capacity journeys but fails later History/window/navigation checks; diagnosis is pending. Earlier 16/16 regression evidence at `ba355dd` is historical and does not certify the changed live appearance composition. Do not close #53 or claim all journeys pass until these gates clear.

The sections below are chronological evidence, including failed/superseded candidates. Their pending wording describes those checkpoints rather than overriding this current status.

Contract [SHELL-APPEARANCE](../SHELL-APPEARANCE.md) locked October 24,2026 at f5174a6. Public appearance-service boundary explicitly approved by user; existing public UI journeys remain approved. Implementation started in isolated issue53 worktree. No new test result, source acceptance or native capture is claimed yet. Record actual red→green cycles and source-bound original theme/size captures here before integration.

## First public shell tracer

Test-only source `a66d39e` adds an owned two-file Downloads journey through existing public UI. After scanning and category selection it expects one accessible category badge, accurate Plan/History context, preserved choices across navigation/themes, stable outer bounds, hidden badge after deselection and unchanged original bytes. Local Xcode27.1 build-for-testing passes. Hosted native run40090379307 at a66d39e fails as intended on the missing accessible category badge (line38,30.798s), after successfully selecting both owned files. The original900×640 Light capture and export manifest are preserved at ../visual/shell-appearance/40090379307-red/. Individual review also confirms the editable Plan is incorrectly labelled Read-only metadata; no test-fixture correction is needed. This is failing baseline evidence, not acceptance.

The appearance implementer uses the explicitly approved public preference-service seam. Typed monitoring presentation is being developed through the existing approved public alert-controller/controlled OS-clock seam; underlying polling, authorization and delivery policy must remain unchanged. No product monitoring capability is promoted.

Public appearance service checkpoint agentd346851/root92521d8 adds four actual red→green journeys: missing/default and persisted recreation; invalid/unreadable no-repair fallback; failed write retaining session choice and explicit retry; independent remove-success Reset behavior. Focused4/4 pass; logs /tmp/shell53-cycle1-red.log through cycle4-green.log retained in implementation cache. App composition/native appearance qualification remains pending.

## Native badge/context vertical and appearance red

`40090744516` at `efb059a` passes the selected-category/destination journey45.892s. Both original900×640 Light/Dark captures individually reviewed: one badge for two selected Downloads files, correct Plan context, stable geometry and reachable actions. Test also checks History context, choice preservation, badge hidden after deselection and unchanged fixture bytes. This bounded pass does not qualify appearance persistence or monitoring presentation. Originals/manifests: `docs/visual/shell-appearance/40090744516`.

Appearance-only tracer `40090809557` at `5ae8d7d` fails as intended atline81 after Dark→Quit→relaunch restores Automatic instead (11.194s). The owned-state fixture reaches the intended failure; no test correction required. Original900×640 Light/Automatic reviewed and preserved in `docs/visual/shell-appearance/40090809557`. App wiring follows this observed red; public policy4/4 alone was not sufficient.

Restricted source reviews of services atf82abf8 found Reset load/remove exceptions could leave shell readiness stale, and present-but-invalid capacity could say on despite rejected metadata. Source correctiona21f1a0 marks typed attention while preserving policy/lifecycle behavior. Follow-up detail wording and app composition qualification remain pending. StorageAlerts43/43 pass after ten public red→green policy journeys (33existing+10new), recorded by the owner; not native OS certification.

Local full Core run at sourcea21f1a0 passes146 tests (141 Swift Testing +5 XCTest), log /tmp/shell53-core146.log, Xcode27.1. This includes the four appearance-policy journeys; it does not qualify native appearance composition.

## Application appearance and typed footer composition

Native appearance relaunch run40091348457 at49d8e79 passes19.175s: Dark survives Quit/relaunch, changing to Automatic also persists, empty Plan remains unselected and window bounds stable. This does not by itself prove a populated plan is cleared by Quit. Four public appearance policy journeys remain within Core146.

Footer actual red40091500415 at82d8ffe fails missing direct attention action after selecting an owned file and encountering an unreadable owned alert-state record (line123,36.710s). Original900×640 Automatic/Light reviewed and preserved. Green40091995008 atba355dd passes36.024s: direct typed attention details, honest stopped polling, unchanged original bytes/saved corrupt state and live choices. Opening footer details bypasses ordinary page-entry configure; it grants no retry/OS permission authority. The fixture is an explicit DEBUG controlled OS adapter gated by verified owned LocalState, not a product scenario selector.

Appearance exceptional run40091893260 atb947c2a passes four cases: read fallback initial14.695s/minimum10.586s; staged Reset/Clear initial26.243s/minimum29.858s. Invalid/unreadable settings stay untouched; Clear preserves Dark; appearance-clear failure retains Dark; later-service failure switches to Automatic after actual appearance removal; final full Reset succeeds. Both save/retry cases fail immediate disappearance assertions (line172,13.953/13.254s); this is not yet classified as a product error or resolved test timing. Test-onlyb3791a3 waits for the public control to disappear and independently verifies saved Dark plus relaunch. Its native outcome remains pending. The complete original14-image export and exact per-journey limits are preserved.

Separate Standards/Spec service and app reviews found Reset/invalid-capacity truth issues, correcteda21f1a0/05b462c with43/43 public alert tests (33existing+10new). Final detail wording red→green reuses those public journeys. App review49d8e79 has no remaining actionable finding in implemented scope. Footer review found an unsupported claim that no manual scan was running; source32d8751 scopes checking text to capacity checks instead. Synthetic Gallery/remainder native qualification is still pending.

## Recovery hit-delivery investigation

Run `40096248481` at `aaf9083` passively records a normal Retry click at the notice right boundary, with key/active window and no modal. Store diagnostics show no retry entry. The trace is preserved under `docs/visual/shell-appearance/40096248481-red`; that first hit-ancestry probe used content-local coordinates, so the exact ancestry is suggestive rather than a definitive AppKit hit-test. A shared activation-point modifier (`206e4b2`, run `40096588867`) leaves the synthesized right-edge click unchanged and fails. A native target/action button (`267cd7e`, final-flows run `40096952080`) also fails both Retry cases (22.397/18.521s), while the expanded badge journey passes50.089s. Neither candidate is accepted as a fix.

The same-source Gallery run `40096988157` passes4/4; presentation does not prove click delivery. A focused History replay at `ba0ce9a`, run `40096673703`, passes47.335/41.672s without launch diagnostics or a product change. The full original affected ordering remains a separate gate. Current diagnostic `16ab175` retains the original Retry failure, then compares a public physical-center click with correctly superview-relative native hit-testing and always reports the original failure. It cannot turn the original failure into green.

## Final affected-flow replay

Run `40096954114` at app source `267cd7e` passes all 16 scoped public native journeys in669.742s: capacity2, History2, Local records1, Storage alerts9 and Downloads2. It repeats the original capacity→History ordering without a product launch change; no launch-failure diagnostic path converts a failure to green. The isolated earlier missing-window run remains recorded, with no established cause or invented product fix. Later source `2456cdd` changes only the failed Retry control’s native accessibility activation point and removes diagnostics; this16-run does not qualify that later activation correction. Its unchanged strict public journeys remain the separate gate.

Local Xcode27.1 build-for-testing passes at app source `2456cdd`; the copied development app’s ad-hoc signature verifies. No real OS permissions, iCloud provider behavior, universal accessibility or supported-platform certification is implied.

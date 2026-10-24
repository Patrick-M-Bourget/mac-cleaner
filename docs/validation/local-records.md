# Shared Local records — #62

October 24, 2026. Approved FLOW-LOCK Q17/Q25, N03/H04/L01–L02 and child #62 under #48. Base integration `03cbdfc` contains qualified caller-aware recovery/Results/access guidance; `50d23db` advances the synchronized handoff. Implementation remains isolated on `verify/local-records-next` until qualification.

## Existing contract

History and Locations enter the same secondary Local records page, with the caller sidebar and one labelled Back. New entry begins at the top; returning preserves caller viewport, live selections and configuration. Opening the page performs no Clear, Reset, scan or permission request. Existing CleanupHistoryModel mechanisms and consequence-specific confirmations supply maintenance policy. Clear preserves current choices, remembered scopes, recovery facts and original files. Reset still checks current journal facts inside its transaction and never changes macOS grants.

Recovery review entered from the page returns to Local records, whose Back returns to the root caller. Direct sidebar navigation clears secondary context. Existing future-gated diagnostics returns directly to the actual History/Locations origin (FLOW-LOCK Q17/table), with Overview diagnostics retaining its existing Overview return. Exclusions remain separately future-gated. No new primary navigation item or roadmap promotion.

## First public tracer

Test-only `3bae223` checks History → Local records → Clear Cancel → Back, then Locations → the same page → actual Clear → caller Back, preserving original bytes and consumed approval protection through public journal APIs. Actual hosted red `40064787450` at `2b76a22` fails on missing `manageLocalRecords` at HistoryUITests line 31 (69.15 seconds including cleanup). Production composition follows this observed public failure. Existing approved public journey/journal/filesystem seams remain in force.

## Qualification gates

Record actual red → green, then strengthen public context/selection and fresh Reset/recovery journeys one vertical slice at a time. Preserve existing startup recovery, terminal Results and Downloads behavior; review source-bound native Light/Dark initial/minimum originals and shared composition before integration. Test and synthetic presentation proof remain distinct from real OS permission/provider qualification. Full parent acceptance, unresolved product decisions and future milestones stay open; M8 remains deferred.

Minimal candidate `ec75c43` composes the same LocalRecordsEntry/LocalRecordsView from both callers and moves existing maintenance confirmations out of History. The panel calls the existing history model with maintenance disabled for reading, leaving ordinary History retention behavior unchanged. The first candidate run `40065094232` was dispatched; caller viewport, recovery/diagnostics and broader safety context are the next vertical after that pilot. This candidate is not integrated or declared complete.

The first candidate run `40065094232` reaches both callers, Cancel and actual Clear, then fails its label-prefix status lookup (28.08 seconds). No failure image was attached by that test. Test-only `345e16d` uses the existing public `historyStatus` identifier and native value/label text, preserves the strict success-prefix and public journal assertions, reveals entries within the actual scroll viewport, and records a permanent status screenshot before asserting. The rerun uses identical production source; whether this is only a lookup mismatch remains subject to that result.

Pilot `40065421756` at `345e16d` passes (20.31 seconds) with unchanged production source. The public identifier/value lookup resolves the status mismatch while still proving actual completed-record removal, consumed approval protection and unchanged original bytes. Both origins and the single caller Back pass. The next public context/recovery vertical remains pending; this pilot alone does not qualify the full ticket.

The first Clear-status original and its manifest are preserved under `docs/visual/local-records/345e16d-clear/`. Reviewed at minimum bounds with Automatic resolving Light: complete success message, readable consequences, actual Locations parent and fixed Back. Context attempt `40065661372` at `57f7b88` failed compilation because the new async XCTest helper used synchronous wait APIs. This is not behavioral red evidence. Test-only async fulfillment correction `4c117d1` passes local build-for-testing; actual context rerun is dispatched on that revision. The stronger public journey also observes a deliberately nonzero management scroll offset before recovery.

Actual context red `40065822914` at `4c117d1` reaches the read-only expired-record proof, live choice, History viewport/disclosure, nonzero management offset and fresh Reset block, then fails at missing Back to Local records (line 121; 105.86 seconds). The next source supplies that contextual return and process-owned management viewport. Global scan-return and alert-open navigation also clear the new secondary context; no feature gate changes.

Context green `40066234820` at `63361f9` passes (86.89 seconds), including the real nonzero management return frame, live choices and unchanged protected facts. Adapted History maintenance green `40066234839` passes 3/3 (100.48 seconds). Broader initial/minimum qualification adds both-origin Light/Dark panel captures, process window reopen and repeated new-entry top. A separate future-gated diagnostics tracer checks both actual root callers, native Save Cancel, frozen redacted preview and process context; it will supply behavioral red before diagnostics routing changes. All new test sources pass local build-for-testing.

Diagnostics actual red `40066805589` at `6cd6f84` fails at missing Review diagnostics (line 63). Its async test continued absent-route queries after the first assertion, taking 469.57 seconds; the guard now records XCTFail and returns promptly without weakening the entry requirement. Source `37aeaf0` adds the unchanged future-gated entry, process-owned frozen diagnostics model/caller/viewport, fresh top identity and direct root Back. Local build-for-testing passes. New diagnostics route and existing Overview diagnostics regressions are in verification.


## Final source and acceptance checks

Final application changes are `dadc0c1`; `f26b413` adds test-only Gallery qualification and `f8a0c86` selects final scoped CI runs. Local build-for-testing passes. Shared `LocalRecordsMaintenanceControls` and `LocalRecordsDiagnosticsEntry` render live and inert labelled Gallery examples without duplicating maintenance policy. Both ordinary launches and diagnostics development-gated launches are tested separately.

New diagnostics route green `40067584469` at `ff51967` passes (70.14 seconds). Existing Overview diagnostics regression `40067584423` passes 2/2 (40.29 seconds). Earlier expanded context initial/minimum runs `40066805453` / `40066805492` pass (80.10 / 74.21 seconds). Final shared-control composition is being requalified at `f8a0c86`, including diagnostics at both sizes, both context journeys, synthetic controls and affected native regressions. These results do not certify real permission changes, provider behavior, every OS/CPU or distribution readiness.

### Standards review

Whole-slice source review through `ff51967` and incremental review `ff51967..f26b413`: no actionable source findings. Shared pure controls preserve enabled predicates, confirmations and guarded actions; tests exercise public UI rather than execution bypasses.

### Spec review

The same two source-review ranges have no actionable implementation findings against #62/FLOW-LOCK. Both real callers, direct root diagnostics Back, gated availability and retained viewport context match the approved contract. Stale Overview-only diagnostics documentation is being reconciled before integration. Runtime and original-image review remain separate acceptance gates.


### Final native results available so far

At `f8a0c86` (application source `dadc0c1`): context minimum `40068265478` passes 87.352 seconds; display-clamped initial `40068265529` passes 89.725 seconds. Gated diagnostics minimum `40068265439` passes 74.734 seconds; initial `40068265594` passes 63.684 seconds. History `40068265641` passes 3/3 (38.775, 35.325, 16.660 seconds), including actual Clear and the fresh Reset guard after relocating controls.

Gallery attempt `40068265576` fails both tests at its theme-picker lookup: native AX exposes label `Appearance, Appearance`. Test-only `f754b83` uses the established unique Gallery picker, asserts its uniqueness and chosen Light/Dark value. No application source or control/frame assertion changes; local build-for-testing passes. Focused Gallery rerun `40068435072` at test-only `f754b83` passes 2/2 (51.382 / 49.623 seconds). Affected regressions `40068265638` remain pending.

Originals from the four final context/diagnostics runs are retained under `docs/visual/local-records/f8a0c86-<run>/` with unmodified manifests. All 44 were inspected individually: no blocking readability, caller, footer or geometry issue. Initial preset captures are actually 1024×640 due to the hosted display; minimum captures are 900×640. Deliberately scrolled History/management/diagnostics content can be partially clipped at its viewport boundary; the fixed shell and footer remain visible, and exact public frame assertions verify restoration. Initial blocked status changes from caution to informational styling when the existing model reloads; protected-record text/actions and actual safeguards remain explicit. This is a minor presentation observation, not evidence of an authority change.


Final History and Gallery add 11 and 12 individually reviewed originals: **67 final originals total**, plus the historical first-pilot Clear image. Six unmodified manifests preserve test names and original UUID filenames. All final images are checked individually, not inferred from a contact sheet. No blocking readability, theme, caller or fixed-layout issue was found. Gallery captures explicitly show inert shared enabled/disabled maintenance and optional diagnostics presentation; they do not certify operation execution. Final History fixtures separately prove actual Clear and protected Reset. Dedicated protected-state captures fully reveal caution text even when a neighboring enabled-state view is deliberately scrolled. Original initial images are display-clamped 1024×640, not claimed as full1120×760 runtime proof.

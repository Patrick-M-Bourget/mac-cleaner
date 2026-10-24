# Shared Local records — #62

October 24, 2026. Approved FLOW-LOCK Q17/Q25, N03/H04/L01–L02 and child #62 under #48. Base integration `03cbdfc` contains qualified caller-aware recovery/Results/access guidance; `50d23db` advances the synchronized handoff. Implementation remains isolated on `verify/local-records-next` until qualification.

## Existing contract

History and Locations enter the same secondary Local records page, with the caller sidebar and one labelled Back. New entry begins at the top; returning preserves caller viewport, live selections and configuration. Opening the page performs no Clear, Reset, scan or permission request. Existing CleanupHistoryModel mechanisms and consequence-specific confirmations supply maintenance policy. Clear preserves current choices, remembered scopes, recovery facts and original files. Reset still checks current journal facts inside its transaction and never changes macOS grants.

Recovery review entered from the page returns to Local records, whose Back returns to the root caller. Direct sidebar navigation clears secondary context. Existing future-gated diagnostics returns directly to the actual History/Locations origin (FLOW-LOCK Q17/table), with Overview diagnostics retaining its existing Overview return. Exclusions remain separately future-gated. No new primary navigation item or roadmap promotion.

## First public tracer

Test-only `3bae223` checks History → Local records → Clear Cancel → Back, then Locations → the same page → actual Clear → caller Back, preserving original bytes and consumed approval protection through public journal APIs. Actual hosted red `40064787450` at `2b76a22` fails on missing `manageLocalRecords` at HistoryUITests line 31 (69.15 seconds including cleanup). Production composition follows this observed public failure. Existing approved public journey/journal/filesystem seams remain in force.

## Qualification gates

Record actual red → green, then strengthen public context/selection and fresh Reset/recovery journeys one vertical slice at a time. Preserve existing startup recovery, terminal Results and Downloads behavior; review source-bound native Light/Dark initial/minimum originals and shared composition before integration. Test and synthetic presentation proof remain distinct from real OS permission/provider qualification. Full parent acceptance, unresolved product decisions and future milestones stay open; M8 remains deferred.

Minimal candidate `ec75c43` composes the same LocalRecordsEntry/LocalRecordsView from both callers and moves existing maintenance confirmations out of History. The panel calls the existing history model with maintenance disabled for reading, leaving ordinary History retention behavior unchanged. Focused green run `40065094232` is pending; caller viewport, recovery/diagnostics and broader safety context are the next vertical after that pilot. This candidate is not integrated or declared complete.

The first candidate run `40065094232` reaches both callers, Cancel and actual Clear, then fails its label-prefix status lookup (28.08 seconds). No failure image was attached by that test. Test-only `345e16d` uses the existing public `historyStatus` identifier and native value/label text, preserves the strict success-prefix and public journal assertions, reveals entries within the actual scroll viewport, and records a permanent status screenshot before asserting. The rerun uses identical production source; whether this is only a lookup mismatch remains subject to that result.

Pilot `40065421756` at `345e16d` passes (20.31 seconds) with unchanged production source. The public identifier/value lookup resolves the status mismatch while still proving actual completed-record removal, consumed approval protection and unchanged original bytes. Both origins and the single caller Back pass. The next public context/recovery vertical remains pending; this pilot alone does not qualify the full ticket.

The first Clear-status original and its manifest are preserved under `docs/visual/local-records/345e16d-clear/`. Reviewed at minimum bounds with Automatic resolving Light: complete success message, readable consequences, actual Locations parent and fixed Back. Context attempt `40065661372` at `57f7b88` failed compilation because the new async XCTest helper used synchronous wait APIs. This is not behavioral red evidence. Test-only async fulfillment correction `4c117d1` passes local build-for-testing; actual context rerun is dispatched on that revision. The stronger public journey also observes a deliberately nonzero management scroll offset before recovery.

Actual context red `40065822914` at `4c117d1` reaches the read-only expired-record proof, live choice, History viewport/disclosure, nonzero management offset and fresh Reset block, then fails at missing Back to Local records (line 121; 105.86 seconds). The next source supplies that contextual return and process-owned management viewport. Global scan-return and alert-open navigation also clear the new secondary context; no feature gate changes.

Context green `40066234820` at `63361f9` passes (86.89 seconds), including the real nonzero management return frame, live choices and unchanged protected facts. Adapted History maintenance green `40066234839` passes 3/3 (100.48 seconds). Broader initial/minimum qualification adds both-origin Light/Dark panel captures, process window reopen and repeated new-entry top. A separate future-gated diagnostics tracer checks both actual root callers, native Save Cancel, frozen redacted preview and process context; it will supply behavioral red before diagnostics routing changes. All new test sources pass local build-for-testing.

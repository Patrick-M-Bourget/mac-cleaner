# Startup capacity refresh — #49

## Accepted bounded qualification — October 24, 2026

Application source `8869b38`; final documentation records this source without claiming one combined full-suite run. Six new public capacity-policy journeys pass within Core142 (137 Swift Testing +5 XCTest). Ten distinct new native UI journeys and seventeen existing affected journeys pass across the focused source-bound runs below. Earlier candidate failures and corrections remain chronological evidence below; they are superseded by this summary.

| Surface | Passing hosted run / source | Boundary |
|---|---|---|
| Manual action |40087688270 /04eda12|Capacity-only action preserves scan/navigation/selection|
| Scan completion and reopen |40087926668 /96939a7|38.086s; latest logical-scan ordering fix|
| Cleanup and historical independence |40088604768 /4cb9d57|47.906s; owned native Trash fixture, unchanged journal and History observations|
| Retry recheck terminal refresh |40087926706 /96939a7|45.615s; no new cleanup authority|
| Current states, initial/minimum |40088850738 /8869b38|2/2,71.096s; retained refresh, fallback/partial, stale failure, recovery|
| First-use states, initial/minimum |40088850882 /8869b38|2/2,103.776s; checking/unavailable/recovery/expiry/foreground|
| Shared Gallery, initial/minimum |40088850911 /8869b38|2/2,108.423s; inert seven-state examples in both themes|
| Existing affected regressions |40087127762 /8ea8f2d, then40088292227 /c741014|11 original passes +4 repaired-case passes; compact sidebar fixes actual minimum-window expansion|
| Overview findings and secondary tools |40087127755 /8ea8f2d|2/2; findings702.687s, tools37.097s|
| Additional alert-open replay |40088289965 /c741014|77.587s; overlaps existing regression count|

Final originals and unmodified export manifests: [current states](../visual/capacity-refresh/40088850738/manifest.json), [first use](../visual/capacity-refresh/40088850882/manifest.json), [Gallery](../visual/capacity-refresh/40088850911/manifest.json), [cleanup/History](../visual/capacity-refresh/40088604768/manifest.json). 71 originals:20+20+28+3. Final capacity captures use1024×640 initial (host display-clamped) and900×640 minimum; cleanup captures retain their original dimensions. No rescaling or contact-sheet substitution. The root individually reviewed all20 first-use originals: full labels, reserved card/status positions, honest absent/stale evidence, aligned sidebar, reachable action strip in Light/Dark; no remaining finding. All20 current-state and3 cleanup/History originals were individually reviewed in [final state review](capacity49-states-final-review.md); all28 Gallery originals in [final Gallery review](capacity49-gallery-final-review.md). No remaining changed-state visual blockers.

Source review found one missing retry-terminal hook, fixed in `a2f9686`; follow-up source review found no remaining actionable issue. A single-scan cancellation ordering race was corrected in `87de710`. Visual review independently caught a clipped native Refresh capacity label despite passing accessibility tests; `8869b38` preserves intrinsic button width inside a minimum144pt slot. Final recaptures replace the blocked earlier images. Exact unchanged window/Scanned locations positions are tested; changing glyph-tight AX Text width is not treated as scroll movement.

Controlled metadata and clocks qualify the refresh policy, not every macOS volume/API configuration. Hosted native proof uses macOS26/Xcode26.6; local build uses Xcode27.1. Gallery is synthetic. This does not certify actual iCloud/provider permissions, every browser, VoiceOver operation, signing/notarization, or clean installation. M8 commercialization remains deferred. No polling, background keepalive, alert-policy change, automatic file selection, or historical rewrite was added.

## Chronological implementation evidence

Historical lock checkpoint: contract locked October24,2026 in [CAPACITY-REFRESH](../CAPACITY-REFRESH.md). At that point implementation and public/native qualification were pending. Existing approved UI journeys remain the UI test seam; controlled service boundary explicitly approved by user on October24. No tests or native evidence are claimed by this lock.


## First public UI tracer

Test-only agent `ab42ba9`, root `8941c41`: explicit capacity refresh exists separately from Scan again and preserves Overview coverage/navigation/empty plan and fixed window. Guarded missing-action failure captures and returns promptly. Local build-for-testing passes. Production is unchanged. Hosted behavioral red `40083724345` at `8941c41` fails at line16 on the missing capacity-only refresh action (15.030seconds), as intended. Local/native app compilation and existing Core136 (131SwiftTesting+5XCTest) pass. The user subsequently approved the controlled-reading/clock service boundary; service-first TDD resumes from this observed UI red.


## Initial proof checklist (historical)

| Contract surface | Proof to record before acceptance | Status |
|---|---|---|
| Manual capacity action separate from scan | Public Overview action, unchanged coverage/selection/navigation/window | Actual missing-action red recorded |
| Launch/foreground30seconds/manual/alert-open | Public controlled service clock/readings; native entry/manual trigger composition | Subsequently qualified below |
| Logical scan finish/Stop/failure and cleanup terminal | App-level owned journey evidence plus service post-action freshness/trailing demand | Subsequently qualified below |
| Refresh/checking/failed-stale/unavailable/partial totals | Same shared live/Gallery native presentation in both themes/sizes, public service transition evidence | Subsequently qualified below |
|10second expiry/late responses/concurrent triggers | Controlled public service states without private-method or collaborator-order assertions | Subsequently qualified below |
| Historical/alert independence, window reopen | Recorded operation observations unchanged, existing alert/context regressions, retained process state without new keepalive | Subsequently qualified below |
| Source/metric/time and compatible comparisons | Explicit current evidence, no scope-volume substitution or history rewrite | Subsequently qualified below |

Real native capacity metadata is separate from deterministic fixtures. Inert Gallery examples certify presentation only. Record actual hosted capture dimensions; the initial preset may be display-clamped. Do not label unrelated suites rerun unless run; no new platform/signing certification is implied.

The original missing-action red PNG/manifest is preserved at `docs/visual/capacity-refresh/8941c41-red/`. Reviewed900×640 Automatic resolving Light: startup amount/time/important metric and ordinary findings are present, capacity card has no refresh affordance. This is before-state evidence only.


## Public service policy verticals

Agent checkpoint `caaef4f` adds five public capacity-service journeys, each after an observed failing policy cycle: launch publication; failure retaining prior evidence plus zero/partial metadata recovery; foreground30seconds/launch-idempotence/explicit triggers; overlapping requests with post-action trailing demand;10second expiry and late-reply rejection. Focused policy suite passes5/5 locally. Red/green logs are retained outside repo as `/tmp/capacity49-cycle1-red.log` through `cycle5-green.log`. Timeout red first reported public assertion failures then cascaded into fixture index failure; a test guard prevents that cascade. Do not describe the fixture crash as a production failure.

This is policy-seam evidence, not proof of app-level terminal-trigger wiring, native API behavior or UI state presentation. Root/native qualification remains pending.


## Native verticals after first candidate

First action candidate `40085800284` at `85833b4` reaches Refresh capacity, then fails a test lookup for configured coverage in the actual no-scope state (line21,9.710s). Test-only9f554e5 observes the existing no-included-locations text; `40086118769` subsequently reaches Plan but fails obsolete Nothing selected wording (line34,12.503s). Test-onlye110e6c observes the actual0-files-selected summary and disabled Review cleanup instead. Neither lookup failure is claimed as a product bug or successful journey.

Actual scan red `40085905164` at5702b58 fails post-scan capacity refresh atline75 (30.699s); its other test retains the already-known old lookup failure. Actual partial-state red `40085979730` at9c75e3c fails both initial/minimum atline132 because the sidebar loses available space without a total (17.400/14.730s). Candidate8f91540 fixes shared partial meter/state geometry and supplies inert Gallery states; f347206 adds once-per-logical-scan terminal requests. Local builds pass; four native journeys at40086277589 are pending, with the known older manual-test wording still present there. Current test-onlye110e6c corrects that assertion for the next run.

### Standards

Restricted Core review09e5c18..f347206: no actionable findings. Refresh policy stays behind the approved public OS/clock seam; tests exercise public evidence, controlled external callbacks and time. App/UI integration remains outside this review.

### Spec

The same restricted Core review found no actionable findings against CAPACITY-REFRESH.md: cadence, launch deduplication, trailing post-action demand, expiry/late-reply protection, retained success and partial metadata align. This does not qualify remaining app hooks or native presentation.


At `f347206`, `40086277589` passes the real scan-completion journey (29.756s) and Core142 (137SwiftTesting+5XCTest). The old manual assertion fails as already noted. Both native state cases fail exact observation-frame equality because Text's intrinsic glyph width changes305→291points with its content (samex/y/height); this is not evidence of window resizing or a scroll jump. Sourcee5c60ab reserves the full observation and native action regions without loosening the exact frame assertion. All four journeys rerun at that source; completion is pending.


Manual action finally passes12.337seconds and scan passes29.652seconds in `40086689374` at `e5c60ab`; Core142 also pass. That run still fails both state cases because native AX continues to expose tight Text glyph bounds despite the visual frame. Source0de4cae adds a meaningful containing observation group, preserves readable Text identifiers and measures the group's exact frame across states instead of glyph bounds; no tolerance/hittable-only substitute. Cleanup red `40086787640` at5ce83b9 fails the actual post-cleanup current reading (line112,42.663s). Source8ea8f2d requests a new current reading after execution.run and supplies actual app activation/alert-open triggers; recorded capacity pairs are untouched. Native5journeys, existing affected regressions9 and Overview2 are in qualification at8ea8f2d.

Policy red/green logs are additionally preserved outside repo under `notes/capacity49-evidence/` in the implementation cache. Six focused public-policy journeys pass; the sixth is qualification of existing expiry/trailing behavior, not a new failing-cycle claim.

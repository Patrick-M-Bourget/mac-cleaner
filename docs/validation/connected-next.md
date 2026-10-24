# Mixed scopes and inspector evidence

October 23, 2026. Tracking #58 (parent #46) and #59 (parent #47); approved FLOW-LOCK/proposal b96bb97. Baseline integration `5a9d588` is the qualified first Downloads slice. Candidate work remains isolated on `verify/connected-parity-next` until the gates below pass.

## Source and public checks

Latest application source `9264d7a66f641189294f8e0ef0b0b6b586c0dc98` adds the current-status access guidance fix. Inspector/full Downloads regressions ran at `f233d105bc076f75ce2c55442def5b0ab13f1e83`; earlier mixed-only run `ef54d49` differs from f233d10 only by the inspector inset and failure diagnostics. Public app/scanner/executor seams are the previously approved boundaries. Tests use owned disposable files and isolated settings; no personal files or OS permissions are changed.

| Native run | Source | Observed outcome |
|---|---|---|
| 40054138889 | 833b09f | Initial red: missing Why listed and limited-coverage copy. Mixed failure exposed guarded DEBUG fixture classifier recognizing only exact root, not descendants; production classification already handles descendants |
| 40054231055 | 4358044 | Additional red: outside-Downloads/protected inspector explanations missing |
| 40054702929 | da235c2 | Mixed initial pilot and Gallery pass; inspector reaches new evidence but old native scroll identifier query fails |
| 40054915485 | 45ffc1a | Actual owned SQLite red: specific protected-file reason missing; outside case still old scroll query |
| 40055144175 | dac832d | Strengthened mixed initial pilot passes, not full #58 proof |
| 40055727927 | b3d570e | Gallery passes; both inspectors fail strict text containment; both full mixed journeys stop at XCTest shorthand identifier length limit |
| 40056524171 | ef54d49 | FAIL: both advance through reconnect; below-viewport lazy B checkbox is not instantiated before the generic reveal helper checks existence |
| 40057507530 | badca19 | RED reproduced both sizes: exact stale B access notice remains after independently observed three-file eligibility. Public search reveals exact checkbox rows without assuming offscreen lazy existence |
| 40058146619 | 9264d7a | Final full mixed initial/minimum verification pending |
| 40058178176 | 9264d7a | Existing scope-guidance regression pending |
| 40058179409 | 9264d7a | Existing unavailable-location regression pending |
| 40056586166 | f233d10 | PASS: both owned inspector journeys (124.47s), including actual SQLite reason, strict visible restriction frame, reachable Close and explicit selection/confirmation Cancel |
| 40056609812 | f233d10 | PASS13/13 (741.69s): initial/minimum connected execution/results/History/relaunch, contextual prerequisite, scope guidance/recovery, refresh, three checkbox anchors, keyboard Cancel/focus and retry |

The native scroll identifier is `explorerInspector`; native selectable text can extend its accessibility frame beyond the glyph origin. The shared horizontal `Space.xs` inset retains strict viewport containment checks. Exact path identifier predicates address XCTest's 128-character shorthand limit without changing identity or weakening the journey. Failure-only frame/AX/capture attachments remain available for diagnosis. The ef54d49 final native AX state independently shows three eligible files/six bytes and an obsolete B access notice; #58 adds an exact recovered-state regression for that real display bug, separate from the lazy row lookup correction. After the exact red reproduced at both sizes, the model stopped storing access errors as obsolete generic copy: guidance now derives from current included-scope recovery status, while general notices remain separate. Resolving one scope cannot erase another failed scope's status or authorize old observations.

## Changed behavior and proof boundaries

- **#58 / S01–S05, N08, FL05/FL06/FL09:** shared adaptive LocationScopeRow labels remembered ancestor/descendant overlap; configurations stay independent, storage is not naively summed. Recovery actions retain full labels and fall below identity/status at compact width. Full owned journeys exercise valid A with unscanned/unavailable B, pending Review blocking, explicit reconnect, picker Cancel/wrong-location, omission/re-inclusion, conditional Forget and independent overlap/hardlink membership with deduplicated bytes. Original file bytes and window/checkbox frames are asserted.
- **#59 / F05/F06, N08:** structured observed location/scope/time, why listed, logical/on-disk sizes and action/consequence. Specific restrictions distinguish ordinary outside-Downloads files, folders, packages, links, protected file types, cloud/unknown-locality and stale/unavailable evidence. The typed protected path reason shares Core's existing exclusion list and does not expand eligibility. Inspection alone never selects; explicit selection → Plan → confirmation Cancel preserves original bytes.
- Close stays outside the bounded evidence scroll and the action footer remains a sibling. Existing explicit Quick Look/Reveal gates and shared search/Back/selection context remain unchanged. Synthetic Gallery states cover unavailable metadata without claiming genuine File Provider behavior.

## Native visual evidence

[Seven original Gallery captures](../visual/connected-next/b3d570e/manifest.json) from the passing Gallery test in otherwise failed run 40055727927 preserve native Light/Dark minimum900×640 examples and opaque Dark chrome. Hashes, original attachment names, dimensions and source/run are in the manifest. Reviewed recovery captures show full Choose again / Reconnect and recheck labels, overlap text and disabled omitted-row control. The target-based Gallery capture scrolls the row heading above the viewport; it proves action-label rendering, not complete row-context review. Owned journey captures must additionally show the actual full recovery context.

[Fourteen original inspector captures](../visual/connected-next/f233d10/manifest.json) from40056586166 were reviewed in Light/Dark: minimum900×640 uses a bounded lower inspector; initial1024×640 uses the side inspector. Structured paths wrap in their bounded pane. Specific SQLite/outside-Downloads/package/folder/link reasons are readable when scrolled; Close and fixed View cleanup plan remain visible. The compact pane intentionally scrolls its evidence; a top screenshot alone does not show every field. Original native test assertions verify restriction containment/hit testing and successful Close, not screenshots alone. Shared near-black/white reading surfaces, subdued summary plane and explicit selection/info separation are retained. Minimum and initial dimensions follow the current runner's available display, not fabricated web dimensions.

[Thirty-one original regression captures](../visual/connected-next/f233d10-regressions/manifest.json) from the13/13 passing run preserve initial/minimum Downloads prerequisites/populated plan/inspector/results/empty states, minimum access recovery and updated shared Gallery in both themes. Representative inspector/plan/recovery captures were reviewed: the real compact recovery row now shows its identity/status and full action labels without ellipsis; the original white sidebar and stable sibling action strip remain. Behavior proof is the passing native journey, not a claim of pixel identity with the web prototype.

Mixed-location originals, remaining green runs and final integration status are pending. Native OS permission revocation, disconnected-volume/File Provider behavior, older OS/CPU and manual VoiceOver qualification are separate gates. No new adapter or M8 work; parent #44/#46/#47/#48/#50/#45 and all future milestones remain open.

## Source review

Parallel standards/spec reviews against `5a9d588` found no source blocker. Spec reviewed through ef54d49; standards through f233d10. Nonblocking standards observations: repeated inspector restriction lookup and view-local lexical overlap classification; neither introduces new authority or a documented-standard breach. Both axes additionally reviewed the current-status access guidance fix and found no blocker: Observation tracks current scopes/statuses/notice, other failed included scopes remain represented, and no scan/selection authority changes. Final native evidence is still a merge gate.

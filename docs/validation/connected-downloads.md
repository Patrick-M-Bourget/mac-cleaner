# Connected Downloads journey

October23,2026. Approved: [FLOW-LOCK](../FLOW-LOCK.md), proposalb96bb97 and [design review](../CONNECTED-FLOW-DESIGN-REVIEW.md). Tracking: #55 → #56 → #57; parent#45. Application candidate: `824328f799df3d00c046c6ac623b473650eb303d`; later changes are tests/docs only.

**First Downloads slice qualified.** Final existing-flow regression40051984202 passed5/5. The evidence below qualifies #55–#57 across explicit source boundaries, not a single full-suite green run or complete prototype parity.

## Implemented behavior

- Stable Cleanup plan: summary → contextual Downloads category/prerequisite → collapsed inline refinement → fixed Review. No permanent setup chooser. Scans stay on their initiating screen and never select files.
- Remember explicitly granted scopes/inclusion only. Add never scans; Quit restores no observations, selections or authority. Manual scan, selection, preview, retry and execution resolve guarded grants; stale/moved/unavailable access never silently renews.
- Macro and inline choices share exact immutable confirmation/execution. Cancel retains membership. Selected pending files block review until checked or deliberately deselected; independently valid evidence stays usable.
- Explorer browses observations only, with folders, breadcrumbs, descendant search/no matches, separate adaptive inspector and caller-aware Back. File inspection, folder navigation and selection remain separate actions. Process context survives navigation; sidebar entry invents no Back chain.
- Refresh keeps observed names/query visible, explicitly suspended. Stale rows cannot be newly selected; selected pending rows remain checked and recoverable. Changed targets clear with an explanation; discoveries stay unchecked.
- Failed access remains Unknown after its scan is retired. Included-but-unscanned locations prevent complete coverage; omit removes current evidence, re-inclusion needs manual checking. Empty completed findings name their inspected scope.
- Results offer History/new plan. Consumed authority cannot execute again; a new plan is unselected and requires a fresh manual scan.

Shared APIs are documented in DESIGN-SYSTEM: CategoryPrerequisite, ToolbarScanStatus, LocationScopeRow, ExplorerInspector and native viewport restoration. Selection/coverage/overlap policy lives in models rather than View formatting.

## Verification

Local Xcode27.1 build-for-testing succeeds at824328f; preserved app bundle passes ad-hoc signature verification. Core:131 Swift Testing +5 registry XCTest =136 tests pass, including unchanged exact overlap rebinding, expired proof, root-symlink rejection and malformed storage recovery. Local UI automation cannot initialize (timeout before assertions); native journey proof uses hosted macOS26/Xcode26.6 and disposable fixtures only.

| Run / source | Result and boundary |
|---|---|
| [40050266396](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40050266396) / caf6375 |13/13 expanded cases pass before the stronger refresh-retention assertion. Includes both complete journeys, retry, scan-away/Stop, keyboard focus and all anchors. |
| [40050359141](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40050359141) / caf6375 |3/3 exact-frame tests pass: category/individual plan choices, Explorer choices and scrolled category. Optional initial offset fixes the reproduced52pt AppKit inset displacement. |
| [40050757234](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40050757234) /39832ca |Intentional red: expanded refinement disappears during refresh. b1702ef retains prior displayed observations without restoring selection authority. |
| [40050922744](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40050922744) /b1702ef |12/13 pass, including both complete journeys and all anchors. Refresh passes retained-search/query assertions but looks for an unmaterialized offscreen lazy row. Native video shows1file/3bytes retained; this is not treated as a green run. |
| [40052574336](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40052574336) /f5f1d06 |Strengthened refresh test passes: scroll row into view, exact checked1/disabled state during scan, Cancel/return, unchanged recheck, changed target unchecked, query/bounds and original bytes preserved. Application source equals824328f. |
| [40051942964](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40051942964) /19fd3d1 |Minimized intentional red: initial1-byte/1-eligible Downloads observation succeeds, then missing root incorrectly loses Unknown. |
| [40051982017](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40051982017) /824328f |Same public unavailable test passes with corrected coverage. No false No eligible files. |
| [40052410048](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40052410048) /4ed88cc |Unavailable/recovery test passes with current minimum Light/Dark captures, exact window bounds, historical evidence and explicit Choose again. Application source equals824328f. |
| [40051984202](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40051984202) /824328f |5/5 pass: Recovery3, Growth and600-file Overview regression, including both sizes (992.6s total; Overview768.8s). Recovery queries its stable summary identifier; Growth observes its own completed state rather than an Overview-only button. |

The complete journey uses real disposable files: contextual scan → unchecked real findings → macro/individual selection → Explorer descent/search/no matches/Back → exact confirmation Cancel → native Trash results → History/new plan → relaunch with configuration only → manual scan/complete empty → omit/reinclude. Inspectors are tested beside the list at initial size and as bounded panels at minimum. Retry and original byte/journal safety checks remain intact.

Earlier broad run40047017039 found the corrected Recovery/Growth queries, plan inset, unavailable identifier and large-list path. Unaffected retry/diagnostics/exclusions/history/managed inventory/alerts classes passed there; it was not a full-suite success. The Explorer row-highlight optimization removes repeated full snapshot sorting; run40050435403 then completed browsing/search/partial-coverage checks before exposing the separately fixed unavailable-coverage failure. Run40051875862 used an invalid fixture name and was cancelled, not counted as diagnostic proof.

## Native visual record

- [b1702ef originals](../visual/connected-downloads/b1702ef/manifest.json):25 captures from passing journey/Gallery cases, actual1024×640 initial and900×640 minimum. Reviewed unscanned/header, useful/empty plan, results, wide/compact inspector and opaque Gallery in Light/Dark. The old clipped heading is absent; empty coverage is named, Light sidebar is white and fixed actions stay reachable.
- [4ed88cc originals](../visual/connected-downloads/4ed88cc/manifest.json):4 minimum Light/Dark unavailable/recovery captures. Unknown and historical evidence remain distinct. Compact Reconnect and recheck is visually ellipsized although the full accessible control name remains available; shared adaptive action layout is explicitly included in#58.
- [f5f1d06 originals](../visual/connected-downloads/f5f1d06/manifest.json):5 refresh captures, including the checked/disabled retained row, cancelled refresh and changed target in both themes. Explicit scrolling is recorded, not retouched out of the evidence.
- [ffd11f7 intermediate originals](../visual/connected-downloads/ffd11f7/manifest.json) remain historical; its initial unscanned capture contains the old inset bug and is not accepted final geometry.

All manifest image hashes and local documentation links verify. PNGs are original native captures. Hosted display constraints did not allow the requested1120×760 initial size; the record never substitutes requested for actual dimensions. Browser typography is not a pixel contract or native accessibility certification.

## Review and remaining scope

Standards axis: no remaining documented blocker after extracting observation policy from View and replacing status-copy branching with typed AccessStatus. Two viewport bridges remain a nonblocking duplication concern with different restoration events; do not consolidate on source speculation after exact anchor tests pass.

Spec/safety axis: no new blocker at824328f in balanced leases, exact unchanged overlap membership, omit/Forget distinction, guarded reset, refresh display/current-authority separation or no-authority relaunch/new plan. Source review does not certify native OS behavior.

Original #44/#46/#47/#48/#50 and audit#45 remain open beyond this first slice. Next accepted dependencies: #58 mixed locations/access/overlap (including compact action layout), #59 structured inspector evidence. Caller-aware History recovery return remains on#48. Remaining #49/#51–#54 decisions and all future milestones are preserved.

Real permission revocation, File Provider/iCloud behavior, supported OS/CPU, VoiceOver and broader FL01–FL14/overlap qualification remain separate gates. No personal files were cleaned, no adapter was promoted and no M8 distribution work was required. PR36 stays draft for the broader specification.

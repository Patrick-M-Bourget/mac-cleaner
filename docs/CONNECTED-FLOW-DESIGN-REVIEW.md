# Connected flow visual review

October 23, 2026. Flow and presentation choices Q1–Q30 are user-approved in [FLOW-LOCK](FLOW-LOCK.md). **The user approved the annotated visual proposal on October 23, 2026 (“seems good”).** The visual checkpoint is complete; native implementation and proof remain outstanding.

## Review artifact

- [Self-contained interactive prototype, source b96bb97](https://github.com/Patrick-M-Bourget/mac-cleaner/blob/b96bb97/docs/prototypes/connected-flow-review.prototype.html). Download/open the HTML locally; GitHub's source view does not execute it. No server, dependencies, network assets or real data are required.
- [Prototype notes and limits](https://github.com/Patrick-M-Bourget/mac-cleaner/blob/b96bb97/docs/prototypes/README.md).
- [All 60 browser-rendered views and hash/dimension manifest](https://github.com/Patrick-M-Bourget/mac-cleaner/tree/b96bb97/docs/prototypes/flow-review-captures).

The throwaway HTML and renders are preserved on `prototype/connected-flow-review`, outside the production integration branch. The real implementation remains SwiftUI/AppKit. This document and FLOW-LOCK retain the approved intent; do not ship or port the preview HTML as application code.

The review page supplies state/theme/window controls, annotations, a readable state summary and guided walkthroughs. All review controls are outside the app frame. Ordinary app controls use the same in-memory state model. Grants, folder choice, scanning, file contents, Finder, Trash and Quit are simulated. Remembered locations in the preview do not persist to disk. Local-record/diagnostic entry is annotated rather than fully simulated. Its caller-aware native composition belongs to #48/#62: the current candidate reuses shared Local records from History and Locations, recovery returns to that page, and future-gated diagnostics returns directly to the actual root caller. Candidate presentation source `dadc0c1` and earlier route/Overview regression greens are tracked in [Local records qualification](validation/local-records.md); final native verification at `f8a0c86` remains pending. Neither this review prototype nor those earlier greens declare final integration or full parent acceptance. The preview does not resolve #49/#51–#54 or full future capability gates.

## What to inspect

| Area | Visual/flow anchors | Reference views |
|---|---|---|
| Plan before scan | Stable summary/category/footer; Not scanned and disabled macro checkbox; Scan Downloads lives in category, no global setup banner | FL01 initial/minimum, both themes |
| Useful empty selection | Real fixture count/size; quiet Nothing selected; Choose items collapsed; Explore secondary; review disabled | FL02 |
| Selected/mixed | Same composition; exact membership and logical size; inline refinement, separate deeper inspection | FL03 |
| Empty/partial/pending | Empty is not unknown; limited coverage explicit; retained choices, recheck/deselect escape, fixed blocked review | FL04–FL06 and FL08 |
| Persistent scan status | Compact toolbar progress/Stop; Return to scan only away; location editing disabled; completion never navigates | FL07 |
| Locations | Inclusion checkbox, folder/path, explicit status, direct recovery, secondary Forget; no automatic scan from Add | FL09 and OVL |
| Explorer | Folder entry versus info/file inspection; search scanned descendants; honest no matches with no stale inspector | FL10–FL11 |
| Responsive inspector | Right-hand detail with independent scrolling when wide; compact bounded panel above fixed footer, close/action controls reachable | FL11 at1120×760 and900×640 |
| Retry/results/reopen | Explicit broad-scan boundary; consumed results → History/new plan; remembered location does not restore current findings/selection | FL12–FL14 |

The OVL fixture demonstrates exact selection retention when a parent location is forgotten but an included completed child independently supports one chosen file. It is additional review coverage beyond FL01–FL14, not a new feature.

## Guided review paths

1. **First scan:** start with no location → contextual access choice and scan → complete simulated scan from review controls → six eligible files → exact review → Cancel retains choices.
2. **Shared selection & Back:** mixed plan → Explore Downloads → Media folder → inspect file → View cleanup plan reuses the existing ancestor; no Back loop.
3. **Unavailable choices:** one pending selected file blocks review → deliberately deselect unavailable → review remaining exact file → Cancel → manage locations.
4. **Retry & new plan:** unfinished-only review → explicit all-Downloads scan → retained choice/new discoveries unchecked → exact preview outcome → new unselected plan requiring manual scan.

Sidebar entry is direct. Overview→Explorer→plan retains a contextual return; plan→Explorer→plan reuses its ancestor. Query/folder/inspector/viewport are session context, separate from shared exact membership.

## Design vocabulary

Keep the approved white Light sidebar and reading plane, near-black Dark surfaces, understated chrome, muted orange/blue/teal category cues, 190-point sidebar, 26-point page hierarchy, shared spacing and fixed action region. Samples are explicitly marked. This is one coherent proposal for the agreed design, not a set of alternative brands or layouts.

In native implementation, add missing recurring patterns to DesignSystem/Gallery first: shared toolbar scan status, location inclusion/status/recovery row, contextual category prerequisite and responsive inspector. Preserve actual platform focus/semantics rather than copying CSS/control metrics. No selection-only layout animation, destination resize, automatic scan or duplicate selection action is introduced.

## Render and interaction evidence boundary

The render pass produced 60 views: 14 FL states plus overlap × Light/Dark ×1120×760/900×640. Its manifest records exact HTML hash, browser version, image hashes, dimensions and reported content/footer geometry. No page script errors, horizontal content overflow or out-of-window footer was reported. Those checks are browser layout observations, **not native app tests or OS/accessibility certification**.

Representative originals were visually reviewed for ready/unscanned/pending plan, unavailable locations, scan away from origin, wide/compact Explorer inspector and results. A compact-inspector issue was corrected before final preservation so its content/actions stay above the fixed footer. Remaining files are available for review; no claim of complete native state certification is made.

Public preview controls were exercised for ancestor reuse, Select all→confirmation Cancel preserving six choices, and overlap Forget identifying one dependent choice while retaining the independently supported one. Native permission, persistence, provider, journal and Trash behavior remain subject to the existing public-boundary and real integration gates. Production app code is unchanged by this review.

## Approved delivery direction

Q30 prioritizes a coherent visible Downloads journey over finishing isolated technical components. The first slice includes remembered explicit Downloads configuration, contextual plan scan, macro/inline selection, Explorer round trip, exact confirmation/Cancel, results and fresh new-plan boundary. Necessary route/registry foundations may be built first but do not constitute feature completion.

Next slices finish multi-location configuration, overlap/Forget, access recovery, scanning away from origin and every blocked/empty FL branch. Keep #44/#46/#47/#48/#50 open until their full acceptance is actually proven. Other feature tickets and milestones remain preserved. Do not detour into M8 or require the full roadmap for M1.

After visual approval, turn this into dependent implementation slices with parity IDs + FL states, shared-component/gallery work, specific public journey checks and original native Light/Dark initial/minimum capture requirements. Any divergence returns to SPEC/handoff review rather than becoming an undocumented shortcut. Visual approval of this preview does not waive native checks.

## Status

- [x] User approved Q1–Q30 flow, presentation and delivery decisions.
- [x] Annotated states and one interactive review proposal prepared in the approved visual language.
- [x] Synthetic render/interaction observations preserved with source/hash boundaries.
- [x] User visual approval of proposal b96bb97, October 23, 2026.
- [x] Dependent implementation slices published as #55 → #56 → #57 under #45.
- [x] Complete native first-slice validation; see [connected evidence](validation/connected-downloads.md). Full connected parity remains on the original repair tickets.

- [x] Bounded #58/#59 mixed-location/overlap/access and inspector slices qualified; [native source, full journeys and originals](validation/connected-next.md). Wider parent acceptance remains open.

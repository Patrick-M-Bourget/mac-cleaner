# Connected product flow lock

Approved October 23, 2026: user accepted grilling Q1–Q25, explicitly confirmed the consolidated contract in Q26, and accepted presentation/delivery Q27–Q30. Applies to #44, #46, #47 and #48, plus the results boundary in #50. These are approved product requirements, **not implemented capability claims**. The [parity audit](PROTOTYPE-PARITY.md) retains the baseline and open gaps. Presentation and delivery decisions are locked below; the annotated visual proposal b96bb97 was user-approved on October 23, 2026. No repair is implemented or qualified by approving a flow.

SPEC and DESIGN-HANDOFF reference this same contract. It supersedes conflicting global plan-chooser, flat explorer and hard-coded return descriptions. Safety and M1 scope remain unchanged: exact eligible Downloads files only, no automatic scans/cleanup, no whole-folder targets, no broader adapter mutation. Future milestones and #49/#51–#54 remain preserved; appearance persistence and History scan-activity decisions are not decided here.

## Approved decision trace

| Decision | Approved behavior |
|---|---|
| Q1 | Overview starts general scans; Locations manages included scopes; a category can start a contextual prerequisite scan. The initiating screen remains visible through progress/completion. |
| Q2 | Remember chosen locations and inclusion preferences across Quit. Recheck access before scanning; remembered configuration restores neither current findings nor cleanup authority. New launch has no cleanup selection. |
| Q3 | Explorer has a selected-locations root, folder navigation/breadcrumbs, scoped search and separate inspector. Browse existing observations only; never silently scan new scope. |
| Q4 | One plan hierarchy: summary → Downloads category → fixed review action. Before scan: Not scanned, disabled checkbox, contextual scan action. Useful scan: real count/size, checkbox and Choose items initially collapsed. No permanent global setup banner/chooser. |
| Q5 | Scan Downloads rechecks configured included Downloads scopes, or explicitly requests Downloads access when none exists. Arbitrary locations belong in Locations. A limited subfolder scan must not be labelled all Downloads. |
| Q6 | Inclusion and Forget are separate. Excluding retains location configuration and suspends dependent choices. Forget explicitly removes choices supported solely by that location; independently supported overlapping choices survive. Re-inclusion requires a fresh check. |
| Q7 | Folder name enters; separate info action inspects folder. File name inspects. Checkbox selects. Breadcrumbs/Back navigate folder history before returning to the originating screen. |
| Q8 | Search current folder plus its scanned descendants, labelled as such, with relative paths. No matches hides stale inspector and offers Clear search; membership is unchanged. |
| Q9 | View cleanup plan from Explorer offers contextual Back to Explorer restoring folder/query/inspector/viewport. Direct sidebar entry has no manufactured Back chain. |
| Q10 | Complete empty = No eligible files. Incomplete/denied/disconnected = specific unavailable reason and recovery. Retained choices stay visible but blocked until checked; independent valid locations remain usable. |
| Q11 | Explorer prioritizes allocated On disk size; inspector also shows logical size. Folder totals use only existing observations, deduplicate resource allocation within that total, and state unknown/partial coverage. Plan logical size remains separately labelled. |
| Q12 | Retain explicitly added overlapping locations and label overlap. Never silently remove their configuration or sum overlapping scopes as independent storage. Distinct hardlink paths remain distinct targets; byte totals deduplicate resources. |
| Q13 | Navigation remains available during manual scans. Persistent scan status provides Stop and return to origin. Completion updates observations without navigating. Scope editing is disabled during a running scan. |
| Q14 | Unavailable remembered locations offer Choose again or Reconnect and recheck, plus omit. Request access only from that explicit recovery action; other valid locations remain usable. |
| Q15 | Retry offers Review all Downloads… as an explicit new manual scan leaving unfinished-only restriction. Retain unfinished choices for validation, leave new discoveries unchecked and never automatically carry completed successes. |
| Q16 | Review Downloads opens a category view across included scanned Downloads scopes, with limited coverage explicit, exact duplicate entries merged and nothing automatically selected. It must not pick an arbitrary first scan. |
| Q17 | Contextual Back returns to the real caller. History recovery → History; History/Locations local records or diagnostics → caller; Overview Explorer → Overview; Explorer plan → Explorer. Automatic startup recovery returns Overview. Sidebar navigation is direct. |
| Q18 | Any selected pending/unavailable target blocks Review cleanup until validated or explicitly deselected. Offer Deselect unavailable files and individual controls. A failed location with no selected targets does not block independently valid choices. |
| Q19 | Forget confirmation only when choices would be removed: name location and affected selection count. Unused locations can be forgotten directly. Forget never deletes files. |
| Q20 | Results are a separate destination under plan. View history and Start a new plan are explicit. New plan or sidebar plan after completion is unselected and needs a fresh manual scan; never reopen consumed work as executable. |
| Q21 | Add folder remembers it and includes it in the next manual scan; adding/configuring never starts a scan. Existing independently valid observations remain usable; new scope is Not scanned. |
| Q22 | With mixed coverage, complete valid scopes can supply selectable eligible files. Describe inspected coverage and exact eligible count; unknown/unscanned parts are never implied to be empty or included in Select all. |
| Q23 | Enter folder at top with empty search and no previous inspector. Back restores parent query/inspector/scroll. If the inspected identity disappeared after refresh, clear it. |
| Q24 | Inline Choose items is primary plan refinement; Explore Downloads offers deeper review. If plan is already the Explorer's ancestor, View cleanup plan returns to it rather than pushing a duplicate route. |
| Q25 | Navigation/query/disclosure/inspector/viewport state survives navigation/window closure while process lives, then clears on Quit. Remembered configuration and durable history/recovery are separate. Launch opens Overview unless recovery needs review. |
| Q26 | User confirmed this consolidated flow contract; synchronize specs/tickets and prepare annotated states/implementation sequence before coding. |
| Q27 | Compact shared toolbar scan progress, Stop and Return to scan while elsewhere; existing content stays visible with truthful refreshing state. No full-page spinner or completion navigation. |
| Q28 | Explorer uses a right-hand inspector when room permits; at compact widths the same detail is a bounded panel. Opening it preserves list position and outer window geometry. |
| Q29 | Location rows expose inclusion checkbox, folder/path and explicit status, with direct recovery only where needed. Forget is a secondary menu action and keeps Q19's conditional confirmation. |
| Q30 | First visible milestone is the complete remembered Downloads → plan scan → category/inline selection → Explorer round trip → confirmation/Cancel → results → new-plan journey. Then finish multi-location/overlap/access branches; a first demo is not full ticket/parity completion. |

## Screen responsibilities and return behavior

| Screen / entry | Primary responsibility | Scan or review result / Back |
|---|---|---|
| Overview | Current observed capacity, included/scanned coverage, four truthful informational categories | General scan stays here. Explore enters selected locations; Downloads review enters scoped category view. |
| Cleanup plan, direct | Category selection and inline refinement, exact consequence review | Contextual scan stays here. Direct entry has no Back. Selection never starts cleanup. |
| Cleanup plan, from Explorer | Same plan, with caller context | Back restores Explorer unless plan was already an ancestor, in which case reuse it without a cycle. |
| Locations & access | Remember/include/omit/forget/add/renew explicit scopes; access and coverage | Configuration does not scan. Explicit Scan selected locations stays here. |
| Explorer | Navigate/search existing scoped observations, inspect evidence, shared live selection | Directory history unwinds first. Final Back returns caller with saved context. No filesystem discovery from browsing. |
| Results | Per-target outcome, actual returned Trash paths, estimates vs observed capacity | View history; Start a new plan without automatic scan. Plan sidebar does not reopen executable consumed work. |
| Recovery | Durable facts and unresolved outcomes, no automatic repeat | Caller-aware Back for manual entry; Return to Overview for startup entry. |
| Local records / diagnostics | Existing guarded maintenance or redacted review/local Save | Return to actual History/Locations caller; existing milestone gates remain. |

Route reuse must prevent Plan → Explorer → Plan → Explorer cycles. A sidebar choice enters that primary destination directly; it is not a push onto the contextual Back stack. No completion callback changes destination, resets viewport or creates an approval. Explorer never enters protected packages or crosses unscanned/volume/link boundaries to imitate a file manager.

## Annotated behavior states

These annotate approved behavior, not new visual mockups. All must use the existing white/near-black palette, quiet category accents, shared components and stable native geometry. Presentation choices Q27–Q29 are confirmed. The [annotated visual review](CONNECTED-FLOW-DESIGN-REVIEW.md) renders this contract; proposal b96bb97 is user-approved for implementation.

| State ID | Evidence and category presentation | Available action / outcome |
|---|---|---|
| FL01 — no Downloads observation | Stable plan summary; Downloads Not scanned; no fake count/amount; checkbox disabled | Scan Downloads / explicit access request; stay on plan, nothing selected |
| FL02 — useful scan, zero selection | Real coverage/count/logical size, unchecked category, collapsed Choose items | Select category or refine inline; Review disabled until an exact eligible choice exists |
| FL03 — selected/mixed | Same hierarchy, shared exact membership, Selected for Trash consequence | Inline refinement, Explore Downloads and bounded Review; Cancel restores choice/focus/context |
| FL04 — complete empty | No eligible files within named inspected coverage, not a global clean bill | Manual recheck or manage locations; no fabricated eligible checkbox |
| FL05 — mixed/partial/unavailable coverage | Separate known complete eligible subset from unknown/inaccessible parts | Select valid observed targets; targeted recovery/omit; pending selected targets block review |
| FL06 — selected pending | Retained identities and explicit blocked reason, no approval from stale observations | Recheck or deliberately Deselect unavailable files/individual choices; no implicit omission |
| FL07 — scanning/Stop | Previous observations explicitly refreshing, new scopes unscanned/preliminary, no fake zero flash | Persistent Stop/return-to-origin, navigation allowed, scope editing disabled; completion never navigates |
| FL08 — cancelled scan | Retain choices and required-refresh evidence, no completed baseline implied | Explicit recheck; unaffected independently valid observations remain usable |
| FL09 — remembered scope unavailable | Location-specific access/disconnected status, no inferred grant | Choose again / Reconnect and recheck / omit; no automatic permission escalation |
| FL10 — no Explorer matches | Query/scope explicit; no stale inspector, no false empty-folder claim | Clear search in same context; preserve hidden selections |
| FL11 — folder descent/Back | Observed child folder only; new context starts clean | Breadcrumb/Back restores parent state; info inspects, checkbox selects |
| FL12 — targeted retry | Only validated unfinished identities, completed successes excluded | Fresh exact approval, or explicit Review all Downloads… scan boundary; discoveries unchecked |
| FL13 — completed run/new plan | Separate per-target results and recoverability, consumed authority | View history / Start a new plan; unselected category workspace needs manual fresh scan |
| FL14 — quit/reopen | Persistent location configuration, durable records; no live findings/plan restored | Overview, or startup recovery if needed; manual scan required |

## Design review and delivery checkpoint

**Flow and presentation decisions Q1–Q30 are locked.** Implement the approved [annotated visual states](CONNECTED-FLOW-DESIGN-REVIEW.md), using the existing approved palette/components rather than unrelated variants. The review prototype is synthetic, isolated from production code and preserved on a prototype branch. It illustrates intent, not native geometry, platform support or filesystem evidence. User approval of its visual states is recorded; original source-pinned native Light/Dark initial/minimum proof follows implementation before UI merge.

Delivery is a connected user-visible slice: remembered Downloads → contextual plan scan → category/inline refinement → Explorer with return context → exact confirmation/Cancel → results → explicit new plan. Route/state and remembered-scope foundations may be implemented first as needed; do not call isolated helper work the completed feature. Subsequent immediate slices complete multi-location/overlap/access recovery and every FL branch. All acceptance remains on #44/#46/#47/#48/#50 until actually proven. Annotated visual approval is complete (b96bb97, October 23, 2026); proceed with the agreed connected slice without introducing further product questions.

Do not resume unrelated isolated feature work. Every slice names parity IDs and FL states and preserves the approved responsibilities above. #49 capacity freshness, #51 scan-history product contract, #52 growth, #53 shell/appearance and #54 archive guidance remain visible in their milestones; this lock does not silently resolve or remove them. M8 signing stays deferred.

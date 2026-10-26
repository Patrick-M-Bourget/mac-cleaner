# Still — design and interaction handoff

Native UI implementation follows the mandatory [design system](DESIGN-SYSTEM.md).

Revision 0.9 · October 22, 2026 · Companion to [SPEC.md](SPEC.md).

## Prototype parity checkpoint — October 23, 2026

The [parity audit](PROTOTYPE-PARITY.md) traces current gaps and retained future capabilities. User-confirmed grilling Q1–Q30 now locks the connected [product flow contract](FLOW-LOCK.md) for #44/#46/#47/#48 and the results boundary in #50. These are approved requirements, **not implemented parity claims**.

The plan retains a stable category workspace with contextual scan prerequisites; Locations manages remembered explicit inclusion; Explorer navigates existing observations and shares selection; contextual Back preserves caller state without cycles. Scans never navigate on completion. Selected pending files block approval until checked or deliberately deselected. Completed runs lead to separate results and a fresh unselected new-plan boundary. See FLOW-LOCK for every decision, return route and FL01–FL14 state.

Presentation/delivery decisions and the [annotated visual proposal](CONNECTED-FLOW-DESIGN-REVIEW.md) were approved by the user on October 23, 2026. Connected implementation may proceed in the agreed Downloads-first sequence; do not re-grill settled flows or resume isolated screen work. Keep the approved white/near-black native design, existing shared components and all future milestones. Remaining #51–#54 decisions/gates are preserved; #49 now follows the separately confirmed capacity contract below. None is a blanket prerequisite for M1. M8 remains deferred. The first connected Downloads implementation (#55 → #56 → #57) is qualified by [source-bound native evidence](validation/connected-downloads.md), including existing-flow regression. Qualified slices #58/#59 cover mixed-location/access/overlap and structured inspector evidence; original full parent parity remains open. Failed access remains unknown coverage after its old scan is retired; remembered included locations without current observations prevent a complete-coverage claim. Omitted locations do not contribute current coverage, and re-inclusion requires a fresh manual check. Locations labels remembered ancestor/descendant overlap without removing configuration or summing shared storage twice. At compact widths, shared recovery actions move below identity/status to keep their labels readable. Successful access renewal retires that location's obsolete access notice; other included locations retain their own current failures. The Explorer inspector separates observed location/scope/time and sizes, why listed, cleanup action/consequence and specific protection/unavailable reasons; inspection never selects or authorizes cleanup. Protected file-type/location explanations come from the same canonical policy that excludes those paths, without changing eligibility. Native qualification of these #58/#59 additions is recorded separately in [connected next-slice evidence](validation/connected-next.md).

Integrated checkpoint `03cbdfc` delivers #60 (caller-aware recovery under #48), #61 (truthful terminal Results under #50), and #63 (optional folder-access education under #46). Manual recovery returns to its real caller; startup recovery returns Overview. Current observed caller viewport and live session context remain process-owned, separate from durable facts. Terminal presentation distinguishes applied, partial, no-op and unresolved outcomes without claiming released space. Unknown outcomes require recovery review instead of ordinary retry. Existing exact unfinished-file recheck/new-approval and explicit new-plan boundaries remain. #63 adds optional folder-access education in Locations, using a restrained disclosure with no inferred Full Disk Access status, OS prompt, discovery scan or cleanup-policy expansion. #62 is integrated at `03779f5`, sharing existing Local records management from History and Locations; it retains current maintenance safeguards and future diagnostics/exclusion gates. Local records has one Back to its History/Locations caller; recovery entered there returns to that page, while gated diagnostics returns directly to the root caller as locked in Q17. [Local records qualification](validation/local-records.md) tracks this slice. [Recovery/results qualification](validation/recovery-results.md) records implementation and native evidence separately from requirements; full parent acceptance, unresolved History/appearance decisions and future milestones remain preserved.

Every implementation slice must name parity and FL IDs, synchronize **SPEC and DESIGN-HANDOFF**, cover the complete user journey and its exceptional states, and retain explicit proof limits. Design annotations precede implementation; original native Light/Dark initial/minimum capture and public-flow verification precede UI merge. A helper, probe, inaccessible development route or successful build alone is not feature completion.

## Design intent

A quiet native Mac utility: light and dark appearance, white/near-black content surfaces, subtle material in native window chrome and dark sidebar, restrained category colour. The light sidebar is explicitly white, per the user’s October 22 clarification; wallpaper/material bleed must not turn it beige. Prioritize readable consequences, predictable navigation and deliberate selection. Glass must not reduce text contrast. Avoid oversized dashboard cards, alarming storage scores, generic “Optimize” actions and promises of exact savings.

Use SwiftUI native controls, system typography and SF Symbols. The browser prototype illustrates visual hierarchy and interaction intent, not production CSS or native component metrics. Its custom symbols should be mapped to suitable SF Symbols during implementation.

## Window and layout

Initial target 1120 × 760 points; minimum target 900 × 640, pending native accessibility/localization validation. Persist user-resized bounds within the current display. At window attachment, fit initial/restored bounds to that display’s visible frame while preserving feasible minimum dimensions. Never resize/recenter on destination changes, selections, disclosures, errors or results. Use a persistent shell, stable toolbar/sidebar, and a shrinkable main content region.

Prototype references: 190 px sidebar, 63 px toolbar; translate to native metrics rather than copying CSS pixels. Keep one main vertical scroll region per destination. Preserve its offset on return; new destinations start at the top. Keep the primary plan action reachable in a stable bottom region. Long confirmation item lists scroll inside bounded sheets with visible action controls. No horizontal overflow for ordinary content. Use wrapping for consequences and accessible truncation for long paths.

Proposed native spacing tokens: 4/8/12/16/24/32 pt; 24–32 pt content insets; 8–12 pt related-control gaps. Treat these as starting design-system values to validate in the native shell, not previously measured production requirements.

## Semantic tokens

| Token family | Intent |
|---|---|
| Surface/window | Native window background |
| Surface/content | Stable opaque reading surface |
| Surface/chrome | Native material for window chrome/sheets and dark sidebar, with opaque reduced-transparency fallback; light sidebar stays explicitly white |
| Surface/elevated | Native sheet/popover material with reliable contrast |
| Text/primary, secondary, disabled | System semantic label colours |
| Separator | Native subtle separator, no heavy card outlines |
| Accent/action | System accent for primary actions and links |
| Selection/focus | Native selected row, mixed checkbox and focus ring |
| Status/success, caution, failure | Semantic system colour plus icon/text |
| Category/cloud, developer, installers, browser | Restrained blue/purple/orange/teal accents; always accompanied by labels |

Use native title/headline/body/caption text styles and regular/medium emphasis. Keep numeric sizes tabular. No essential information relies on colour. Automatic follows system appearance; Light/Dark overrides are optional preferences. Both themes need contrast testing, increased contrast and reduced transparency/motion support.

## Navigation and screen contracts

Full-product navigation is retained below. M1 exposes Overview, Cleanup plan, History and Locations & access. What grew and Storage alerts arrive in M4/M5. Direct cloud/developer/browser action controls appear only when the corresponding adapter ships; inventory and management guidance may appear earlier. [Milestones](MILESTONES.md) is the scope authority.

Sidebar groups use the same row height, icon alignment and selected styling.

| Group | Destination | Primary task |
|---|---|---|
| Storage | Overview | Understand capacity, coverage and findings; start a manual scan |
| Storage | What grew | Compare compatible completed observations |
| Storage | Cleanup plan | Select categories, refine targets, review cleanup |
| Storage | History | Read results and prior activity |
| Settings | Locations & access | Manage scopes, permissions and local data |
| Settings | Storage alerts | Configure optional capacity notifications and login behavior |

Secondary destinations: item review, browser/profile review, app-managed storage, local data/exclusions and run results. Maintain a meaningful parent sidebar highlight and one labelled Back action. Do not create a primary sidebar item for browser cleanup. Reaching the same destination through two routes must not create a navigation loop.

### Overview

During a recheck, the fixed ActionStrip contains the unique Stop scan action; the scrolled header shows progress. The iCloud row displays Unknown whenever membership or cloud state is unknown, retaining identified subtotals and counts only in expanded evidence.

Show startup-volume capacity and observation time separately from inventory in scanned scopes. Show incomplete/denied coverage honestly. Recommendations have category, estimate and a short consequence. Trash-held bytes are separate from potentially released bytes. App-managed storage opens a read-only inventory/guidance page.

Use the approved reading order: Storage overview header / Scan again, subdued startup-volume capacity, compact Scanned locations / Explore storage, then one bordered four-row Recommended for review group (downloaded iCloud files, developer build files, Downloads to review, browser caches). Recommendation rows carry category badge, short plain-language consequence, trailing amount and its meaning, and an affordance only when actionable. The group uses the reading-plane fill; uninspected and unavailable states are explicit, never sample amounts. The direct Choose folder / Choose Downloads shortcuts and Downloads-only explanation remain near scanned coverage. Future tools expand in a secondary More tools group below findings.

Scanned coverage names the currently focused location and observation time, while retaining the number and partial-state evidence of known locations. Its amounts describe that location, not a sum of potentially overlapping roots. Downloads amounts represent eligible logical files across actual scanned Downloads locations; cloud allocation represents the focused location only. Empty eligible findings, missing coverage and unknown totals are distinct. Trash does not release space until emptied.

Recommendation activation opens relevant review without selecting targets. During a targeted retry, Overview describes the observed Downloads findings and offers an explicit Scan again to review all files action. This new manual scan ends retry filtering, rechecks the known locations, keeps unchanged chosen files and leaves newly discovered files unchecked; it does not approve any action. The ordinary Review files action remains inspection only. Downloads Review files opens the included observed Downloads category view across scanned locations even when focus is elsewhere; it never selects targets or redirects to Cleanup plan. Repeated observations of an exact directory entry merge, while distinct hardlink paths remain distinct targets. The cloud row expands existing read-only inventory inline; it adds no eviction action. Unavailable developer/browser rows have a reason and no dead chevron. “Scan again” sequentially rechecks all known explicitly chosen scopes directly, with Stop scan, while keeping the previous choices pending and review suspended until completion; it restores the focused scope afterward. Stop/restart cannot let an old generation overwrite the current operation. Only changing locations opens a chooser. “Review cleanup plan” opens the live category workspace; it never approves or executes.

### Item review and inspector

File names inspect; folder names enter their observed folder, with a separate folder-info action. Checkboxes select. Inspector shows location, size meaning, evidence, intended action/consequence and protected-item reasons. Quick Look and Reveal in Finder are explicit controls. No “Exclude from cleanup” button: it duplicates plan selection and introduces ambiguous persistence. Protected items stay visible with disabled selection and a reason.

Every checkbox immediately updates the same live plan. “View cleanup plan” navigates without applying or replacing a scoped draft. Back preserves selections. Item names inspect without selecting. Search never changes membership; show selected counts even when some selected items are hidden by the query. Selecting a file in one view updates every other representation of that resource/action.

### Cleanup plan

Keep one stable summary → category → fixed-review composition before and after scanning. With no Downloads coverage, show Not scanned, a disabled category checkbox and contextual Scan Downloads; do not replace the workspace with a global chooser/setup banner. With useful evidence and zero selections, keep the real category available and Choose items initially collapsed. Deeper Explore Downloads uses the same live selection and reuses an existing plan ancestor on return. M1 has Downloads; add the other categories as their milestones pass validation:

- iCloud downloads: remove local copies; originals remain online; internet needed to download again.
- Developer build data: permanently clear generated artifacts; rebuild cost; release archives remain.
- Downloads: eligible ordinary files, including installers and personal files; move to Trash; space stays occupied until emptied. Category Select all targets exact scanned files, never whole folders. Show eligible count/bytes and nested relative paths.
- Browser caches: permanently clear verified assets; preserve logins/site data/history; caches may refill.

Category checkbox selects exact eligible IDs at that moment. Mixed state indicates a subset. “Choose items” or “Choose browsers & profiles” expands inline refinement. Summary shows potentially released bytes, separate Trash-held bytes and selected category count. No “I need X GB” control. “Review cleanup” stays disabled with zero selections.

Keep complete-empty, not-scanned, partial and unavailable states within the stable category workspace. Known complete eligible subsets remain usable with explicit limited coverage; selected pending/unavailable targets block review until revalidated or deliberately deselected. Offer Deselect unavailable files without silently omitting choices. Results are a separate plan-owned destination with View history and Start a new plan. New plan or sidebar plan after completion is unselected and requires a fresh manual scan; completion never navigates automatically. Targeted retry clearly limits itself to rechecked unresolved items and offers an explicit Review all Downloads… scan boundary.

### Confirmation and results

“Review cleanup” opens a bounded sheet grouped by action, with exact targets, estimates and consequences. Include browser cache permanence alongside cloud/build/Trash semantics. Cancel returns to the unchanged plan and restores focus. Use a clear final execution label such as “Run cleanup”; do not ship “Simulate selected actions”. Do not execute on opening the sheet.

Results distinguish succeeded, failed, skipped, cancelled and unknown outcomes. Show observed capacity change separately from planned estimates and Trash-held bytes. Reveal in Trash is the ordinary-file recovery path. No universal Undo promise. Retry starts with revalidation, never direct repeat execution.

### Browser review

For the revised Chrome-only contract, selection/confirmation names the verified profile and downloaded-asset cache group, with observed estimate/time and a warning that eligible contents can change before execution. It does not promise a frozen file list. New profiles/groups stay unchecked; detected activity or conflicting scope changes stop unstarted work. All personal-file/Downloads exact-target controls above remain unchanged. #18 capability qualification is complete; #19 implements this composition with qualified native UI and visual evidence recorded in validation/chrome-cleanup.md. Browser probes alone do not qualify the Still screen.

Group by verified browser/profile or explicitly shared cache group. Show running, denied, unknown mapping, unsupported version and empty states. Close-browser guidance never force-quits the browser. Rescan refreshes eligibility; newly eligible groups stay unchecked. A selected group that becomes ineligible is removed with an explanation. Review and inline plan controls ultimately apply to the same committed targets.

### What grew and History

Growth compares compatible completed snapshots with interval, scope and completeness visible. First scan, cleared history and changed coverage are distinct states. Do not represent missing baselines as zero growth. History links to results and local-record management; returning from management restores History as parent.

### Settings and secondary management

Locations show explicit scopes and actual permission state. Denial offers limited operation and contextual recovery. Local history clearing/reset require consequence-specific confirmation. Clear only completed history; retain unresolved journals. Block Reset during execution or pending recovery and offer a recovery review route. Persistent scan exclusions are deferred to M6; do not show their controls in M1 or infer an exclusion from an unchecked item.

Storage alerts are off by default. Threshold, notification state, effective monitoring and separate Start at Login state are visible. Explain close-window versus Quit. Show stopped/blocked/unavailable states without alarming zero-space values. No permission requests during ordinary browsing. Opening a storage alert lands on Overview with a shared summary surface showing when that alert was checked (or an unavailable-time fallback), separate from the current capacity observation. Choose a folder to scan uses the existing explicit folder picker; cancelling leaves the context visible and starts nothing. Dismiss alert removes only this context. No alert action automatically scans or cleans.

Diagnostics shows redacted content before a native Save dialog. Cancellation/failure retains the reviewed payload and never uploads it. App-managed storage keeps unknown/not-inspected sizes distinct from measured zero and offers guidance only.

## Component inventory

Implement reusable native components for sidebar group/row/badge; page header; capacity meter; coverage summary; finding row; mixed category checkbox; item/profile row; inspector; selection summary; settings/status row; disclosure; scan progress; result row; confirmation sheet; and empty/blocked state.

Each interactive component needs default, hover where applicable, keyboard focus, selected/mixed, disabled and busy states. Errors should sit near the affected control or resource. Preserve row identity and focus during updates. Batch asynchronous changes; stale request results cannot overwrite newer scopes.

## Accessibility and keyboard

- Native tab order; visible focus; Space toggles focused checkbox; Return activates a focused button without bypassing confirmation.
- Filename inspection and selection have distinct accessible labels. Announce mixed selection and unavailable reasons.
- Sheet focus stays contained; Escape cancels before execution; restore focus to opener or meaningful surviving control.
- Announce significant scan/selection/result changes without announcing every discovered file.
- Offer text equivalents for capacity charts and category colours.
- Test VoiceOver, keyboard-only operation, increased contrast, reduced motion/transparency, long paths, localized text and larger text.
- Follow native app conventions for Settings and Quit. Do not invent destructive single-key shortcuts.

## Acceptance and lock boundary

At a fixed window size, outer bounds must remain stable within 1 pt rounding across all six destinations, all blocked/empty states, expanded disclosures, selection changes, light/dark appearance and sheets. Primary actions remain reachable. Check scroll and focus restoration separately from screenshots.

Run the journeys in [SPEC.md](SPEC.md) and all branches in the [state matrix](reference/macos-cleaner-ui-state-matrix.md). Test shared membership, category Select all, Back preserving choices, rescan suspension and explicit Quit clearing the unexecuted plan. Review-only persistence of appearance is not permission to persist a native cleanup plan.

The approved product direction is retained, but the October 23 parity checkpoint is not product-flow lock. The connected flow decisions are now confirmed in FLOW-LOCK; its annotated visual proposal b96bb97 is also user-approved for connected feature implementation. Native layout, accessibility, persistence and adapter feasibility remain gates before release. The repository [visual reference](visual/README.md) includes the current preview and representative captures. The full-product preview preserves future feature designs and is explicitly labelled; its simulated OS behavior is not proof of platform support. Keep prototype-only scenario controls and synthetic data out of production.

## Refresh, launch and recovery behavior

Keep selected identities visible as pending during refresh; disable execution. A successful refresh validates survivors and explains changes, without selecting new discoveries. Cancel leaves “Refresh required”. Execution can skip changed targets but cannot substitute targets or change actions. Closing a window retains in-process choices; explicit Quit ends an unexecuted plan. Interrupted execution instead opens recovery review on launch and never resumes automatically.

Initial success means useful understanding, confident approval and observed capacity after real personal sessions. Evaluate recurrence in a later manual session; no background metric collection is implied.

For Downloads-only selection, the summary headline is **Selected for Trash**, with an explicit statement that space remains occupied until Finder empties Trash. When any Chrome cache group is selected, including Chrome-only selection, use **Selected for cleanup** and identify Downloads file and Chrome group counts separately. Explain permanent cache removal/regrowth alongside Trash-held space; no combined estimate promises released disk space. Source9ba40be implements the shared title distinction; final native presentation is qualified atceec55f as recorded in validation/chrome-cleanup.md.

## Implemented session lifecycle — #7

A live unexecuted selection belongs to the app process. Closing the workspace with a pending plan preserves both the inspection observations and selection in memory. With alerts off, the pending plan still keeps Still running. Dock reopening or **Window > Show Still** opens the workspace; Cleanup plan shows the same selected exact paths. Reopening a window does not approve or execute a plan. Explicit **Quit Still** ends the unexecuted selection, and the next launch requires a fresh user-requested scan. Item names continue to inspect independently of checkboxes; search and Back never apply or discard a separate draft.

## Implemented bulk review boundary — #8

Cleanup plan exposes the Downloads category as a native unchecked/mixed/checked checkbox with the current eligible file count and logical bytes. Mixed → Select all materializes exact current entries; later discoveries remain unchecked. Selected for Trash and its retained-space consequence precede review. The fixed confirmation sheet scrolls its expandable exact relative-path list while Cancel and final approval remain visible. Cancel restores the existing choices and focus to Review cleanup. Changes to selection or scan generation invalidate the old review. Final approval freezes a separate exact batch; it does not imply that a filesystem operation succeeded.

The native Downloads confirmation's final **Move to Trash** action now starts the approved exact batch. Results use shared presentation primitives, distinguish planned logical/Trash-held allocated estimates from independently observed capacity change, and offer Reveal in Trash only for known successes with actual returned locations. Starting consumes choices; another plan requires a fresh scan. Unknown outcomes never auto-repeat. #9 qualification is recorded in `validation/downloads-executor.md`. Completed history uses fresh-read maintenance (#13), with hosted native clear/reset and reviewed populated/blocked/confirmation evidence at 38a593e. Uncaptured and manual gates remain; startup recovery is described below.

### Implemented refresh states

Cleanup plan provides contextual **Scan Downloads again**; location-specific rechecks live in Locations & access. Refresh retains previous observed content explicitly marked refreshing, suspends selection and Review cleanup, and offers **Stop scan** in the shared toolbar status. Cancellation or incomplete scope coverage shows Refresh required. Successful recheck keeps unchanged selections, leaves discoveries unchecked and explains cleared changed/removed choices. Search and inspected context remain stable; no destination resize occurs. The [historical refresh evidence](validation/refresh.md) and [connected journey qualification](validation/connected-downloads.md) record their exact source boundaries.

## Native startup recovery (#12)

The following startup behavior retains an Overview return. Manual recovery from History returns to History under #60; manual Overview recovery returns Overview. The process-owned caller, observed viewport and expanded History evidence are separate from durable journal facts. Broader native qualification is tracked in [recovery/results validation](validation/recovery-results.md); the remaining #48 Local records and diagnostics routes stay separate.

Interrupted durable batches open a read-only secondary review on launch. Show unresolved outcomes separately from not-started targets and recorded terminal facts; a missing original never implies Trash success. Keep a fixed Return to Overview action and an Overview route back to unresolved evidence. A new manual scan/selection/approval is the only path to another cleanup. Current locations are unverified; only an explicitly persisted resulting location may be revealed on user action. See [validation and remaining gates](validation/startup-recovery.md).

The native active-operation footer keeps **Stop after current file** reachable. Partial results offer **Recheck unfinished files**, which performs read-only checks and forms a new restricted plan; it never executes. Completed successes and new discoveries are excluded, and changed/unavailable paths receive a new-scan recovery explanation. The same bounded confirmation requires a new final approval. Native disclosure controls inside its ScrollView retain a shared leading gutter so the arrow stays visible and clickable; label selection does not substitute for glyph activation. See `validation/cancel-retry.md`.

### M4 What grew native comparison states

Future-gated What grew preserves existing shortcuts and adds Command-6. The fixed action strip follows [WHAT-GREW](WHAT-GREW.md): establish a baseline, scan again, Stop during scanning, or explicitly reconnect missing authority. It uses the verified remembered location where available instead of always reopening a generic picker. A selected completed observation shows scope, completeness and both interval endpoints; compatible comparisons show folder/category logical deltas. First, cleared, expired/missing, changed-coverage and unknown observations have distinct explanations. Partial/cancelled/unmeasured observations never masquerade as completed growth. Completed-observation selection is secondary disclosure content; no writer attribution or cleanup selection is inferred. See [historical mechanism evidence](validation/growth-comparisons.md) and [current #52 qualification in progress](validation/what-grew.md).

### Directory instability during scanning

Existing scan progress names the single bounded recheck when directory evidence changes. Its subtotal may restart because inconsistent attempts are not combined; cumulative inspected-work count and elapsed time remain meaningful. Stop stays in the shared fixed action strip. Repeated instability or budget exhaustion shows partial/unknown coverage with the existing explicit Recheck folder route. Pending plan choices remain Refresh required until a complete compatible recheck. See [validation](validation/directory-stability.md).

### Completed-history implementation (#13)

Under the locked #51 [History activity contract](HISTORY-ACTIVITY.md), History presents terminal scan activity and completed cleanup runs with All activity/Scans/Cleanups filters. Shared scan summaries expand recorded root/coverage/outcome/aggregate details without scanned child-file catalogues. Cleanup summaries retain expandable per-file results. The combined feed is implemented at `f062ca6`; [qualification](validation/history-activity.md) records exact native/source limits. Planned logical/Trash-held allocation estimates and independently saved capacity change stay distinct; legacy missing measurements remain Unknown. Local-data controls use native consequence-specific confirmations. Unfinished runs remain outside completed history, survive Clear/retention, block Reset and link to fresh read-only recovery. Reset does not restore or retry a plan. See [history/reset evidence and remaining native gates](validation/history-reset.md).

### M6 diagnostics review and local Save

The earlier Overview-only route remains a supported entry. Qualified #62 adds diagnostics from the shared Local records page in History and Locations, returning directly to the actual root caller with one Back. The frozen diagnostics model and observed viewport remain process-owned through window closure; a new explicit review creates a fresh snapshot at the top. The route remains M6-gated. [Local records qualification](validation/local-records.md) records the source and native boundaries; this accepts the bounded #62 caller journey, with broader platform/future limits retained.

A secondary future Overview action, or the candidate gated Local records entry, opens Review diagnostics, listing Included and Excluded fields before a selectable exact JSON preview. The preview is a frozen snapshot, not a live log. Reuse PageHeader, SettingsRow, SummarySurface and StatusRow; the reading region scrolls inside the fixed shell while the caller-labelled Back and Save diagnostics remain in ActionStrip. Native Save chooses a destination only after review. Cancel and write failure preserve the identical payload and offer another Save, with no fallback location or upload. Saving refuses the known local app-state subtree and its symlink aliases; if that protection root cannot be verified, Save fails without changing the preview or choosing a fallback. No diagnostics action clears history, resolves recovery or authorizes cleanup. A new explicit review creates a new snapshot; allowed Reset discards the old preview. [Hosted diagnostics evidence](validation/redacted-diagnostics.md) qualifies the review/header and scrolled-payload layouts at 0e8a143 in both themes and sizes. Native Cancel is behaviorally asserted; uncaptured Save-panel/saved/failure visual states and manual OS/accessibility gates remain.

### Custom exclusions (M6)

A future-gated secondary **Custom exclusions** route under Locations & access uses shared settings/status surfaces. Choose a file or folder, review the resolved path, volume-bound matching and file/subtree boundary, then Save exclusion explicitly. Existing rules have explicit Remove controls; cancellation and ordinary plan deselection never save rules. A persistent status explains that changed rules require a manual recheck and excluded bytes are unknown. Fixed safety protections remain read-only. [Rule, rename/replacement and coverage semantics](EXCLUSIONS.md) are authoritative.

## Current-build cleanup scope guidance

> Historical implementation record at f9e854f. The approved [flow lock](FLOW-LOCK.md) supersedes the global plan banner/chooser and detour below: use contextual category prerequisites and stay on the initiating screen. Preserve Downloads-only safety while implementing the approved replacement; do not copy this old composition into new screens.

Overview before scanning, folder inspection and Cleanup plan display: “Cleanup currently supports files in Downloads only. Other folders are inspection only.” A shared “Choose Downloads…” button opens the native folder chooser at the user's Downloads directory. Scanning begins only after the user confirms a folder; Cancel preserves the current view, observations and choices. The chooser permits another location for inspection and repeats the restriction. The shortcut does not grant eligibility, select files or approve cleanup. It is disabled during scanning/selection preparation where applicable; execution retains its dedicated progress flow. Files inside Downloads remain subject to all existing completeness, identity and protection checks. Broader ordinary-file cleanup and whole-folder cleanup require separate product/safety design; this guidance does not expand M1 mutation scope.

### Explicit pip cache inspection (#24)

Keep pip as a secondary future-milestone Overview destination. Reuse PageHeader, SettingsRow, StatusRow and SummarySurface. Choose Python interpreter and cache independently, then Inspect explicitly; chooser cancellation preserves choices. Explain the supported Apple developer tools Python 3.9 / bundled pip 21.2.4 boundary before selection and in the native picker. Show selected paths, verification/progress or useful unsupported/access/timeout guidance, followed by current inventory evidence only after successful inspection. Changing either choice discards the previous evidence.

A live report identifies the exact tool, resolved explicit cache root and observation time, lists wheel count and checked logical/allocated subtotals, and separates vendor summary text from actual allocation evidence. Unknown measurements remain Unknown; legacy HTTP coverage and unmeasured HTTP-v2/other contents are explicit. Limit visible wheel paths to the first 20 while totals cover every returned wheel. The recorded disposable reference remains labelled and clears live choices/evidence; it never impersonates the user's cache. There is no select, Add to cleanup plan, install or clean action on this surface. Preserve outer bounds while content scrolls in both themes and at minimum size.

### Docker explicit local inspection (#33)

Use shared page/settings/status/summary components on the future Docker route. Present the supported exact CLI/Engine version and the pending genuine-runtime qualification before input. CLI selection and an initially empty **Local Unix socket path** field are separate explicit choices. **Inspect selected Docker** stays disabled until both inputs exist and during inspection; no selection initiates a process. Changing the CLI clears the previous report. Each explicit inspection clears stale daemon evidence before reporting its result. Explain unsupported release, denied/unavailable endpoint and timeout without install/start/elevate actions. The user may separately choose disk-image metadata; never imply it belongs to the daemon. Persistent-volume labels and unknown host/VM values remain visible in the report. No selection, Cleanup plan or mutation control is added. The window and shared scrolling contract stay unchanged.

Editing the Docker socket path invalidates prior daemon evidence and status immediately; another explicit Inspect is required. Independently selected image-file metadata remains visible with its separate unverified ownership label. Re-entering the identical socket path does not discard an observation.

### Homebrew cache inventory — #22

Keep this secondary page behind the existing future-milestones gate and shared native components. “Choose Homebrew executable…” and “Choose cache folder…” are separate explicit choices; “Inspect selected Homebrew” enables only with both. Explain pinned Homebrew 4.6.17 shell-source support, explicit cache override and that installed code/configuration is not executed. Choice replacement invalidates evidence; native picker Cancel preserves current choices/report. Disable choices and reference actions during inspection.

Show complete/partial/unsupported/unavailable/timed-out status without navigation or window changes. Only supported inventory displays observed count, logical bytes, allocated bytes, downloads/incomplete counts and observation time; partial totals read “Unknown”. Unsupported source must not show a fabricated zero inventory. Always distinguish pinned shell provenance, resolved installation prefix and queried cache override from discovered settings. The Homebrew-specific incomplete-name list is capped at 20 visible names and warns that downloads may still be active. “Reclaimable space: Unknown” is explicit; no cleanup, selection checkbox or plan action exists. Keep the older synthetic preview separately labelled as an example, never as real vendor qualification. Capture selected/inventory states in Light/Dark at initial/minimum bounds using the real staged-shell and owned-cache pipeline; no personal installation is needed.

## Commercialization boundary — M8

Distribution signing, secure timestamps, notarization, release-preflight corrections and commercial packaging belong to M8/#40. They add no onboarding, sidebar or cleanup-flow steps, and do not gate feature implementation or local builds. Keep native ad-hoc test signing and each feature’s actual permission, identity and safety checks. Functional/accessibility acceptance remains M7; see [milestones](MILESTONES.md) and [commercialization](COMMERCIALIZATION.md).

### Storage alerts lifecycle evidence

The existing settings/status composition is unchanged. Re-enabling after a delayed check must resume monitoring; obsolete work must not overwrite the current status or cancel a newer episode’s request. An observed threshold invalidation stops polling and keeps the existing actionable status. Quit cannot restart checks through wake/activation while awaiting a safe cleanup boundary; saved intent survives for a new launch. Disable/reset remain resumable and remove known pending request identities across restart, without claiming recall of delivered banners. Editing the threshold does not change monitoring until Apply; invalid or unapplied text leaves the last applied threshold active. See [monitoring implementation and controlled evidence](validation/alert-monitoring-orchestration.md). No new permission, toggle, navigation or visual state is introduced by these corrections.

#62 shared presentation source `dadc0c1` extracts inert Gallery-compatible maintenance and diagnostics controls without changing model authority. Earlier native diagnostics route run `40067584469` and existing Overview diagnostics regression run `40067584423` pass at `ff51967`; final native context/diagnostics/History/affected regressions pass at `f8a0c86`, with shared Gallery2/2 at test-only `f754b83` and67 individually reviewed originals. Save-panel/saved/write-failure visual and manual OS/accessibility limits remain as recorded in the owning validation reports.


## Locked capacity-card behavior — #49

Overview retains capacity → coverage → findings. The implemented shared card provides a quiet native Refresh capacity/Try again action, separate from Scan again. Checking, retained-value refreshing, observed important/fallback, valid available/unknown total, stale failure and first-use unavailable states reserve their header, meter and status/action space. Only refresh/retry is disabled during its request. Missing totals never hide a valid available amount or draw a filled meter; failed reads never silently update observation time.

The sidebar shares the same amount/status, with compact Observed/Last observed time and no duplicate action. Full observation time and metric remain in the card and sidebar help/accessibility label. This compact footer preserves the minimum window budget with future navigation visible. The native action keeps its intrinsic label and padding within a stable minimum-width slot. Exact window and the unchanged Scanned locations heading below the card anchor native geometry checks; varying text glyph widths are not layout movement.

Closing/reopening a retained process preserves current evidence and live choices. A current refresh cannot rewrite Results/History measurements; after leaving Results, the approved History route inspects that recorded operation, while selecting Cleanup plan starts a new plan. [Canonical contract](CAPACITY-REFRESH.md) and [qualification](validation/capacity-refresh.md) record combined focused native passes at final presentation source `8869b38`; all 71 final original captures have been individually reviewed and accepted.


## Shell and appearance lock — October 24

#53 is locked in [SHELL-APPEARANCE](SHELL-APPEARANCE.md). Use reserved compact sidebar badge/footer and appearance feedback space, actual-page context, native full-label actions and immediate shared appearance updates without navigation/focus/selection/scroll/window movement. All exceptional preference/monitoring states require shared Gallery and original native theme/size review; [Bounded implementation qualification](validation/shell-appearance.md) passes at final app source `c5886e8`.

#53 implementation composition: reserve a24pt preference-feedback row at the top of the right content pane, near the toolbar appearance picker, in every state. Share it with Gallery. Keep messages and full native Retry saving action within that row; do not add a tall sidebar/toolbar stack, obscure content with an overlay, steal focus, or resize the window when feedback changes. Corrected shared Gallery and staged-Reset originals have passed their bounded visual review. Live appearance is process-owned through one native owner so content and auxiliary panels remain consistent, including return to Automatic. Gallery retains its independent preview. Normal-click Retry at both sizes and all16 affected journeys now pass in the source-bound [shell evidence](validation/shell-appearance.md).


## History activity lock — October 24

#51 Q1–Q15 and the consolidated contract are user-confirmed in [HISTORY-ACTIVITY](HISTORY-ACTIVITY.md). M1 History gains minimal terminal scan activity alongside completed cleanup runs, with All/Scans/Cleanups filters and honest scope/outcome/retention/availability. Detailed growth collection/comparisons stay M4-gated; historical routes never restore live findings or approval. Scan activity and enabled aggregates share the existing250 MB archive budget; cleanup retains its separate250 MB completed-payload budget, with protected recovery exemptions. Implemented at app source `f062ca6` with [bounded source/native qualification](validation/history-activity.md), including96 individually accepted final originals. The full future roadmap and deferred M8 remain unchanged.


## What grew flow and navigation lock — #52

Q1–Q17 and the consolidated [WHAT-GREW](WHAT-GREW.md) contract are implemented at application source `fb20196`, with [bounded qualification](validation/what-grew.md): Core158 Swift Testing +5 XCTest, six business journeys at two sizes (12 methods), two Gallery checks and six affected existing checks across source-bound runs. All50 final changed-presentation originals are individually accepted. G01–G04 are Covered for this future-gated manual workflow. M4 gating, #51 archive/recovery authority, platform limits and all future milestones/M8 deferral remain unchanged.


### What grew route details — #52 implementation

Current selection and exact History requests are separate. An exact historical page retains Back to History, and “Scan this location now” changes to current mode only after verified authority and an accepted actual scan. Cancelling reconnect preserves the exact historical observation. A new History row must not displace the original link on Back: restore its position, filter and disclosure after the updated feed loads.

Review uses verified current findings: Review Downloads enters the existing plan with Back to What grew; Explore folder enters the observed-only Explorer with that same caller. Missing current findings require explicit Scan to review. Pending access verification is disabled/checking, never a transient false Locate prompt. Reconnect rejects same-named/replaced roots; stale async results cannot navigate or start a scan after the caller changes.

Archive unavailability hides numeric comparisons and offers explicit Retry. The retained identity may still resolve current authorized findings; this does not make cached historical numbers valid. Save warnings keep current review usable without replaying the failed observation. Stop/partial/failed attempts explain their outcome separately from the last valid retained comparison. M4 gating and all cleanup/recovery authority stay unchanged.


## Release archives guidance flow — #54

Q1–Q7 in [RELEASE-ARCHIVES](RELEASE-ARCHIVES.md) are implemented at application source `62bcf8a`, with [bounded Core/native/visual evidence](validation/release-archives.md). Guidance-only Release archives is first in the existing M6-gated list; Device backups remains default. It is always Not inspected and Protected from Still cleanup, with retention guidance, explicit Open Xcode/Apple guide and truthful unavailable fallback. The shared inert `ReleaseArchiveGuidance` is reused live and in the collapsed Gallery. No picker, metadata read, traversal, deletion, new permissions or navigation framework was added. M01–M02 are Covered for this guidance slice; broader #31 native owner-app/platform qualification, other categories, future milestones and M8 deferral remain unchanged.

## Storage alerts settings lock — #27

Q1–Q7 in [STORAGE-ALERTS](STORAGE-ALERTS.md) have bounded settings implementation at live/controller source `336fcb9`, final Gallery `5049ce4`, with [source-bound evidence](validation/storage-alerts-settings.md). Shared current capacity/Refresh is separate from monitoring samples; permission recovery is contextual; only explicit valid Apply changes a pending threshold. Unknown display total preserves the saved threshold. Shared pure settings/Gallery and the collapsed quiet explanation omit the prototype test-notification control. #27 remains open for genuine macOS authorization/delivery; M5 stays gated, #28/#29 stay separate, and all future milestones/M8 deferral remain.

#27 composition: shared `VolumeSummary` reuses current capacity/time/failure/Refresh; `AlertPermissionDetails` separates permission/recovery; `AlertThresholdEditor` keeps the applied value visible during pending/invalid edits; `MonitoringDetails` and Last monitoring check describe the independent monitoring session; `QuietAlertExplanation` starts collapsed. Current display Refresh does not call the alert controller. Exact qualification remains in validation/storage-alerts-settings.md; native OS delivery is not inferred from this composition.

## Chrome cleanup contract — #18/#19

Q1–Q6 in [CHROME-CLEANUP](CHROME-CLEANUP.md) are user-confirmed. #18 qualification is complete for its explicitly recorded Stable release/layouts; CfT evidence alone never grants installed-Stable support. #19 delivery and its bounded qualification are recorded below. #19 retains the approved browser/profile → shared plan → permanent confirmation/results journey, explicit authorized inspection, reviewed profile/cache groups under revised rules5–7 and explicit recheck on reopen/uncertainty/change. Preserve protected browsing data; GPU/code caches and broader compatibility remain future scope. Disposable synthetic environments only. No new guidance-only screen or production capability is implied: if ownership/concurrent-write protections cannot be established, record the specific blocker and leave cleanup disabled. #19 is implemented and qualified within its recorded Chrome boundary; broader M3/M8 and other milestone gates remain.

Historical qualification checkpoint: [source-bound lease investigation](validation/chrome-stable-qualification.md) did not establish the former exclusive-lease guarantee. Its stop rule is superseded by the user-approved native close-and-clean contract below; it is not a current lease prerequisite.

## Chrome native close-and-clean revision — October25

The user approved revised [CHROME-CLEANUP](CHROME-CLEANUP.md) rules5–7. Chrome-only approval is a verified profile/asset-cache group with refreshed estimates, not a frozen inode manifest. Require browser/helpers closed, revalidate verified scope/ownership/layout with no-follow access, reject replaced directories/unknown evidence, stop unstarted work on detected activity/conflicts and report partial outcomes. Ordinary-use residual races are explicit; an exclusive external lease is no longer prerequisite. Newly generated eligible entries inside the same approved cache group may be included; new profiles/groups stay unchecked. Downloads and all personal files retain exact-target protections. Earlier exclusive-lease stop-rule text is historical and superseded only for this Chrome model. This is the approved qualification contract; the bounded production adapter is implemented and qualified; broader compatibility remains future scope. Extension-based cleanup remains a possible later alternative, not this slice.



## Chrome #18 final capability checkpoint

Remaining #18 qualification is complete within the [recorded compatibility boundary](validation/chrome-close-clean.md#final-saved-record-evidence-and-18-capability-decision): actual Stable156.0.8078.48/macOS26.6.2 arm64; standard split-root removal/regrowth and native conflict/access checks at8f610f7; genuine headed password fill, saved-address record retention and download history atfa8192d; earlier27c1db6 preserves two-profile site/session/history/offline semantics. That capability decision enabled the subsequent #19 browser/profile → shared plan → permanent confirmation/results implementation. The bounded #19 adapter is implemented and qualified as recorded below. Unknown/shared/managed/redirected layouts remain unavailable; additional compatibility remains future scope. Address form-suggestion acceptance is unqualified; actual saved-record preservation is independently proven. Personal-file/Downloads exact-target protections are unchanged.


## Chrome #19 qualified delivery

The approved browser journey is implemented with separate typed cache-group approval and unchanged exact-file Downloads authority. [Source-bound qualification](validation/chrome-cleanup.md) records genuine Chrome cleanup through the production Swift adapter at23e2219: workflow40264317079 succeeds on verified Stable156.0.8078.48/macOS26.6.2 arm64. Saved passwords, saved-address records, protected site/session/history/offline state and downloads pass their stated checks. Address website form-fill commitment is not qualified. Still UI/visual/regression acceptance is complete for this bounded delivery through [PR72](https://github.com/Patrick-M-Bourget/mac-cleaner/pull/72). Final app presentation is `ceec55f`: 11 distinct public UI methods pass across the recorded scoped runs, and 47 selected original captures were individually reviewed. The production adapter is byte-for-byte unchanged from the full successful `23e2219` qualification. Later repeat refusals preserve uncertain work; they are not relabelled green. See the qualification report for exact sources, viewport limits and unsupported cases.

One latched cancellation request covers both action categories (c91b78b): Stop preserves unstarted work even when requested during Downloads or initial capacity sampling; completed Trash moves/cache removals remain completed. Completed Chrome history expires after90days with a20MB component ceiling inside the existing combined250MB completed-cleanup payload budget (fa60edb/2228508). Unresolved facts are exempt from completed-history eviction, retained by Clear and block Reset/replay; unsafe/unreadable journals refuse further work. Clear/Reset reports committed Chrome effects and the actual failed preference stage separately (e8e94ab). Unknown capacity/size remains unknown, and removed bytes never promise disk-space gain.


### Chrome #19 current interaction handoff

Overview’s **Review browser caches** opens a caller-preserving Browser caches review. **Enable Chrome inspection** performs the first explicit check; later **Recheck Chrome** refreshes estimates/status without selecting discoveries. Recognized profile rows expose independent checkbox selection, observed time and size or an explicit running/access/unsupported/unknown/empty state. **Back** returns to the actual caller; **View cleanup plan** uses the same session membership. The shared browser category supports macro selection and collapsed **Choose browsers & profiles** refinement.

The plan summary uses **Selected for cleanup** whenever Chrome groups are selected; **Selected for Trash** remains the Downloads-only default. Mixed confirmation groups exact Downloads paths under Move to Trash and verified Chrome groups under permanent asset-cache removal. Cancel preserves choices and returns keyboard focus to Review cleanup. Mutating either category invalidates the review. **Run cleanup** starts only these distinct approvals; Stop stays reachable across both phases. When Chrome is included, the results workspace uses one **Running cleanup** / **Cleanup results** page header and states the separate permanent-cache and Downloads-to-Trash consequences. Chrome-only results show no Downloads success outcome; mixed results retain both action-specific sections. The lower **Chrome cache results** section must remain reachable through the shared scroll region and appear in its own reviewed capture, rather than relying on a top-viewport Downloads capture. Downloads-only presentation retains its existing header. Results and History show per-group completed/failed/skipped/cancelled/unknown facts, actual removed entries/bytes and separate capacity evidence. Chrome results never offer Undo or Reveal in Trash. A new attempt requires explicit recheck/selection/approval. Local-data Clear/Reset preserves unresolved Chrome facts and reports partial maintenance effects accurately.


Source345d723 adds the shared results hierarchy and Chrome-only initial/minimum public journey/captures; native presentation and original-image acceptance remain pending. It changes presentation and coverage, not approval, mutation or compatibility scope.


## Xcode flow lock — grilling #16/#17

The user confirmed Q1–Q7 in [XCODE-CLEANUP](XCODE-CLEANUP.md): remaining qualification must lead to the complete developer cleanup journey; initial targets are verified project-specific generated intermediates; inspection may run while Xcode is open, but cleanup requires closed owners. Project-grouped review uses exact-file refinement; explicitly enabled standard-root inspection remains manual. Qualified Xcode cleanup uses practical close-and-clean safeguards with documented residual races, not a universal exclusive lease; new files never join its frozen manifest. Other generated categories and custom roots remain future scope. Xcode/build activity or uncertain Xcode scope stops the entire remaining approved run, with truthful Not started outcomes; a changed/missing individual file is skipped while other verified targets may continue. The consolidated contract is user-confirmed. Bounded Core qualification #16 passes at `f937636` with [source-bound evidence](validation/xcode-intermediates.md); #17 is now unblocked for the complete app journey. The app feature remains undelivered until that integration passes; design approval alone never enables an adapter. Preserve the approved shared plan/confirmation/results design and exact personal-file protections.

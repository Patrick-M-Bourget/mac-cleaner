# Still — design and interaction handoff

Native UI implementation follows the mandatory [design system](DESIGN-SYSTEM.md).

Revision 0.9 · October 22, 2026 · Companion to [SPEC.md](SPEC.md).

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

Show startup-volume capacity and observation time separately from inventory in scanned scopes. Show incomplete/denied coverage honestly. Recommendations have category, estimate and a short consequence. Trash-held bytes are separate from potentially released bytes. App-managed storage opens a read-only inventory/guidance page.

Recommendation activation opens its relevant item/profile review without selecting targets. “Scan again” starts a scan of existing scopes directly, with Cancel; only scope changes require settings. “Review cleanup plan” opens the category workspace.

### Item review and inspector

Names inspect; checkboxes select. Inspector shows location, size meaning, evidence, intended action/consequence and protected-item reasons. Quick Look and Reveal in Finder are explicit controls. No “Exclude from cleanup” button: it duplicates plan selection and introduces ambiguous persistence. Protected items stay visible with disabled selection and a reason.

Every checkbox immediately updates the same live plan. “View cleanup plan” navigates without applying or replacing a scoped draft. Back preserves selections. Item names inspect without selecting. Search never changes membership; show selected counts even when some selected items are hidden by the query. Selecting a file in one view updates every other representation of that resource/action.

### Cleanup plan

Show available macro categories after a useful scan even with no selections. M1 has Downloads; add the other categories as their milestones pass validation:

- iCloud downloads: remove local copies; originals remain online; internet needed to download again.
- Developer build data: permanently clear generated artifacts; rebuild cost; release archives remain.
- Downloads: eligible ordinary files, including installers and personal files; move to Trash; space stays occupied until emptied. Category Select all targets exact scanned files, never whole folders. Show eligible count/bytes and nested relative paths.
- Browser caches: permanently clear verified assets; preserve logins/site data/history; caches may refill.

Category checkbox selects exact eligible IDs at that moment. Mixed state indicates a subset. “Choose items” or “Choose browsers & profiles” expands inline refinement. Summary shows potentially released bytes, separate Trash-held bytes and selected category count. No “I need X GB” control. “Review cleanup” stays disabled with zero selections.

Use full empty states only for no completed scan or no eligible findings. Unavailable categories explain their cause; unaffected categories remain usable. A completed run replaces executable reuse with a rescan requirement. Targeted retry clearly limits itself to rechecked unresolved items.

### Confirmation and results

“Review cleanup” opens a bounded sheet grouped by action, with exact targets, estimates and consequences. Include browser cache permanence alongside cloud/build/Trash semantics. Cancel returns to the unchanged plan and restores focus. Use a clear final execution label such as “Run cleanup”; do not ship “Simulate selected actions”. Do not execute on opening the sheet.

Results distinguish succeeded, failed, skipped, cancelled and unknown outcomes. Show observed capacity change separately from planned estimates and Trash-held bytes. Reveal in Trash is the ordinary-file recovery path. No universal Undo promise. Retry starts with revalidation, never direct repeat execution.

### Browser review

Group by verified browser/profile or explicitly shared cache group. Show running, denied, unknown mapping, unsupported version and empty states. Close-browser guidance never force-quits the browser. Rescan refreshes eligibility; newly eligible groups stay unchecked. A selected group that becomes ineligible is removed with an explanation. Review and inline plan controls ultimately apply to the same committed targets.

### What grew and History

Growth compares compatible completed snapshots with interval, scope and completeness visible. First scan, cleared history and changed coverage are distinct states. Do not represent missing baselines as zero growth. History links to results and local-record management; returning from management restores History as parent.

### Settings and secondary management

Locations show explicit scopes and actual permission state. Denial offers limited operation and contextual recovery. Local history clearing/reset require consequence-specific confirmation. Clear only completed history; retain unresolved journals. Block Reset during execution or pending recovery and offer a recovery review route. Persistent scan exclusions are deferred to M6; do not show their controls in M1 or infer an exclusion from an unchecked item.

Storage alerts are off by default. Threshold, notification state, effective monitoring and separate Start at Login state are visible. Explain close-window versus Quit. Show stopped/blocked/unavailable states without alarming zero-space values. No permission requests during ordinary browsing.

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

This handoff is ready for native-shell implementation. Native layout, accessibility, persistence and adapter feasibility remain gates before release. The repository [visual reference](visual/README.md) includes the current preview and representative captures. The full-product preview preserves future feature designs and is explicitly labelled; its simulated OS behavior is not proof of platform support. Keep prototype-only scenario controls and synthetic data out of production.

## Refresh, launch and recovery behavior

Keep selected identities visible as pending during refresh; disable execution. A successful refresh validates survivors and explains changes, without selecting new discoveries. Cancel leaves “Refresh required”. Execution can skip changed targets but cannot substitute targets or change actions. Closing a window retains in-process choices; explicit Quit ends an unexecuted plan. Interrupted execution instead opens recovery review on launch and never resumes automatically.

Initial success means useful understanding, confident approval and observed capacity after real personal sessions. Evaluate recurrence in a later manual session; no background metric collection is implied.

In M1, the summary headline is “Selected for Trash”, with an explicit statement that space remains occupied until Finder empties Trash. Later milestones separate potentially released bytes from Trash-held bytes.

## Implemented session lifecycle — #7

A live unexecuted selection belongs to the app process. Closing the workspace with a pending plan preserves both the inspection observations and selection in memory. With alerts off, the pending plan still keeps Still running. Dock reopening or **Window > Show Still** opens the workspace; Cleanup plan shows the same selected exact paths. Reopening a window does not approve or execute a plan. Explicit **Quit Still** ends the unexecuted selection, and the next launch requires a fresh user-requested scan. Item names continue to inspect independently of checkboxes; search and Back never apply or discard a separate draft.

## Implemented bulk review boundary — #8

Cleanup plan exposes the Downloads category as a native unchecked/mixed/checked checkbox with the current eligible file count and logical bytes. Mixed → Select all materializes exact current entries; later discoveries remain unchecked. Selected for Trash and its retained-space consequence precede review. The fixed confirmation sheet scrolls its expandable exact relative-path list while Cancel and final approval remain visible. Cancel restores the existing choices and focus to Review cleanup. Changes to selection or scan generation invalidate the old review. Final approval freezes a separate exact batch; it does not imply that a filesystem operation succeeded.

The native Downloads confirmation's final **Move to Trash** action now starts the approved exact batch. Results use shared presentation primitives, distinguish planned logical/Trash-held allocated estimates from independently observed capacity change, and offer Reveal in Trash only for known successes with actual returned locations. Starting consumes choices; another plan requires a fresh scan. Unknown outcomes never auto-repeat. #9 qualification is recorded in `validation/downloads-executor.md`. Completed history uses fresh-read maintenance (#13), with hosted native clear/reset and reviewed populated/blocked/confirmation evidence at 38a593e. Uncaptured and manual gates remain; startup recovery is described below.

### Implemented refresh states

Cleanup plan provides direct Recheck location actions. Refresh preserves selected rows and their last observations, suspends Review cleanup, and offers Stop refresh in the fixed action strip. Cancellation or incomplete scope coverage shows Refresh required. Successful recheck keeps unchanged selections, leaves discoveries unchecked and explains cleared changed/removed choices. Search and inspected context remain stable; no destination resize occurs. See [refresh evidence](validation/refresh.md).

## Native startup recovery (#12)

Interrupted durable batches open a read-only secondary review on launch. Show unresolved outcomes separately from not-started targets and recorded terminal facts; a missing original never implies Trash success. Keep a fixed Return to Overview action and an Overview route back to unresolved evidence. A new manual scan/selection/approval is the only path to another cleanup. Current locations are unverified; only an explicitly persisted resulting location may be revealed on user action. See [validation and remaining gates](validation/startup-recovery.md).

The native active-operation footer keeps **Stop after current file** reachable. Partial results offer **Recheck unfinished files**, which performs read-only checks and forms a new restricted plan; it never executes. Completed successes and new discoveries are excluded, and changed/unavailable paths receive a new-scan recovery explanation. The same bounded confirmation requires a new final approval. Native disclosure controls inside its ScrollView retain a shared leading gutter so the arrow stays visible and clickable; label selection does not substitute for glyph activation. See `validation/cancel-retry.md`.

### M4 What grew native comparison states

Future-gated What grew preserves existing shortcuts and adds Command-6. The fixed action strip opens an explicit folder picker. A selected completed observation shows scope, completeness and both interval endpoints; compatible comparisons show folder/category logical deltas. First, cleared, expired/missing, changed-coverage and unknown observations have distinct explanations. Partial/cancelled/unmeasured observations never masquerade as completed growth. Completed-observation selection is secondary disclosure content; no writer attribution or cleanup selection is inferred. See [implementation evidence](validation/growth-comparisons.md).

### Directory instability during scanning

Existing scan progress names the single bounded recheck when directory evidence changes. Its subtotal may restart because inconsistent attempts are not combined; cumulative inspected-work count and elapsed time remain meaningful. Stop stays in the shared fixed action strip. Repeated instability or budget exhaustion shows partial/unknown coverage with the existing explicit Recheck folder route. Pending plan choices remain Refresh required until a complete compatible recheck. See [validation](validation/directory-stability.md).

### Completed-history implementation (#13)

History presents completed runs using shared summaries with expandable per-file results. Planned logical/Trash-held allocation estimates and independently saved capacity change stay distinct; legacy missing measurements remain Unknown. Local-data controls use native consequence-specific confirmations. Unfinished runs remain outside completed history, survive Clear/retention, block Reset and link to fresh read-only recovery. Reset does not restore or retry a plan. See [history/reset evidence and remaining native gates](validation/history-reset.md).

### M6 diagnostics review and local Save

A secondary future Overview action opens Review diagnostics, listing Included and Excluded fields before a selectable exact JSON preview. The preview is a frozen snapshot, not a live log. Reuse PageHeader, SettingsRow, SummarySurface and StatusRow; the reading region scrolls inside the fixed shell while Back to Overview and Save diagnostics remain in ActionStrip. Native Save chooses a destination only after review. Cancel and write failure preserve the identical payload and offer another Save, with no fallback location or upload. Saving refuses the known local app-state subtree and its symlink aliases; if that protection root cannot be verified, Save fails without changing the preview or choosing a fallback. No diagnostics action clears history, resolves recovery or authorizes cleanup. A new explicit review creates a new snapshot; allowed Reset discards the old preview. [Hosted diagnostics evidence](validation/redacted-diagnostics.md) qualifies the review/header and scrolled-payload layouts at 0e8a143 in both themes and sizes. Native Cancel is behaviorally asserted; uncaptured Save-panel/saved/failure visual states and manual OS/accessibility gates remain.

### Custom exclusions (M6)

A future-gated secondary **Custom exclusions** route under Locations & access uses shared settings/status surfaces. Choose a file or folder, review the resolved path, volume-bound matching and file/subtree boundary, then Save exclusion explicitly. Existing rules have explicit Remove controls; cancellation and ordinary plan deselection never save rules. A persistent status explains that changed rules require a manual recheck and excluded bytes are unknown. Fixed safety protections remain read-only. [Rule, rename/replacement and coverage semantics](EXCLUSIONS.md) are authoritative.

## Current-build cleanup scope guidance

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

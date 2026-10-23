# Design/spec contract — revision 0.8

October 22, 2026. Authoritative requirements: [PRD](macos-cleaner-prd.md) and [technical specification](macos-cleaner-technical-spec.md), both revision 0.8. Canonical conversation preview: `storage-companion-direct.html`. Previous previews and research strategy suggestions are historical, not current requirements.

## Shared decisions

| Decision | UI contract | Implementation contract |
|---|---|---|
| Cleanup goal | No desired-space field or target disclosure in Cleanup Plan. | Plans contain exact actions, not a target-space mandate. |
| Storage alerts | Secondary settings destination; optional, initially off. | Included in v1; capacity-only polling, never folder scans or cleanup. |
| Threshold | Notify below 40 GB, editable. 40 GB is an example default, not a macOS requirement. | Decimal GB; >= 1 GB and below startup volume capacity. |
| Work cadence | “About every 15 minutes while awake.” | Best-effort timer plus coalesced activation/wake sample; no waking, exact delivery guarantee or catch-up bursts. |
| Access | Contextual notification opt-in. Full Disk Access not required for capacity checks. | Effective monitoring requires alert intent and notification authorization. Denial/revocation stops alert-only work. |
| Background presence | Menu-bar presence while alerts active; closing the window does not stop it. | Same user app process, no privileged daemon or FSEvents watcher for alerts. |
| Start at Login | Separate opt-in; surface approval/disabled status. | Register only on explicit action through SMAppService and reflect actual OS state. |
| Quit | Stops monitoring; saved login preference remains. | Safe operation boundary, no alert-only process left running. |
| Repeat suppression | One alert per low-space episode. | Persist suppression across restarts; recovery margin is threshold + 5 GB, capped at capacity. |
| Snooze | Remind me later means 24 hours. | At expiry recheck while running; one reminder only if still low. |
| Notification action | Open Overview and offer Scan again. | No automatic scan, cleanup or stale reclaimable-space claim. |
| Selection | Nothing preselected. Category checkbox selects eligible targets; inline item checkboxes refine them. Filename inspection remains distinct. | Materialize exact target IDs from the scan snapshot; show mixed category state and revalidate before execution. Never auto-add new eligible targets. |
| Confirmation | Group by Remove local downloads / Clear build data / Move to Trash. Show consequence and expandable files. | Separate action types and approval record; no generic permanent-delete fallback. |
| Accounting | Whole-disk capacity separate from scoped inventory; Trash-held bytes separate from available-space estimate. | Consistent available-capacity metric shared between Overview and monitoring; unknown readings never zero. |
| Results | Per-action outcomes, recovery and targeted rescan of skipped items. | Never blindly repeat completed actions; revalidate retry candidates. |

Sidebar structure: **Storage** contains Overview, What grew, Cleanup plan and History. **Settings** contains Locations & access and Storage alerts. Both groups use the same row spacing, icon alignment and selected-state styling; Locations & access opens the full Scan locations & access screen.

## Browser cache contract — revision 0.8

- Overview recommendation opens Browser caches; no additional primary sidebar item.
- Group by browser and validated profile/cache group. Chrome and Safari are initial candidates, not an unconditional compatibility promise.
- Nothing preselected. Running browsers show close-first guidance, disabled cache selection and explicit Rescan. The preview simulates closure; it does not close a real browser.
- Selected groups flow through Clear browser caches confirmation and per-action results.
- Permanently remove only validated asset caches. Preserve cookies, website/offline data, logins/passwords, history, autofill, sessions/tabs and downloads.
- Reopened/unsupported/inaccessible groups are skipped. Offer a fresh review, not automatic retry.
- Display regrowth/redownload consequences; no generic speed boost, exact savings or undo promise.
- Cache discovery belongs to manual scans, not Storage Alerts capacity polling.
- Canonical preview examples: Chrome Personal 1.6 GB, Chrome Work 0.5 GB, Safari Default storage 1.1 GB. These are synthetic values. Safari uses an explicit cache-group label rather than implying all versions support identical profile mapping.

## Preview versus native implementation

The preview simulates notification permission, Start at Login, Quit, notifications and cleanup. It does not install a background item, schedule real checks, request macOS permissions, open folders or change files. It exposes representative permission and lifecycle states; it is not a functional implementation of timer/suppression behavior.

Native lifecycle, notification delivery, timers, persistence and permission handling remain engineering requirements. No real automation or monitoring has been enabled on this Mac.

## Required acceptance checks

- Cleanup Plan has no goal control; Storage Alerts has the only space-threshold field.
- Alerts start off; on-demand inspection works with notifications denied and without Full Disk Access.
- Enabling alerts explains menu-bar behavior before notification authorization.
- Start at Login does not turn on automatically; disabled/approval-required registration is not shown as active.
- Closing the window, Quit, launch, wake, denial, revocation, snooze and threshold changes follow both specifications.
- A capacity check never calls the recursive scanner or ActionExecutor.
- Repeated low readings/restarts do not produce repeated alerts; genuine recovery rearms.
- Notification opens Overview and offers a scan; it never starts a cleanup.
- Existing file review, grouped confirmation, Trash accounting and recovery flows remain usable in both themes.

## Change discipline

When changing these behaviors, update the PRD, technical specification, canonical preview and this table in the same change. Keep future proposals distinct from v1 commitments. Refresh acceptance checks if a default, permission requirement or lifecycle rule changes.

## Refinement contract — revision 0.8

Overview displays potentially releasable estimates separately from items proposed for Trash, with eligibility qualifications. Manual scan scope includes recognized browser caches when accessible. App-managed storage guidance is separate from actionable cleanup findings. [UI handoff review](macos-cleaner-ui-handoff-review.md) records incomplete v1 states; preview coverage must not be mistaken for full specification coverage.

## Empty and blocked states — revision 0.8

The canonical preview now includes a review-only state picker outside the app window. [UI state contract](macos-cleaner-ui-state-matrix.md) maps every selectable branch to its requirement, permitted operations and recovery. Zero selections retain the category selection workspace; they do not produce a redirecting empty state. Unsupported/unknown/inaccessible browser groups have no executable action; unrelated validated groups remain usable. Permission recovery requires a new scan. The picker and simulation wording are not production components.

## Layout invariants — revision 0.8

The [window and interaction stability contract](macos-cleaner-layout-contract.md) is normative for window sizing, scrolling, modal bounds and regression acceptance. Content-driven window resizing is a defect. Prototype review tools are outside the app and must also reserve their own geometry.

## Direct planning and management — revision 0.8

The [flow audit](macos-cleaner-flow-audit.md) defines the primary category-to-confirmation journey, direct scan-again behavior, post-run invalidation, local records/exclusions and app-managed inventory. These replace the revision 0.5 empty-plan redirect. The four primary navigation destinations and two settings destinations are retained.

## Review routes and selection — revision 0.8

Overview recommendations open the relevant item review. The item inspector offers Quick Look and Reveal in Finder; it has no “Exclude from cleanup” action. Item checkboxes determine this plan’s membership. Protected/offline items retain their read-only reason. Persistent scope exclusions belong in settings, not in the inspector.

Item review loads a scoped draft from the current plan. “Add selected items to cleanup plan” applies the reviewed scope and opens Cleanup plan; “Update cleanup plan” permits clearing an existing scoped selection. Preserve other categories and deduplicate target IDs. Leaving via Back does not apply an unsubmitted draft. Reopening review loads the committed plan. Browser-profile review follows the same contract. Inline category refinement edits the plan directly. Only “Review cleanup” opens the final confirmation; no review entry executes cleanup.

Keep a single context-labelled Back action, stable window bounds and destination scroll restoration. Selecting or inspecting an item must never navigate. Initial startup must not populate hidden selections.

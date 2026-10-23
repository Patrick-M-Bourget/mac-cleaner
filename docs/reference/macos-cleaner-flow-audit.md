> Historical revision 0.8 reference. Preserve feature detail, but implementation scope and interaction rules are superseded by [SPEC](../SPEC.md), [design handoff](../DESIGN-HANDOFF.md), and [milestones](../MILESTONES.md), revision 0.9. In particular, staged item drafts, clearing selections on rescan, persistent plans and installer-only selection are obsolete.

# Flow audit and lock candidate — revision 0.8

Canonical preview: `storage-companion-direct.html`. Requirements: [PRD](macos-cleaner-prd.md), [technical specification](macos-cleaner-technical-spec.md), [state matrix](macos-cleaner-ui-state-matrix.md), [layout contract](macos-cleaner-layout-contract.md).

## Primary journey

**Cleanup plan → select categories → optionally adjust items inline → Review cleanup → confirm consequences → results.** A current usable scan is the prerequisite; visiting Overview or a file inspector is not a prerequisite for choosing a category. Nothing is preselected.

A category checkbox explicitly selects the exact eligible targets in that scan snapshot. The checkbox is mixed when only some eligible targets are selected. Opening a disclosure only inspects/refines selection. Newly eligible files or profiles after a refresh are never silently added to an existing selection. Execution still requires the separate confirmation and immediate target revalidation.

The right-hand size on each category is its eligible inventory; the top summary is the selected potential available-space estimate. Item counts distinguish those meanings. Trash bytes remain separate. No selected categories displays a quiet dash and disables Review cleanup while keeping all categories visible.

## Audited journeys

| Journey | Current contract and correction | Design status |
|---|---|---|
| First launch → scan | Choose scopes, discover metadata, then show findings. No fabricated prior baseline or mandatory permissions checklist. | Defined |
| Returning user → scan again | Scan the current locations directly in a progress sheet; settings are only for changing scope. Cancellation preserves prior completed observations. | Corrected |
| Cleanup plan with no selection | Four category rows stay available. Category checkboxes select eligible targets; inline item/profile lists provide refinement. | Corrected; previous empty redirect removed |
| Macro selection → item refinement | One selection set drives macro state, item checks, selected bytes and confirmation. Partial selection is visibly mixed. | Corrected |
| Browser selection | Plan supports eligible groups directly. Its inline profile list shows running/blocked groups and offers a status rescan. Detailed browser review remains available from Overview. | Corrected; no required menu detour |
| Browser closes after selection | Refresh eligibility; retain existing exact selection and leave newly eligible groups unselected. | Defined and checked |
| Files → plan | Inspection does not select; explicit checked items are added to the plan. Other category selections persist. | Defined |
| Confirmation → cancel | Return to the same selections and scroll position. No files change. | Defined |
| Execute → results → plan | Clear executed selections. Require fresh discovery before another general cleanup; do not leave the old plan executable. | Corrected |
| Partial outcome → retry | Recheck skipped items only; create a fresh review for the ready subset. Completed targets are not repeated. | Defined; native executor must enforce identities |
| Growth comparison | Compare matching completed coverage; first, cleared and mismatched baselines explain the next step. Review options leads directly to category planning. | Defined |
| History → local records | A secondary management screen provides retention information, custom exclusions, clear history and app reset with distinct confirmations. Back returns to the entry destination. | Added |
| Exclusion removal | Remove the preference, then rescan before offering it for cleanup. Protected system/library data remains protected independently. | Added |
| Clear history | Clear app records and comparison baselines, preserve original files and location choices. New activity appears without reviving cleared example records. | Added |
| Reset Still | Clear local preferences/records, selections and custom exclusions; remove scopes; stop alerts and disable login registration. Existing OS grants are managed separately in System Settings. | Added; simulated |
| App-managed storage | Read-only rows distinguish observed allocations from inaccessible/uninspected data. Management guidance never adds a deletion action to the plan. | Added |
| Diagnostics | Review included fields and redacted payload before choosing a local save location; cancel without exporting. | Added; save dialog simulated |
| Storage alerts | Optional off-by-default monitoring, separate login preference, contextual permissions, unknown-reading and stopped states. Notification opens Overview without scanning or cleaning. | Retained |
| Window and focus | Stable shell, internal scrolling, bounded confirmation, focus return and destination scroll restoration. State changes never resize the window. | Retained |

## Locked interaction principles

- Cleanup plan is a selection workspace, not merely a receipt for choices made elsewhere.
- Reserve full empty states for no scan/no eligible findings, not zero user selections.
- Category selection does not mean “anything this category may contain later.” Bind it to exact eligible targets at selection time.
- Scanning, selecting, confirming and executing are distinct actions. A scan-scope checkbox never means cleanup consent.
- Every block identifies its cause and offers the nearest useful recovery. Unaffected categories remain usable.
- Read-only inventory, cache purge, cloud eviction and Trash movement keep distinct consequences and recovery semantics.
- Macros and item lists are two views of one plan, not independently mutable copies.
- Preserve context on Back, Cancel and state refresh; do not force a return to Overview to complete a local task.

## Remaining gates before implementation lock

The core interaction model is now a lock candidate. Extract the design system from these components and specify keyboard shortcuts/VoiceOver labels in the native handoff. Validate the proposed initial/minimum window sizes and large-text/localized layouts in a native shell.

Keep the existing conditional adapter policy explicit: Xcode is represented; Homebrew/pip must pass feasibility and version fixtures before their own review details are committed for release. Browser versions, Safari cache mapping/access, iCloud eviction and allocated-byte accounting remain engineering feasibility gates. The prototype cannot certify those capabilities.

Diagnostics export now has an explicit review sheet with a redacted sample payload before the native Save dialog. Native save cancellation/failure must preserve the reviewed payload and never upload automatically. The preview simulates this handoff; no diagnostic file is actually written.

## Validation performed

Direct category selection, mixed item selection and exact confirmation totals were exercised. Browser revalidation kept a selected Safari group while leaving newly eligible Chrome groups unchecked. Quick-scan cancellation returned without opening settings. A completed cleanup invalidated the old executable plan. Local history clearing produced the correct empty record state. The fixed-window shell and existing safety/blocked branches are retained; native file operations and OS changes remain simulated.

## Review routes and selection — revision 0.8

Overview recommendations open the relevant item review. The item inspector offers Quick Look and Reveal in Finder; it has no “Exclude from cleanup” action. Item checkboxes determine this plan’s membership. Protected/offline items retain their read-only reason. Persistent scope exclusions belong in settings, not in the inspector.

Item review loads a scoped draft from the current plan. “Add selected items to cleanup plan” applies the reviewed scope and opens Cleanup plan; “Update cleanup plan” permits clearing an existing scoped selection. Preserve other categories and deduplicate target IDs. Leaving via Back does not apply an unsubmitted draft. Reopening review loads the committed plan. Browser-profile review follows the same contract. Inline category refinement edits the plan directly. Only “Review cleanup” opens the final confirmation; no review entry executes cleanup.

Keep a single context-labelled Back action, stable window bounds and destination scroll restoration. Selecting or inspecting an item must never navigate. Initial startup must not populate hidden selections.

Revision 0.8 verification: from an empty plan, opened iCloud item review with all eligible items unchecked, selected Reference documents only, and reached confirmation with exactly one item / 1.6 GB. Inspector exclusion control is absent. Prior broad layout sweep remains historical; native behavior still requires validation.

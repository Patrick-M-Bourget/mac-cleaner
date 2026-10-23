# UI handoff readiness — revision 0.8

Canonical preview: `storage-companion-direct.html`. The [flow audit](macos-cleaner-flow-audit.md) is the current interaction reference; older preview files are historical.

## Lock candidate

The core journey is **Cleanup plan → select categories → optionally refine items inline → review consequences → confirm → results**. Zero selections do not hide category choices. No completed scan and no eligible findings remain distinct genuine empty states.

| Area | Design coverage | Implementation gate |
|---|---|---|
| Overview and scope | Separate capacity, inventory, eligibility and Trash accounting | Accurate allocated-byte and capacity readings |
| Category and exact-item planning | Four macro categories, mixed selection, inline files/profiles, single target set | Snapshot identities, exclusion filtering and revalidation |
| Browser cleanup | Inline planning plus detailed review, running/unsupported/access states | Tested browser/version allowlists and helper detection |
| Cloud/build/Trash actions | Consequence-specific confirmation and recovery | Real API/tool behavior and race fixtures |
| Results and retries | Partial, cancelled and skipped outcomes; old-plan invalidation; fresh targeted retry | Exact per-target completion and retry accounting |
| Growth | First/mismatched/cleared baselines and completed-scope comparison | Baseline compatibility and persistence |
| Local data and exclusions | Empty/populated exclusions, removal, clear history, reset confirmations | Atomic persistence, stop monitoring and login unregister |
| App-managed storage | Observed versus unavailable inventory, management guidance, protected data | Native discovery with truthful coverage |
| Diagnostics | Redacted preview and explicit local-save handoff | Native Save dialog, cancellation/failure handling |
| Storage alerts | Opt-in, permissions, login, snooze, unknown reading and Quit | Native lifecycle/timer/suppression validation |
| Window stability | Bounded shell, scroll restoration, bounded sheet and fixed controls | Native sizing, accessibility, localization and display restoration |

## Design system extraction

Extract semantic light/dark tokens for content/chrome/elevated surfaces, separators, text, focus, selection and status. Use native typography, SF Symbols and materials in production. Glass belongs in chrome; reading/confirmation surfaces need stable contrast.

Components: sidebar group/row/count, page header, capacity meter, scope summary, finding row, macro category with mixed checkbox, inline item/profile list, inspector, selection summary, permission status, settings row, disclosure, progress/result row, confirmation sheet, empty/blocked state and local-data review.

Specify default, hover, focus, selected/mixed, disabled, loading and error states. Capture keyboard/VoiceOver behavior during the native handoff. Review-only scenario controls and simulation labels are excluded from the production component library.

## Remaining lock gates

- Verify the native shell at proposed initial/minimum sizes, larger text, translated strings and VoiceOver. Prototype geometry checks do not certify native behavior.
- Validate iCloud eviction, Safari/Chrome mappings and filesystem accounting before treating their implementation as supported. Preserve the existing conditional adapter policy: Xcode is represented; Homebrew/pip require their own validated rules and review details before release.
- Confirm implementation acceptance against the [state matrix](macos-cleaner-ui-state-matrix.md), [layout contract](macos-cleaner-layout-contract.md) and [flow audit](macos-cleaner-flow-audit.md). Native operations and persistence are simulated in the preview.

The previous management and inventory UI gaps are covered. This revision is suitable for design-system extraction and a native-shell implementation spike; release capability promises still depend on the feasibility gates above.

## Review routes and selection — revision 0.8

Overview recommendations open the relevant item review. The item inspector offers Quick Look and Reveal in Finder; it has no “Exclude from cleanup” action. Item checkboxes determine this plan’s membership. Protected/offline items retain their read-only reason. Persistent scope exclusions belong in settings, not in the inspector.

Item review loads a scoped draft from the current plan. “Add selected items to cleanup plan” applies the reviewed scope and opens Cleanup plan; “Update cleanup plan” permits clearing an existing scoped selection. Preserve other categories and deduplicate target IDs. Leaving via Back does not apply an unsubmitted draft. Reopening review loads the committed plan. Browser-profile review follows the same contract. Inline category refinement edits the plan directly. Only “Review cleanup” opens the final confirmation; no review entry executes cleanup.

Keep a single context-labelled Back action, stable window bounds and destination scroll restoration. Selecting or inspecting an item must never navigate. Initial startup must not populate hidden selections.

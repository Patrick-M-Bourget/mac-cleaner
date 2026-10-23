# Still — design and interaction handoff

Revision 0.8 · October 22, 2026 · Companion to [SPEC.md](SPEC.md).

## Design intent

A quiet native Mac utility: light and dark appearance, white/near-black content surfaces, subtle material in window chrome and sidebar, restrained category colour. Prioritize readable consequences, predictable navigation and deliberate selection. Glass must not reduce text contrast. Avoid oversized dashboard cards, alarming storage scores, generic “Optimize” actions and promises of exact savings.

Use SwiftUI native controls, system typography and SF Symbols. The browser prototype illustrates visual hierarchy and interaction intent, not production CSS or native component metrics. Its custom symbols should be mapped to suitable SF Symbols during implementation.

## Window and layout

Initial target 1120 × 760 points; minimum target 900 × 640, pending native accessibility/localization validation. Persist user-resized bounds within the current display. Never resize/recenter on destination changes, selections, disclosures, errors or results. Use a persistent shell, stable toolbar/sidebar, and a shrinkable main content region.

Prototype references: 190 px sidebar, 63 px toolbar; translate to native metrics rather than copying CSS pixels. Keep one main vertical scroll region per destination. Preserve its offset on return; new destinations start at the top. Keep the primary plan action reachable in a stable bottom region. Long confirmation item lists scroll inside bounded sheets with visible action controls. No horizontal overflow for ordinary content. Use wrapping for consequences and accessible truncation for long paths.

Proposed native spacing tokens: 4/8/12/16/24/32 pt; 24–32 pt content insets; 8–12 pt related-control gaps. Treat these as starting design-system values to validate in the native shell, not previously measured production requirements.

## Semantic tokens

| Token family | Intent |
|---|---|
| Surface/window | Native window background |
| Surface/content | Stable opaque reading surface |
| Surface/chrome | Native material, with opaque reduced-transparency fallback |
| Surface/elevated | Native sheet/popover material with reliable contrast |
| Text/primary, secondary, disabled | System semantic label colours |
| Separator | Native subtle separator, no heavy card outlines |
| Accent/action | System accent for primary actions and links |
| Selection/focus | Native selected row, mixed checkbox and focus ring |
| Status/success, caution, failure | Semantic system colour plus icon/text |
| Category/cloud, developer, installers, browser | Restrained blue/purple/orange/teal accents; always accompanied by labels |

Use native title/headline/body/caption text styles and regular/medium emphasis. Keep numeric sizes tabular. No essential information relies on colour. Automatic follows system appearance; Light/Dark overrides are optional preferences. Both themes need contrast testing, increased contrast and reduced transparency/motion support.

## Navigation and screen contracts

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

Load a scoped draft of committed plan membership when opening review. Present “Add selected items to cleanup plan” for a nonempty selection; “Update cleanup plan” when clearing an existing selection. Disable the CTA when no changeable targets or existing membership exist. Applying replaces only the reviewed scope and opens Cleanup plan. Back leaves the committed plan unchanged. A short hint should explain that selections apply when the CTA is used.

Keep selection independent of the inspector and search filtering. Changing a query must not silently deselect targets. The selection summary counts the reviewed scope, including selected items temporarily hidden by search. Switching reviewed scopes deliberately reloads the corresponding committed draft; do not silently carry a hidden cross-folder batch.

### Cleanup plan

Always show available macro categories after a useful scan, even with no selections:

- iCloud downloads: remove local copies; originals remain online; internet needed to download again.
- Developer build data: permanently clear generated artifacts; rebuild cost; release archives remain.
- Installers: move to Trash; recoverable in Finder; space stays occupied until emptied.
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

Locations show explicit scopes and actual permission state. Denial offers limited operation and contextual recovery. Local history clearing/reset require consequence-specific confirmation. Persistent scan exclusions are a settings-level policy; do not infer an exclusion from unchecking a cleanup item.

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

Run the journeys in [SPEC.md](SPEC.md) and all branches in the [state matrix](reference/macos-cleaner-ui-state-matrix.md). Add explicit regressions for initial hidden selections, scoped apply/removal, saved-state restoration ordering and Back abandoning drafts. The latest prototype restoration fix has not yet received a dedicated browser regression; do not claim complete verification.

This handoff is ready for native-shell implementation. Native layout, accessibility, persistence and adapter feasibility remain gates before release. The conversation prototype (`storage-companion-direct.html`) is the visual reference; historical previews are superseded. Keep prototype-only scenario controls and synthetic data out of production.

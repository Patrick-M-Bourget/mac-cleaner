# Still native design system

This is the mandatory presentation implementation contract for native UI. [DESIGN-HANDOFF.md](DESIGN-HANDOFF.md) owns interaction requirements; [SPEC.md](SPEC.md) owns product scope and safety. This document owns reuse, component roles and the UI change process. The approved [visual references](visual/README.md) establish hierarchy and tone, rather than pixel measurements for AppKit controls.

## Implementing or changing UI

1. Read the relevant screen/state requirements in the handoff and milestone scope. Locate the existing component in [DesignSystem.swift](../Still/App/DesignSystem.swift) and examples in [DesignGallery.swift](../Still/App/DesignGallery.swift).
2. Reuse the component and semantic tokens. When a required pattern is missing, add a shared component and a gallery example for its meaningful states before composing the screen. Keep domain decisions and filesystem work in their existing models/adapters.
3. Migrate every touched screen to the shared vocabulary. Checkpoint branches created before this system must migrate their UI when resumed, before integration. A local one-off style needs an explicit documented reason in review; recurring patterns belong in the shared component.
4. Review light and dark native captures against the approved references, at initial and minimum window sizes. Exercise changed states through public user journeys. Record captures, checks and remaining limits in validation evidence before merging UI changes.

Complete means every changed screen/state is accounted for, shared examples match the actual API, and the review records what was observed. A successful build or UI test alone does not establish visual fidelity. Changes to interaction or scope also update their authoritative handoff/spec, rather than introducing new behavior through styling.

## Tokens and surfaces

Use `StillDesign.Space` (`xs`, `sm`, `md`, `lg`, `xl`, `page`) for the 4/8/12/16/24/32-point rhythm; `Radius.row` and `.surface` for related rows and summary surfaces. Use `TypeStyle.page`, `.value` and `.section` for hierarchy, native body/callout/caption for supporting text, and monospaced digits for measured values. Read current values in source; avoid copying numeric definitions into screen files.

`StillDesign.reading` is the opaque white/near-black reading plane. `SummarySurface` creates the subdued elevated selection/summary region. `ChromeSurface(role: .sidebar)` is explicitly white in Light appearance, following the user’s October 22 clarification. It preserves native material in Dark appearance. `ChromeSurface()` supplies material for other chrome; both roles use an opaque system-background fallback where applicable for Reduce Transparency. A light sidebar always stays white, including fallback mode. Native semantic foreground and separator colors carry ordinary text and boundaries. A glass effect must leave reading content legible.

`StorageCategory` supplies a local badge accent and SF Symbol: cloud blue, developer purple, Downloads orange, browser teal, managed indigo. These identify categories; they do not indicate risk, selection or eligibility. `StatusRole` supplies neutral/success/caution/failure icon treatment with an explicit text explanation. Never make meaning depend on color alone.

## Component API and composition

The app target owns these internal SwiftUI components; they are presentation primitives, not a separate public package. Source is authoritative for signatures and defaults.

| Component | Role |
|---|---|
| `PageHeader` | Quiet page title and optional single explanatory subtitle |
| `SummarySurface`, `SelectionSummary` | Subdued grouped evidence and selected-for-Trash value/detail |
| `FindingRow`, `CategoryBadge` | Category hierarchy, consequence and explicit accessory action |
| `InspectableItemRow` | Separate selection control from filename inspection; size aligned at trailing edge |
| `MacroCategoryCheckbox` | Native AppKit unchecked/mixed/checked category selection |
| `ScanProgressSummary` | Bounded preliminary metadata evidence, unknown remaining coverage; no cleanup controls |
| `StatusRow`, `EmptyState` | Honest status, blocked/error explanation, or no findings yet |
| `SettingsRow` | Setting title, explanation and native controls |
| `StillSidebarRow`, `ChromeSurface` | Persistent native navigation and adaptive chrome |
| `CapacityMeter` | Optional observed capacity and adaptive capsule meter; unknown stays distinct from zero |
| `NativeWindowContract` | Outer minimum sizing and explicit Debug capture-size modes; never destination-driven resizing |
| `ActionStrip`, `ReviewCleanupButton` | Stable primary-action region and explicit native focus restoration |

Examples inside an app-target `View` body (closures refer to the screen's existing model/actions):

```swift
VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
    PageHeader(title: "Downloads", subtitle: "Choose exact files to review.")
    SelectionSummary(value: selectedSize, detail: selectedCount)
    FindingRow(category: .downloads, title: "Downloads",
               detail: eligibilityText, consequence: trashConsequence) {
        Button("Choose items", action: expandItems)
    }
    StatusRow(text: coverageText, symbol: "info.circle")
}.padding(StillDesign.Space.page)
 .background(StillDesign.reading)
```

```swift
MacroCategoryCheckbox(state: selection.categoryState,
    label: "Select all eligible Downloads files",
    enabled: !selection.isPreparing && !selection.rows.isEmpty) {
    Task { await selection.toggleAll() }
}
ActionStrip(message: "Nothing changes until you confirm the next step.") {
    ReviewCleanupButton(enabled: selection.canReview,
                        focusRequest: reviewFocusRequest,
                        action: beginReview)
}
```

`selectedSize`, `selectedCount`, `eligibilityText`, `trashConsequence`, `coverageText` are strings supplied by the screen; `expandItems` and `beginReview` are its actions. These snippets show composition, not a second source of selection policy. `MacroCategoryCheckbox` takes `CategorySelectionState` from StillCore; derive it from the session model. Increment the focus request once after sheet dismissal rather than repeatedly stealing focus.

## Screen and state inventory

This inventory identifies migration ownership, not feature completion. See [DEVELOPMENT.md](DEVELOPMENT.md) for capability gates and [MILESTONES.md](MILESTONES.md) for future scope.

| Surface / source | Shared presentation and states to maintain |
|---|---|
| Workspace / `StillApp.swift` | Persistent sidebar/toolbar, Overview header, capacity and findings; unknown capacity, no selected scope, fixture-only examples |
| Folder inspection / `FolderInspection.swift` | Header, summary/status, inspectable rows and inspector; loading, partial/denied, empty, unknown sizes, selected/mixed controls |
| Cloud inventory / `CloudInventoryView.swift` | Category badge, summary and status; metadata evidence and unsupported guidance, no invented eviction eligibility |
| Live plan and confirmation / `SessionPlan.swift` | Selection summary, category checkbox, inline item refinement, stable action strip, bounded exact-target confirmation; zero/mixed selections, pending/unavailable targets, disabled review, Cancel/focus return |
| Cleanup execution / `CleanupExecutionView.swift` | Shared page/summary/settings/status composition; running/cancel request, per-target outcomes, planned versus observed bytes and actual returned Reveal locations |
| Interrupted cleanup / `CleanupRecoveryView.swift` | Read-only startup evidence, known/pending/unresolved states, blocked journal, fixed return action; no restored plan or retry control |
| Locations & access and History shell / `StillApp.swift` | Settings/empty-state vocabulary; current limitations explicit |
| Alerts / `StorageAlerts.swift`; login / `AppLifecycle.swift` | Page/settings/status rows; off, blocked permission, unavailable capacity, snoozed and independent login status |
| Homebrew / `HomebrewInspection.swift`; pip / `PipInspection.swift`; Docker / `DockerInspection.swift` | Secondary future-scope pages, shared headers/status/summaries; explicit inspection, unavailable/unsupported/timeouts and read-only opportunity reports |
| Managed storage / `ManagedStorageView.swift` | Secondary read-only guidance, shared headers/status; selected metadata and ownership uncertainty |
| What grew / `GrowthHistoryView.swift` | Future-gated completed comparison evidence, shared summary/status/settings rows, fixed explicit-scan action; first/cleared/missing/incompatible/unknown states |
| Component gallery / `DesignGallery.swift` | Developer-only representative components, light/dark, opaque chrome and native selection states |

Future routes retain their feature gates. Browser cleanup, startup recovery, full history, growth and additional roadmap screens must use these primitives when implemented; their presence in the handoff is not evidence they ship today. No scenario picker, sample measurements or gallery toggle belongs in production navigation.

## Native behavior and accessibility

Keep the shell geometry and scroll/action regions defined in the handoff. Expansion changes content, not window size or destination. Category refinement is inline; selecting and inspecting are separate actions. Shared components must preserve model-provided unknown/partial/blocked states and shared session selection.

Use native buttons, toggles, disclosure and AppKit bridges for keyboard focus and mixed state. Name inspection separately from selection. Consequences wrap; long paths use accessible truncation/help or a bounded detail region. Keep confirmation actions visible while its exact-target list scrolls. Restore focus on Cancel without clearing choices.

Review light/dark text, separators, focus and disabled controls under Increased Contrast. The current opaque chrome fallback implements Reduce Transparency; the gallery's forced opaque option exercises that surface, not the whole OS preference. Preserve Reduce Motion and avoid animated layout reflow; manual accessibility checks remain necessary. Test keyboard-only operation and VoiceOver separately from visual capture, including labels for capacity and non-color status meaning. Do not claim accessibility certification from automated accessibility-tree assertions.

Capacity means observed startup-volume capacity in Overview/sidebar, separate from scanned-scope inventory and its coverage. Planned logical/allocated bytes, potentially released bytes, Trash-held bytes and observed capacity are distinct concepts. Reuse must preserve the data meaning and observation time; use unknown text instead of fabricated values.

## Developer gallery and review evidence

Build the Debug app using [DEVELOPMENT.md](DEVELOPMENT.md), then launch its executable explicitly:

```sh
.build/xcode/Build/Products/Debug/Still.app/Contents/MacOS/Still --design-gallery
```

`--design-gallery` is compiled under `DEBUG` and replaces workspace content only for this explicit launch. Its actions are inert examples; forced opaque preview controls belong only there. The product retains its Automatic/Light/Dark appearance preference. `--fixture-workspace` is a separate explicit development/test mode. Real user findings remain outside gallery fixtures.

For each UI change record screenshot paths, revision, appearance, content size, fixture conditions, checked states and known gaps. Capture Overview and populated plan in both appearances, representative changed secondary/settings states, and minimum-size long-path/empty/blocked states. Check category hierarchy and amount alignment, summary restraint, action reachability, focus/selection distinctions, clipping and unchanged window bounds. Include opacity/contrast variants where changed. Store #37 evidence at `docs/validation/design-system.md` with captures in `docs/visual/native-design-system/{before,after}/`; until that report exists and records a check, treat it as pending. Original approved references remain in `docs/visual/` and are not replaced by native output.

For repeatable native review captures, Debug `--design-initial-size` requests up to a 1120 × 760 outer window once at attachment; `--design-minimum` requests up to 900 × 640 once and takes precedence. Both requests fit the current visible screen. These explicit review flags bypass restored dimensions for that launch only. Ordinary production launches fit initial/restored bounds once; navigation never resizes the window. Debug `--design-constrained-screen` supplies a smaller available-frame boundary for native reachability regression without changing display preferences.

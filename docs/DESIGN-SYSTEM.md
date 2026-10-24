# Still native design system

This is the mandatory presentation implementation contract for native UI. [DESIGN-HANDOFF.md](DESIGN-HANDOFF.md) owns interaction requirements; [SPEC.md](SPEC.md) owns product scope and safety. This document owns reuse, component roles and the UI change process. The approved [visual references](visual/README.md) establish hierarchy and tone, rather than pixel measurements for AppKit controls.

## Implementing or changing UI

The [parity checkpoint](PROTOTYPE-PARITY.md) is required in addition to component reuse. A coherent palette cannot compensate for a missing feature or changed workflow. Name affected parity IDs, entry/return routes, category/refinement behavior and exceptional states before implementation; update SPEC and DESIGN-HANDOFF together. The connected [flow lock](FLOW-LOCK.md) is approved; maintain its FL01–FL14 states while reviewing the confirmed presentation in annotated visual states under #45. Toolbar scan status, responsive inspector and location-row hierarchy follow FLOW-LOCK Q27–Q29. Shared examples and screenshots must be reviewed in the complete user journey, not only the gallery.

1. Read the relevant screen/state requirements in the handoff and milestone scope. Locate the existing component in [DesignSystem.swift](../Still/App/DesignSystem.swift) and examples in [DesignGallery.swift](../Still/App/DesignGallery.swift).
2. Reuse the component and semantic tokens. When a required pattern is missing, add a shared component and a gallery example for its meaningful states before composing the screen. Keep domain decisions and filesystem work in their existing models/adapters.
3. Migrate every touched screen to the shared vocabulary. Checkpoint branches created before this system must migrate their UI when resumed, before integration. A local one-off style needs an explicit documented reason in review; recurring patterns belong in the shared component.
4. Review light and dark native captures against the approved references, at initial and minimum window sizes. Exercise changed states through public user journeys. Record captures, checks and remaining limits in validation evidence before merging UI changes.

Complete means every changed screen/state is accounted for, shared examples match the actual API, and the review records what was observed. A successful build or UI test alone does not establish visual fidelity. Changes to interaction or scope also update their authoritative handoff/spec, rather than introducing new behavior through styling.

## Tokens and surfaces

Use `StillDesign.Space` (`xs`, `sm`, `md`, `lg`, `xl`, `page`) for the 4/8/12/16/24/32-point rhythm; `Radius.row` and `.surface` for related rows and summary surfaces. Use `TypeStyle.page`, `.value` and `.section` for hierarchy, native body/callout/caption for supporting text, and monospaced digits for measured values. Read current values in source; avoid copying numeric definitions into screen files.

`StillDesign.reading` is the opaque white/near-black reading plane. `SummarySurface` creates the subdued elevated selection/summary region. `ChromeSurface(role: .sidebar)` is explicitly white in Light appearance, following the user’s October 22 clarification. It preserves native material in Dark appearance. `ChromeSurface()` supplies material for other chrome; both roles use their opaque shared surface tokens where applicable for Reduce Transparency. A light sidebar always stays white, including fallback mode. Native semantic foreground and separator colors carry ordinary text and boundaries. A glass effect must leave reading content legible.

`StillDesign.adaptive` centralizes the approved reference palette as sRGB light/dark pairs. Reading planes are white / `#171719`, summary surfaces `#F7F8FA` / `#232328`, and the dark sidebar `#242428`. Sidebar selection uses a quiet `#E5EDFA` / `#353E51` gradient, rather than a saturated flat accent wash. Keep system text, disabled, focus and separator semantics. The light sidebar stays white. `AppBrand` owns the restrained blue-to-lilac mark; do not recreate it in screens.

Page titles retain the 26-point medium hierarchy with restrained tracking; summary values use 22-point medium and section labels explicit 13-point medium. `SelectionSummary.consequence` groups a wrapped caption with its value rather than adding another full-height page section.

`StorageCategory` supplies a local badge accent and SF Symbol: cloud blue, developer purple, Downloads orange, browser teal, managed indigo. These identify categories; they do not indicate risk, selection or eligibility. `StatusRole` supplies neutral/success/caution/failure icon treatment with an explicit text explanation. Never make meaning depend on color alone.

## Component API and composition

The app target owns these internal SwiftUI components; they are presentation primitives, not a separate public package. Source is authoritative for signatures and defaults.

| Component | Role |
|---|---|
| `PageHeader` | Quiet page title and optional single explanatory subtitle |
| `SummarySurface`, `SelectionSummary`, `VolumeSummary` | Subdued grouped evidence, selected-for-Trash value/detail/consequence and observed startup-volume capacity |
| `RecommendationGroup`, `StorageReviewRow` | Bordered reading-plane category group with shared dividers; badge/title/consequence and trailing amount/meaning; active rows expose action, category, consequence and amount through accessibility, unavailable rows have no dead affordance |
| `FindingRow`, `CategoryBadge` | Category hierarchy, consequence and explicit accessory action |
| `InspectableItemRow` | Separate selection control from filename inspection; size aligned at trailing edge |
| `MacroCategoryCheckbox`, `CategorySelectionHeader` | Native AppKit unchecked/mixed/checked selection; checkbox → badge → category evidence → trailing size composition |
| `ScanProgressSummary` | Bounded preliminary metadata evidence, explicit enumeration/recheck/stability phase, unknown remaining coverage; native spinner plus accessible phase text, no cleanup controls |
| `CleanupScopeNotice` | Existing inspection/Overview guidance; the approved plan replacement uses a contextual category prerequisite, never a permanent global chooser/banner (FLOW-LOCK Q4/Q5) |
| `StatusRow`, `EmptyState` | Honest status, blocked/error explanation, or no findings yet |
| `SettingsRow` | Setting title, explanation and native controls |
| `AppBrand`, `StillSidebarRow`, `ChromeSurface` | Shared brand, persistent native navigation, destination accents and adaptive chrome |
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

`selectedSize`, `selectedCount`, `eligibilityText`, `trashConsequence`, `coverageText` are strings supplied by the screen; `expandItems` and `beginReview` are its actions. These snippets show composition, not a second source of selection policy. `MacroCategoryCheckbox` propagates enabled state through both SwiftUI and its native bridge; never rely only on setting `NSButton.isEnabled`, which SwiftUI can override. It takes `CategorySelectionState` from StillCore; derive it from the session model. Increment the focus request once after sheet dismissal rather than repeatedly stealing focus.

## Connected recurring patterns

The [visual review](CONNECTED-FLOW-DESIGN-REVIEW.md) illustrates these approved responsibilities. The first Downloads slice implements the native APIs below, with meaningful Gallery examples. Their presence does not qualify every FL branch; see [connected validation](validation/connected-downloads.md). Keep domain policy in the observation/selection models.

| Pattern | Responsibilities / states |
|---|---|
| `ToolbarScanStatus` | Shared phase/entry evidence, Stop and return-to-origin while away; no completion navigation or invented percentage; FL07/FL08 |
| `LocationScopeRow` | Inclusion, folder/path, current access/coverage and optional `overlap` explanation; fixed-size direct actions trail at wide widths and move below identity/status at compact widths; secondary Forget, editing paused during scan; Q29/FL09 |
| `CategoryPrerequisite` | Not scanned/empty/partial versus eligible count and logical size; contextual scan/recheck within the stable plan; no permanent setup banner; FL01–FL06 |
| `ExplorerInspector` | Separate folder navigation/info/file inspection/selection; right pane or compact bounded panel above footer, preserved context; FL10/FL11 |
| Contextual return / `DestinationViewport` | Caller-labelled Back, viewport/query/inspector restoration and existing-ancestor reuse; no Plan/Explorer cycle; Q17/Q24 |

## Screen and state inventory

This inventory identifies migration ownership, not feature completion. See [DEVELOPMENT.md](DEVELOPMENT.md) for capability gates and [MILESTONES.md](MILESTONES.md) for future scope.

| Surface / source | Shared presentation and states to maintain |
|---|---|
| Workspace / `StillApp.swift` | Persistent sidebar/toolbar, Overview header, capacity and grouped real findings; unknown capacity, no selected scope, partial/unavailable/rechecking and fixture-only examples ([Overview restoration evidence](validation/overview-restoration.md)); opened-alert historical timestamp/unavailable context uses existing SummarySurface and StatusRow with explicit folder choice/dismissal ([validated states](validation/alert-open-context.md)) |
| Folder inspection / `FolderInspection.swift` | Header, summary/status, inspectable rows and inspector; loading, partial/denied, empty, unknown sizes, selected/mixed controls |
| Cloud inventory / `CloudInventoryView.swift` | Category badge, summary and status; metadata evidence and unsupported guidance, no invented eviction eligibility |
| Live plan and confirmation / `SessionPlan.swift` | Selection summary, category checkbox, inline item refinement, stable action strip, bounded exact-target confirmation; zero/mixed selections, pending/unavailable targets, disabled review, Cancel/focus return |
| Cleanup execution / `CleanupExecutionView.swift` | Shared page/summary/settings/status composition; running/cancel request, per-target outcomes, planned versus observed bytes and actual returned Reveal locations |
| Interrupted cleanup / `CleanupRecoveryView.swift` | Read-only startup evidence, known/pending/unresolved states, blocked journal, fixed return action; no restored plan or retry control |
| Locations & access / `StillApp.swift` | Shared settings and empty-state vocabulary; actual scope/access evidence |
| Completed History / `CleanupHistoryView.swift` | Shared headers, summaries, settings/status rows; native Clear/Reset confirmations and protected recovery route. Hosted CI qualifies the clear/reset journeys and captured populated/blocked/confirmation states at 38a593e; uncaptured/manual gates remain in `validation/history-reset.md`. |
| Alerts / `StorageAlerts.swift`; login / `AppLifecycle.swift` | Page/settings/status rows; off, blocked permission, unavailable capacity, snoozed and independent login status |
| Homebrew / `HomebrewInspection.swift`; pip / `PipInspection.swift`; Docker / `DockerInspection.swift` | Secondary future-scope pages, shared headers/status/summaries; explicit inspection, unavailable/unsupported/timeouts and read-only opportunity reports. Homebrew uses pinned staged-shell fast paths plus explicit cache metadata; unsupported source shows guidance without zero inventory. |
| Diagnostics / `DiagnosticsView.swift` | Secondary future-gated exact payload preview, included/excluded fields and frozen cancelled/failed/saved states; shared fixed Back/Save ActionStrip; [clean hosted header/payload captures at 0e8a143](validation/redacted-diagnostics.md) qualify both themes and sizes, with uncaptured/manual gates retained |
| Managed storage / `ManagedStorageView.swift` | Secondary read-only guidance, shared headers/status; selected metadata and ownership uncertainty |
| What grew / `GrowthHistoryView.swift` | Future-gated completed comparison evidence, shared summary/status/settings rows, fixed explicit-scan action; first/cleared/missing/incompatible/unknown states |
| Component gallery / `DesignGallery.swift` | Developer-only representative components, light/dark, opaque chrome and native selection states |

Future routes retain their feature gates. Browser cleanup and additional roadmap screens must use these primitives when implemented. Implemented recovery, history and future-gated growth use the same vocabulary; each validation report distinguishes tested behavior from remaining qualification gates. No scenario picker, sample measurements or gallery toggle belongs in production navigation.

## Native behavior and accessibility

For selection-only updates, check content anchoring as well as the outer window frame: the clicked visible control should retain its viewport position after selection settles. Use the actual scroll viewport to establish visibility; accessibility hit testing alone can include off-screen rows. The [checkbox movement investigation](validation/checkbox-content-anchor.md) records the scrolled-category reproduction and focused fix. Do not bind a mixed summary/list scroll pane to item-ID scroll targets solely to preserve selection scrolling; selection updates must preserve the native viewport. Explicit navigation restoration is a separate concern.

Keep the shell geometry and scroll/action regions defined in the handoff. Expansion changes content, not window size or destination. Category refinement is inline; selecting and inspecting are separate actions. Shared components must preserve model-provided unknown/partial/blocked states and shared session selection.

Use native buttons, toggles, disclosure and AppKit bridges for keyboard focus and mixed state. Name inspection separately from selection. Consequences wrap; long paths use accessible truncation/help or a bounded detail region. Keep confirmation actions visible while its exact-target list scrolls. Native macOS disclosure arrows extend before their labels: use the shared leading control gutter (`StillDesign.Space.xl`) inside bounded scrolling content so the actual arrow stays within the clip. Test visible native glyph activation and expanded contents, not label clicks or clipped coordinates. Restore focus on Cancel without clearing choices.

Review light/dark text, separators, focus and disabled controls under Increased Contrast. The current opaque chrome fallback implements Reduce Transparency; the gallery's forced opaque option exercises that surface, not the whole OS preference. Preserve Reduce Motion and avoid animated layout reflow; manual accessibility checks remain necessary. Test keyboard-only operation and VoiceOver separately from visual capture, including labels for capacity and non-color status meaning. Do not claim accessibility certification from automated accessibility-tree assertions.

Capacity means observed startup-volume capacity in Overview/sidebar, separate from scanned-scope inventory and its coverage. Planned logical/allocated bytes, potentially released bytes, Trash-held bytes and observed capacity are distinct concepts. Reuse must preserve the data meaning and observation time; use unknown text instead of fabricated values.

## Developer gallery and review evidence

Build the Debug app using [DEVELOPMENT.md](DEVELOPMENT.md), then launch its executable explicitly:

```sh
.build/xcode/Build/Products/Debug/Still.app/Contents/MacOS/Still --design-gallery
```

`--design-gallery` is compiled under `DEBUG` and replaces workspace content only for this explicit launch. Its actions are inert examples; forced opaque preview controls belong only there. The product retains its Automatic/Light/Dark appearance preference. `--fixture-workspace` is a separate explicit development/test mode. Real user findings remain outside gallery fixtures.

For each UI change record screenshot paths, revision, appearance, content size, fixture conditions, checked states and known gaps. Capture Overview and populated plan in both appearances, representative changed secondary/settings states, and minimum-size long-path/empty/blocked states. Check category hierarchy and amount alignment, summary restraint, action reachability, focus/selection distinctions, clipping and unchanged window bounds. Include opacity/contrast variants where changed. Store #37 evidence at `docs/validation/design-system.md` with captures in `docs/visual/native-design-system/{before,after}/`; until that report exists and records a check, treat it as pending. Original approved references remain in `docs/visual/` and are not replaced by native output.

For repeatable native review captures, Debug `--design-initial-size` requests a 1120-point outer width and 760-point height when that height fits; on a shorter display it uses the approved 640-point minimum height. `--design-minimum` requests 900 × 640 and takes precedence. Both requests still clamp to the current visible screen if necessary. This is an explicit capture preset: it avoids deriving a different baseline from small native available-area changes across launches. Ordinary production initial/restored sizing is unchanged. These explicit review flags bypass restored dimensions and place the fitted window at the current visible screen’s top-left corner for that launch only, so native restoration/cascade offsets do not alter capture baselines. These Debug modes fit on the first native window update while the window is active, key and visible; attachment or first-key activation alone can still expose transient available-screen metrics. Workspace layout is retained but presentation, accessibility and hit testing wait until the app’s own deferred fit completes. Tests then use ordinary visible controls as readiness and retain exact subsequent frame-equality checks. Do not calculate the expected available area from the UI test runner’s `NSScreen`: its cached visible frame can differ from the active application’s frame. Ordinary production launches fit initial/restored bounds once; navigation never resizes the window. Debug `--design-constrained-screen` supplies a smaller available-frame boundary for native reachability regression without changing display preferences.

Checkpoint rhythm migration: screen sections use `Space.xl`, compact confirmation grouping uses `Space.lg`, label/target-list groups use `Space.md`, row inset uses `Space.sm`, and tightly related metadata uses `Space.xs`. Legacy 20/18/10/5-point rhythm literals are normalized to those existing semantic roles (24/16/12/4); no new token or screen redesign is introduced. Zero spacing at adjoining reading/chrome/action regions is intentional structural abutment. Native control frames, the fixed bounded confirmation size, badge dimensions, line widths and zero action-strip inset are geometry rather than repeated spacing tokens; preserve those local native/layout contracts.

M6 custom exclusions compose existing settings/summary/status surfaces under Locations & access. The fixed action strip owns Choose or explicit preview Save/Cancel; rule removal stays beside its rule. Empty, preview, saved, unreadable-settings and changed-coverage states are documented in [exclusion validation](validation/exclusions.md); clean hosted qualification at `d230958` covers the initial/minimum native journeys and twelve Light/Dark captures; later visual revisions require their own source-pinned review.

### Fixed action composition

Place an interactive `ActionStrip` as a **sibling after `ScrollView` in a zero-spacing `VStack`**, as `LiveCleanupPlanView`, the developer gallery and the secondary workspace routes do. The scroll region shrinks above the strip; the strip remains visible and reachable at initial/minimum bounds. Do not mount these actions with `ScrollView.safeAreaInset`: on the supported hosted macOS 26.6 runner that composition rendered enabled buttons inside the window while accessibility hit-testing rejected the entire strip. A sibling strip fixed the same public journey without changing control labels, actions or geometry. See [native footer reachability evidence](validation/footer-reachability.md).

```swift
VStack(spacing: 0) {
    ScrollView { destinationContent }
    ActionStrip(message: consequenceText) {
        Button("Continue", action: continueReview)
    }
}
```

Check actual enabled/hittable controls and successful actions, including after content/appearance changes; frame containment and screenshots alone do not establish reachability.

## Reference fidelity pass — October 23, 2026

The revision 0.9 personal Light/Dark references remain the comparison authority, with the subsequent explicitly white Light sidebar clarification. Match their grouping, muted accents and hierarchy, while preserving real native controls and tested window/interaction contracts.

- Sidebar labels are secondary until selected; destination symbols use blue, purple, teal or neutral accents. Selection has a subtle surface gradient. Storage and Settings remain labelled groups.
- `CategorySelectionHeader` keeps the native checkbox before the category badge, with a separately readable title/consequence and trailing amount. Only the checkbox changes selection; badges/titles do not duplicate that action. Hiding the visual native title preserves its full accessibility label, mixed state, identifier and target/action.
- `VolumeSummary` puts the device identity and available capacity on one balanced header above a neutral used-capacity meter and observation metadata. Never copy the reference's synthetic category segments into real capacity evidence. Unknown remains unknown.
- Recheck remains a standard native bordered button with its existing accessibility/control role. A caption-link styling experiment made the existing public Button lookup unreachable on hosted macOS; preserve the native affordance rather than weakening the journey.
- Related plan evidence uses the 16-point grouping rhythm; the summary/consequence is one unit. Empty refresh containers consume no inter-section space. Inline refinement retains its native disclosure gutter and separate inspect/select controls.
- `ActionStrip` uses large native capsule-style actions; the AppKit review button uses the corresponding large control size and retains its one-shot focus bridge. It stays a sibling below scrolling content. No custom button event handling, layout animation, destination-driven sizing or floating footer is introduced.
- On macOS 26+, the informational toolbar context has no shared button background. It remains text, while Appearance remains a native labelled picker. Earlier supported configurations use the standard toolbar fallback.

See [fidelity validation](validation/visual-fidelity.md) for exact source, captures, public regression results and remaining manual limits. A build alone is not visual acceptance.

`ReviewCleanupButton` propagates its model-provided enabled state through SwiftUI `.disabled` as well as the native AppKit property. Keep both: native picker dismissal can otherwise expose an enabled-looking review control for an empty plan. The scope-guidance native journey exercises repeated picker cancellation and appearance changes; the gallery uses the actual disabled shared button.

## Inspector evidence and adaptive location rows — #58/#59

`LocationScopeRow.overlap` is optional explanatory copy supplied by configuration policy. `ViewThatFits` preserves full action labels; shared layout falls back below identity instead of screen-local truncation/width fixes. Gallery includes unavailable-overlap and omitted/editing-paused states. Inclusion/Forget semantics remain model-owned.

`ExplorerInspector` keeps Close outside its bounded evidence scroll. Location, observed scope/time, logical/on-disk evidence, Why listed and Cleanup action are separate fields. The evidence column uses shared horizontal `Space.xs` inset to keep selectable native text frames inside its viewport. `SessionPlan.inspectionRestriction` explains the existing eligible boundary; its text grants no selection/execution authority. Folder/package/link/cloud/unknown/stale and outside-Downloads cases remain explicit. Gallery uses labelled synthetic content; it cannot certify provider behavior. See [qualification](validation/connected-next.md) before treating these candidate states as integrated proof.

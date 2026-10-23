# Native design-system validation — #37

October 22, 2026. Native SwiftUI/AppKit review on macOS 27 with Xcode 27.1; deployment target remains macOS 14. The local build does not establish runtime behavior on macOS 14 or distribution signing readiness.

## Authority and resulting presentation

The review used the approved `personal-light.png` and `personal-dark.png`, the handoff, and the component/reference audits. The native interpretation preserves the real titlebar, traffic lights, system controls and focus behavior. Shared page hierarchy, category accents, summary surfaces, rows and fixed action strips replace per-screen styling.

The user's subsequent clarification makes the **light sidebar explicitly white**. `ChromeSurface(role: .sidebar)` owns that policy, including opaque fallback; native material remains appropriate for other chrome and the dark sidebar. This clarification supersedes the earlier reference's cool-gray sidebar appearance. Approved reference images are retained as historical design references, without repainting.

Foundation: `a316253`. Screen migration: `bcfc41a`. Native review/copy/accessibility refinements: `1f34f1f`, `940dbec`. White sidebar and repeatable initial-size review: `a647d7d`. Documentation foundation from `02b0d6c` is merged. Paused #10 and #34 feature checkpoints are **not** included; #8's selection/confirmation checkpoint is included and its Cancel/focus/final immutable approval journey was qualified here. No mutation executor is included.

## Captures

Actual native XCTest window screenshots are stored in [before](../visual/native-design-system/before/) and [after](../visual/native-design-system/after/). [Capture provenance](../visual/native-design-system/captures.json) records source runs and logical window sizes. Screenshots are 2× Retina pixels. Example measurements/names come from explicit fixture mode or owned disposable folders; startup capacity is real capacity-only metadata, labelled separately from selected-scope inventory. No personal directory enumeration was used for design review.

| Review surface | Captures in `after/` |
|---|---|
| Native Overview, selected-folder inspection | `native-overview-{Light,Dark}.png`, `native-inspection-{Light,Dark}.png` |
| Populated live plan and immutable confirmation | `native-plan-{Light,Dark}.png`, `native-confirmation-{Light,Dark}.png` |
| Locations and opt-in alert settings | `native-locations-{Light,Dark}.png`, `native-alert-settings-{Light,Dark}.png` |
| Minimum long-path plan and bounded sheet | `native-plan-minimum-opaque-{Light,Dark}.png`, `native-confirmation-minimum-{Light,Dark}.png` |
| Minimum component gallery, mixed/disabled controls, status/empty/busy states | `gallery-minimum-{Light,Dark}.png`, `gallery-states-minimum-{Light,Dark}.png` |
| Opaque material fallback | `gallery-minimum-opaque-Dark.png` |
| Explicit fixture comparison with baseline | `overview-*`, `inspection-*`, `plan-*`, `settings-*` |

Before captures are the native pre-system shell at checkpoint `5618107`, 1120 × 760. Initial-size after captures use the explicit Debug `--design-initial-size` mode, 1120 × 760. Minimum captures use Debug `--design-minimum`, 900 × 640. These modes set the window once at attachment; navigation, selection, appearance changes and sheets do not resize it. Ordinary user-resized window restoration remains an OS integration gate rather than being certified by the controlled capture modes.

Visual comparison confirmed the compact hierarchy, restrained color, opaque reading plane, distinct name/checkbox affordances, quiet summary and reachable bottom action. Earlier captures exposed a low-contrast light capacity bar and clipped gallery appearance values; the shared capsule meter and adequately sized selector correct those findings. Volume/cloud provenance is secondary to inspected files, while partial/unknown coverage and recovery remain prominent. Repeated selected/eligible plan lists were replaced by one inline refinement list; unavailable selected observations remain separately explained. Technical size/identity details sit in disclosures.

## Checks and exact limits

- StillCore: **43 tests passed**. Existing scanner/selection/immutable review and adapter fixture boundaries remain unchanged.
- StorageAlerts package: **15 tests passed**.
- Native Debug build succeeded. **All 16 current native journeys have passing evidence across the full and affected runs**, rather than a claim that one final full-suite invocation was green.
- The broad `design-regression.xcresult` run passed 13 of 15 journeys. Its two failed journeys were the old alert test's fixture-only Overview assertions and a capture journey whose offscreen selection had not been confirmed. Production-route assertions were corrected, inspection hierarchy moved files ahead of secondary evidence, and the capture now asserts checked membership before review. The separately added gallery journey brings the current suite to 16.
- `design-final-affected.xcresult`: **6/6 passed** — production alert navigation/default-off state, disposable metadata inspection, shared selection/search/window-close/Quit behavior, unavailable-folder unknown/recovery state, populated native design captures/confirmation, and minimum gallery/fallback capture.
- The broad run's passing bulk journey covers category select-all, mixed state, exact 20→19 membership, bounded confirmation, Cancel restoring Review focus, Space reopening review and final immutable approval. It reads only its own disposable sentinel to verify no mutation.
- Its passing minimum long-path journey verifies actual 900 × 640 outer bounds in both themes, a reachable Review action after scrolling, visible sheet actions, Escape cancellation and unchanged outer bounds.

`design-white-sidebar.xcresult`: **3/3 passed** after the final white-sidebar fill and capture-only initial-size mode, refreshing actual Overview/inspection/plan/confirmation/settings and gallery captures. `design-white-minimum.xcresult`: **1/1 passed** and replaces minimum plan/sheet captures with the final white policy. These do not change domain policy or filesystem behavior. Root visually confirmed the final white sidebar, meter, hierarchy and action strip; independent component/visual/document reviewers reported no remaining blocking findings. Test bundles are generated local outputs, not committed artifacts; the captures and this result summary are retained.

## Accessibility and remaining gates

The gallery renders native unchecked/mixed/checked/disabled controls and busy/empty/caution/error examples. Native keyboard and sheet behavior above passed. Capacity and status have text equivalents; category color never carries essential meaning alone. `SummarySurface` responds to the actual Increased Contrast environment. No custom layout animation was introduced.

Forced opaque chrome exercises the same shared fallback branch as Reduce Transparency without changing macOS preferences. Full OS preference propagation, Increased Contrast, Reduce Motion, VoiceOver, localization and larger-text review remain **manual, unverified gates**. The native computer-use connector was unavailable, so captures and interactions used authorized XCTest rather than requesting new system privileges. Screenshots and AX assertions do not certify accessibility.

Real TCC changes, iCloud behavior, login registration, notification delivery, Quick Look/Finder integration, filesystem mutation and crash recovery retain their separate milestone validation gates. Design-system completion does not qualify future adapters or execution.

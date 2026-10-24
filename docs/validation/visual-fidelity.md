# Visual fidelity pass — October 23, 2026

## Reference and scope

Compare the approved revision 0.9 [personal Light](../visual/personal-light.png) and [personal Dark](../visual/personal-dark.png) designs and their `preview-source.html` palette/layout. The user's later white Light sidebar decision supersedes the cool-grey historical sidebar. Starting implementation: `93fc16d`.

The pass changes shared presentation and its screen composition: reference palette, muted category/navigation accents, selected navigation surface, brand, typography, capacity card, grouped selection consequence, checkbox/badge order, native primary control sizing and quiet toolbar context. The gallery demonstrates the same primitives. All scanner, selection, approval, executor, recovery, exclusion and alert models remain unchanged. Native controls, exact target consequences and feature gates remain authoritative.

## Intentional native/data differences

Native traffic lights, window corners, control focus and appearance picker follow macOS. The real app's scrolling body and fixed sibling footer preserve the already qualified action reachability contract. Reference category-coloured capacity segments are synthetic; actual capacity uses one neutral measured meter with the same unknown/provenance semantics. No fixture values become production data. Long exact paths and protected/unavailable states remain visible even when the web reference uses shorter sample copy.

## Source-pinned verification

Final source: `524f878f25f55fd861c0d125e76e99c691ec0aae`.

| Hosted check | Result |
| --- | --- |
| [Full native run 39963991881](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39963991881) | **34/34 journeys passed**, zero failures/skips, 1253.366 seconds. Includes design/window/refresh, cleanup/cancel/retry, recovery/history, exclusions and diagnostics journeys. |
| [Focused exclusions run 39963988565](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39963988565) | **2/2 passed**, zero failures, 234.556 seconds. Initial/minimum journeys retain all original exact frame/action/persistence assertions and add two public-ready relaunch checks per size. |
| [Predecessor-prefix run 39964019612](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39964019612) | **6/6 passed**, zero failures, 368.168 seconds: CleanupRetry, Diagnostics and Exclusions. Workflow-only child `c2e68b479039efd8c46bb277e597fe6a0e7d9b35` has byte-identical app/test sources; only the manual selector differs. The child does not integrate. |

The final full run also passed **117 core**, **20 alert/lifecycle**, and **19 disposable adapter-investigation** tests, then built the app/UI runner. Captures were produced on hosted macOS 26.6.2, arm64 Apple Virtual Machine. The [main manifest](../visual/fidelity/manifest.json) records 33 unaltered original PNGs from the final full run; the [exclusions manifest](../visual/fidelity/exclusions/manifest.json) records 12 originals from the final focused run. Each records exact source, run, artifact, test identifier, attachment name, dimensions and SHA-256. **All 45 final-source images were individually viewed and their hashes/dimensions verified.** Repository fidelity evidence contains only final-source images. Earlier captures, failed-run/probe logs and result bundles remain outside the checkout under `notes/fidelity-*` and `notes/geometry-*`.

On this constrained display, explicit initial captures are **1024 × 640**, minimum captures **900 × 640**. Debug initial capture mode uses the approved 760-point height only when it fits, otherwise the approved 640-point height (still clamped for smaller displays); width remains display-fitted. Larger-desktop 1120 × 760 captures are **not qualified by this run**. Ordinary/Release launches retain their existing one-shot initial/restored fitting behavior.

## Visual review

No new clipped essential text, hidden fixed action or control-layout blocker was observed in the final capture set. The Light sidebar stays white; Dark reading and summary planes retain the approved near-black hierarchy. Selected navigation now uses a restrained explicit overlay instead of generated bevelled shading. Exact paths and consequences wrap, and native confirmation actions remain within their sheets at initial and minimum bounds. Scrolling content retains one fixed, reachable action region.

Representative final captures:

- Native [Overview Light](../visual/fidelity/native-overview-Light.png) / [Dark](../visual/fidelity/native-overview-Dark.png), [inspection Light](../visual/fidelity/native-inspection-Light.png) / [Dark](../visual/fidelity/native-inspection-Dark.png).
- Populated [plan Light](../visual/fidelity/native-plan-Light.png) / [Dark](../visual/fidelity/native-plan-Dark.png), [confirmation Light](../visual/fidelity/native-confirmation-Light.png) / [Dark](../visual/fidelity/native-confirmation-Dark.png).
- Minimum long-path [plan Light](../visual/fidelity/native-plan-minimum-opaque-Light.png) / [Dark](../visual/fidelity/native-plan-minimum-opaque-Dark.png), [confirmation Light](../visual/fidelity/native-confirmation-minimum-Light.png) / [Dark](../visual/fidelity/native-confirmation-minimum-Dark.png).
- Native [Locations Light](../visual/fidelity/native-locations-Light.png) / [Dark](../visual/fidelity/native-locations-Dark.png), [alerts Light](../visual/fidelity/native-alert-settings-Light.png) / [Dark](../visual/fidelity/native-alert-settings-Dark.png).
- Minimum [gallery Light](../visual/fidelity/gallery-minimum-Light.png) / [Dark](../visual/fidelity/gallery-minimum-Dark.png), [opaque Dark simulation](../visual/fidelity/gallery-minimum-opaque-Dark.png), scrolled navigation/capacity states [Light](../visual/fidelity/gallery-states-minimum-Light.png) / [Dark](../visual/fidelity/gallery-states-minimum-Dark.png).
- Refresh-required [Light](../visual/fidelity/refresh-required-Light.png) / [Dark](../visual/fidelity/refresh-required-Dark.png), changed-target [Light](../visual/fidelity/refresh-changed-Light.png) / [Dark](../visual/fidelity/refresh-changed-Dark.png): retained search/choice context, visible freshness notices and disabled review match the public journey.

Additional final exclusions captures cover empty, preview and saved rules in both themes and sizes. Minimum [empty Light](../visual/fidelity/exclusions/exclusions-empty-minimum-Light.png) / [Dark](../visual/fidelity/exclusions/exclusions-empty-minimum-Dark.png), [preview Light](../visual/fidelity/exclusions/exclusions-preview-minimum-Light.png) / [Dark](../visual/fidelity/exclusions/exclusions-preview-minimum-Dark.png), and [saved Light](../visual/fidelity/exclusions/exclusions-saved-minimum-Light.png) / [Dark](../visual/fidelity/exclusions/exclusions-saved-minimum-Dark.png) keep wrapped exact paths/consequences and fixed native actions visible. Original exclusions validation/captures retain their historical source attribution.

The remaining eight comparison captures show explicitly labelled synthetic Overview, inspection, plan and Locations states in both themes. Fixture capacity is never presented as a production measurement; actual capacity remains neutral and labelled. Gallery opaque chrome is a developer-forced fallback simulation, not a claim that the OS Reduce Transparency setting was exercised.

## Observed regression and correction

The intermediate `ed42ad1` presentation changed Recheck location to a caption link. [Focused run 39945557245](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39945557245) passed six design/window journeys but failed the unchanged refresh journey's native Button lookup/hittability assertion at `WorkspaceUITests.swift:475`. The record does not establish an OS-level cause. `7a7199f` restored the existing standard native Button treatment, retained in final `524f878`; the original assertion and full refresh journey passed. Keeping that native action appearance is an intentional functional difference from the reference, not a test workaround. No assertion was weakened.

## Capture-fixture geometry diagnosis

Earlier full `7a7199f` and `d90ba8a` runs each passed 33/34 tests but failed the initial exclusions journey's exact cross-launch frame comparison: 1024 × 674 versus 1024 × 677. An unchanged focused repeat passed, so the failure was intermittent. Native probes measured an actual available-display boundary changing from `(0,63,1024,674)` to `(0,60,1024,677)` during activation: the top edge stayed fixed while the lower exclusion changed. First-key alone sometimes still saw the earlier boundary. A test-runner `NSScreen` oracle was also invalid: it reported 674 while the active app reported 677. These observations do not establish a production navigation resize or an OS defect.

Presentation-after-fit and a deterministic capture origin alone were insufficient: the predecessor-prefix journey still exposed differing maximum fitted heights. The final **explicit Debug capture fixture** uses approved fixed height presets instead of that fluctuating maximum, anchors at the current visible top-left, and presents the normal workspace after the existing fitter runs on the first active/key/visible native window update. The observer is removed before fitting; there are no retry ticks or arbitrary sleeps. Ordinary/Release fitting and product models remain unchanged. Tests observe normal public controls; no private readiness flag, hardcoded 674/677 value, tolerance increase or removal of cross-launch comparisons is used. Temporary probe instrumentation and the invalid runner-screen oracle were removed. Final focused, prefix and full runs above pass the original comparisons plus the added relaunch checks.

Personal, real provider/mount, signed notification/login, VoiceOver, actual OS accessibility settings, ordinary display restoration and release qualification remain separate gates. Gallery opaque chrome is a simulation rather than OS accessibility certification. No personal scan, cleanup or local UI launch was part of this evidence task.

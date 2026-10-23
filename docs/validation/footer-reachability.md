# Native secondary-footer reachability

The original exclusions journeys deterministically failed `Save exclusion.isHittable` at initial and minimum bounds on clean hosted Xcode/macOS 26.6, while the button was enabled and visually inside the window. Runs [39905168716](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39905168716) and [39905512481](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39905512481) establish the original red feedback.

## Diagnosis

A manual `Native Mac workspace` dispatch with `suite=exclusions` retains normal core/alert/adapter checks and the native build, then runs only `ExclusionsUITests`. Normal pushes and pull requests always run the full suite. The manual choice defaults to `all`.

Temporary tagged probes captured model busy/maintenance/execution flags, modal/picker state, native activation and key-window state, baseline/sibling control hittability, AX hierarchy and explicit PNG screenshots. The screenshots were unobscured; Save was blue and inside the fixed footer. Busy flags were false. App/window AX `Enabled=false` was also present before the picker and therefore was not evidence of a stuck modal. Releasing the picker in a synchronous helper did not change the failure and was reverted.

The decisive [baseline probe](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39909592532) found the entire footer non-hittable **before** the picker, with the sidebar hittable. Native activation/key-window state was normal. The sibling-layout probe changed only the secondary footer from a `ScrollView.safeAreaInset` to a sibling below the scroll view in its existing `VStack`, matching the passing live cleanup plan. [Run 39910480532](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39910480532) then reported Choose/Back/Cancel/Save all hittable and successfully saved the rule, persisted it, relaunched, scanned only included entries and checked both themes. This run later crashed inside XCTest's dynamic-label identifier query, so it is **not** a whole-journey pass.

The Remove lookup now matches the identical public full label using `NSPredicate(label == ...)` instead of the crashing XCTest convenience identifier subscript. It neither changes the label nor bypasses native interaction. [Run 39911441259](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39911441259) passed the entire initial journey **1/1 in 89.683 seconds**, including native removal, persisted empty rules and unchanged fixture files.

The final product fix is the fixed sibling footer. The original picker and Save implementation remain unchanged. Temporary probes are removed. The original strict Save enabled/hittable assertion is preserved; Choose and diagnostics Back/Save checks also assert actual reachability. No coordinate bypass, arbitrary sleep, permission change, personal scan or OS-warning workaround was used.

## Final qualification

The probe-free [focused run 39912298566](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39912298566) at `d230958d3a7a5562f17a2c60047a27ea7dd803cc` passed **2/2 in 187.915 seconds** (initial 96.098 s, minimum 91.817 s). Both original flows retain native picker → preview → enabled/hittable Save, persistence across relaunch, included-only scan, theme/bounds checks, exact-label native removal, persisted empty rules and unchanged fixture contents. No temporary probe or picker-lifetime change remains.

All **12 unaltered** empty/preview/saved PNGs were individually viewed: no overlay, essential-text clipping or hidden fixed action was observed. The light sidebar is white, dark surfaces remain near-black, long paths/consequences wrap, and both sizes keep Back/Choose or Back/Cancel/Save readable and reachable. [Capture manifest](../visual/exclusions/manifest.json) records source/run/artifact/attachment provenance, dimensions and SHA-256 hashes.

| State and bounds | Light | Dark |
|---|---|---|
| Empty · initial 1024×677 | [capture](../visual/exclusions/exclusions-empty-initial-Light.png) | [capture](../visual/exclusions/exclusions-empty-initial-Dark.png) |
| Empty · minimum 900×640 | [capture](../visual/exclusions/exclusions-empty-minimum-Light.png) | [capture](../visual/exclusions/exclusions-empty-minimum-Dark.png) |
| Preview · initial | [capture](../visual/exclusions/exclusions-preview-initial-Light.png) | [capture](../visual/exclusions/exclusions-preview-initial-Dark.png) |
| Preview · minimum | [capture](../visual/exclusions/exclusions-preview-minimum-Light.png) | [capture](../visual/exclusions/exclusions-preview-minimum-Dark.png) |
| Saved rule · initial | [capture](../visual/exclusions/exclusions-saved-initial-Light.png) | [capture](../visual/exclusions/exclusions-saved-initial-Dark.png) |
| Saved rule · minimum | [capture](../visual/exclusions/exclusions-saved-minimum-Light.png) | [capture](../visual/exclusions/exclusions-saved-minimum-Dark.png) |

The normal push [full run 39912299004](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39912299004) at the same source passed **34/34 native journeys with 0 failures in 1235.246 seconds**, including both diagnostics journeys with enabled/hittable Back/Save assertions and both exclusions journeys. All workflow stages passed: 117 core tests, 20 alert-policy tests, isolated adapter investigations and native build-for-testing. Local Xcode 27.1 clean core tests passed **117/117**; Debug build-for-testing and Release build passed. The preserved Release candidate is documented in the [personal-build walkthrough](personal-build-walkthrough.md). Native sources have not changed in subsequent review/evidence-only commits. Minimum-OS, Intel execution, manual OS/accessibility and personal-launch gates remain separate; these captures do not qualify uncaptured error/recovery states.

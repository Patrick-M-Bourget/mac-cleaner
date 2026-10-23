# Native secondary-footer reachability

The original exclusions journeys deterministically failed `Save exclusion.isHittable` at initial and minimum bounds on clean hosted Xcode/macOS 26.6, while the button was enabled and visually inside the window. Runs [39905168716](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39905168716) and [39905512481](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39905512481) establish the original red feedback.

## Diagnosis

A manual `Native Mac workspace` dispatch with `suite=exclusions` retains normal core/alert/adapter checks and the native build, then runs only `ExclusionsUITests`. Normal pushes and pull requests always run the full suite. The manual choice defaults to `all`.

Temporary tagged probes captured model busy/maintenance/execution flags, modal/picker state, native activation and key-window state, baseline/sibling control hittability, AX hierarchy and explicit PNG screenshots. The screenshots were unobscured; Save was blue and inside the fixed footer. Busy flags were false. App/window AX `Enabled=false` was also present before the picker and therefore was not evidence of a stuck modal. Releasing the picker in a synchronous helper did not change the failure and was reverted.

The decisive [baseline probe](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39909592532) found the entire footer non-hittable **before** the picker, with the sidebar hittable. Native activation/key-window state was normal. The sibling-layout probe changed only the secondary footer from a `ScrollView.safeAreaInset` to a sibling below the scroll view in its existing `VStack`, matching the passing live cleanup plan. [Run 39910480532](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39910480532) then reported Choose/Back/Cancel/Save all hittable and successfully saved the rule, persisted it, relaunched, scanned only included entries and checked both themes. This run later crashed inside XCTest's dynamic-label identifier query, so it is **not** a whole-journey pass.

The Remove lookup now matches the identical public full label using `NSPredicate(label == ...)` instead of the crashing XCTest convenience identifier subscript. It neither changes the label nor bypasses native interaction. [Run 39911441259](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39911441259) passed the entire initial journey **1/1 in 89.683 seconds**, including native removal, persisted empty rules and unchanged fixture files.

The final product fix is the fixed sibling footer. The original picker and Save implementation remain unchanged. Temporary probes are removed. The original strict Save enabled/hittable assertion is preserved; Choose and diagnostics Back/Save checks also assert actual reachability. No coordinate bypass, arbitrary sleep, permission change, personal scan or OS-warning workaround was used.

## Final qualification

Clean initial/minimum exclusions journeys, unobscured Light/Dark empty/preview/saved captures and the full native regression suite are being qualified on the final probe-free source. Results and capture provenance will be recorded here when complete. Local Xcode 27.1 core tests passed **117/117** and Debug build-for-testing passed during diagnosis; final source build checks follow probe removal.

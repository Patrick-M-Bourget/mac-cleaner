# Refresh preserves choices — issue #10

Refresh begins with immutable selected identities and their last valid observations. Review and execution pause immediately. A complete, newer observation revalidates the original exact file and original scope/Downloads/volume authority, size and modification timestamp. Unchanged survivors remain selected; newly discovered files and hardlink aliases stay unchecked. Changed or missing targets lose actionable membership with a visible explanation. Cancellation, inaccessible scopes and incomplete coverage retain affected choices as **Refresh required**.

## Implementation and safety

`RefreshChoices` owns per-scope generation and pending state. `RefreshValidator` serializes blocking metadata validation on an actor, using one observation index rather than per-target task fan-out. Native `SessionPlan.canReview` combines pending state, preparation and executor readiness. Beginning or completing refresh invalidates any prior confirmation. Older tasks cannot publish into a newer inspection context; cancellation also guards the saved scope report. Pending files can be deselected without being resurrected by completion. Rechecking an ancestor retains the original narrower scope authority.

The plan provides direct **Recheck location** actions and a fixed-footer **Stop refresh** action. Existing shared design components, white light sidebar, native controls and stable window contract are retained. Search, inspected identity and list scroll identity stay in view state while retained observations remain visible. No automatic rescans, content reads, downloads or filesystem mutations are introduced.

## Verification

Approved public seams were exercised using owned disposable folders only. Twelve refresh tests cover survivors/new unchecked discoveries, same-size modification and removal, cancellation/incomplete and cached observations, out-of-order completions, deselection, independent scopes/access loss, prior approval invalidation, pending cleanup, Downloads identity replacement, ancestor authority retention and selected-child identity replacement. The last case failed before adding comparison of frozen canonical scope/resource/volume evidence, then passed.

After merging executor #9 and scanner progress #34, the full StillCore suite passed **70/70** on local Xcode 27.1. Native build-for-testing succeeded. The focused native journey selects through the actual folder picker, preserves search/selection, cancels a bounded scan, explicitly rechecks, observes unchanged readiness and changed-target explanation, verifies new files stay unchecked and compares outer window bounds. It reads back only its own three-byte fixture to verify contents are unchanged.

Final merged native journey passed **1/1 in 57.7 seconds**. Result bundle: `.build/refresh-merged-ui.xcresult`; run log: `/tmp/still-refresh-merged-ui.log`. Its four XCTest window attachments were exported without editing into [required light](../visual/refresh/required-light.png), [required dark](../visual/refresh/required-dark.png), [changed light](../visual/refresh/changed-light.png) and [changed dark](../visual/refresh/changed-dark.png). Captures use real disposable selected-folder metadata on the merged executor/progress build. Earlier pre-executor intermediate captures were replaced.

## Limits

No personal folders were inspected. Native TCC revocation, real mounted-volume loss and exact VoiceOver focus restoration remain manual OS integration checks; controlled access-loss results and stale-generation behavior are covered at the public scanner/refresh seams. Search and outer bounds are asserted in XCTest; arbitrary long-list scroll restoration and assistive-technology focus are not claimed as automated qualification. Filesystem metadata cannot prove that same-size data with deliberately restored timestamps is unchanged; execution still performs its independent final identity/policy checks. This ticket adds no execution retry or recovery workflow.

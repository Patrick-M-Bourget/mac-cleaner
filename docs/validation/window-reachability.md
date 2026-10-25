# Initial window and confirmation reachability — #38

October 22, 2026. Follow-up to the local [design-system validation](design-system.md). The original local passing journeys did not qualify the hosted display geometry.

## Reproduced evidence

Hosted Xcode 26.6 CI at `72be4a2` failed three native journeys. The downloaded recording for `testDesignReviewCaptures` reports **1024 × 768 pixels** with `ffprobe`. Its accessibility snapshot reports an app window at `{{0,31},{1120,677}}` and Appearance at `{{1005,38},{94,38}}`: the control's right edge is 1099, beyond the recorded display. This establishes the offscreen-control cause without changing display preferences or guessing a new runner resolution.

The bulk journey's event log identifies **Choose items** when the test intended to expand the confirmation's exact-file list. The underlying page disclosure is covered by the sheet; selecting the first app-wide disclosure was ambiguous.

## Bounded change

`NativeWindowContract` fits the initial/restored frame to the current screen's visible frame once at attachment, preserving feasible minimum dimensions and keeping the origin inside that frame. Explicit Debug capture size requests pass through the same fitting rule. Navigation, selection, disclosures, theme changes and sheets do not invoke resizing.

Debug `--design-constrained-screen` supplies a smaller available-frame boundary (up to 1024 × 720) for the native regression; it never changes macOS preferences or the real display. The confirmation journey now locates the sheet containing **Review Move to Trash** and expands that sheet's disclosure, rather than the underlying page's **Choose items** control.

The shared white light-sidebar policy, dark material, selection state and approval semantics are unchanged.

## Verification

The new public native journey failed before the implementation: the requested 1120-point window exceeded the controlled 1024-point boundary. It checks feasible bounds, reachable Appearance, route/appearance changes and stable outer geometry. The tight command runs only `WorkspaceUITests/testInitialReviewWindowFitsConstrainedDisplayAndKeepsToolbarReachable`.

Local Debug build and **4/4 native journeys passed** in 84.3 seconds: the new constrained-display journey, bulk mixed/Cancel/focus/approval, fixture design capture, and populated native design capture/confirmation/settings. The bulk journey verifies sheet disclosure hit testing and unchanged exact selection. No broad package rerun was needed for this presentation-only change.

Local verification uses Xcode 27.1. Hosted Xcode 26.6 must rerun CI to establish that environment's result; local success is not a claim of hosted success. No screenshots were repainted, OS display preferences changed, or personal files inspected.

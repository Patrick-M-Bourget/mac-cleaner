# Shell and appearance source reviews — #53

Final source `c5886e8`, baseline `43668a8`. Independent Standards and Spec reviews have no remaining actionable findings. The chronological reports below preserve failed hypotheses; actual final normal-click3/3 and original-capture acceptance supersede pending wording. [Qualification](shell-appearance.md) records source/run boundaries.

## Standards

# #53 final incremental standards review

Comparison `43668a8...2795902`, carrying prior service/app/footer standards reviews forward and inspecting the added hunks since `ba355dd` independently.

No additional actionable documented-standard or Fowler heuristic findings. A single NSApplication appearance owner now governs live content and auxiliary panels; removing the competing live preferredColorScheme override keeps reset-to-Automatic consistent with the locked contract. The isolated developer Gallery retains its own explicit preview appearance. Shared picker labelsHidden and stable accessibility identifier preserve full selection-value space and public test identity. The notice keeps the approved bounded 24-point reserved region; native bordered styling and zIndex do not change persistence/navigation authority. Gallery's initially collapsed synthetic shell group bounds its addition without duplicating components or altering product gates.

Public tests still observe actual preference evidence, frame/context anchors and native controls at approved seams. The known live Retry saving mouse-delivery failure is still under diagnosis; source review and inert Gallery captures do not establish that zIndex fixes it. No new unrelated refactor, internal test bypass, speculative abstraction or actionable Fowler smell found. Applied AGENTS, DESIGN-SYSTEM, SHELL-APPEARANCE, TDD and the full code-review baseline. No repository edits.

## Retry activation and launch diagnostics increment

Comparison `2795902...ba0ce9a`: no additional actionable standards findings. The net product delta sets Retry saving’s native accessibility activation point to its center, keeping the action inside the actual bordered button rather than changing its persistence semantics or adding an alternate test-only action. Temporary probes are absent from the final product diff. Public tests retain ordinary click, persisted-choice and relaunch assertions; this is not a keyboard or coordinate workaround in the test.

History launch diagnostics preserve the original launch requirement: any optional Show Still attempt records diagnostic evidence and then unconditionally fails the missing-initial-window path. It cannot convert a failed launch into green. Screenshot/hierarchy attachments remain scoped to the existing disposable native test process. Native results remain pending at this review point, so no claim is made that the source correction has passed qualification. No repository edits.

## Native recovery-control candidate

Comparison `ba0ce9a...267cd7e`: no additional actionable standards findings. The shared notice now composes a private native NSButton bridge with ordinary target/action and intrinsic sizing. The coordinator updates its closure when SwiftUI updates the representable; the native button owns its accessible label and event region. It keeps the existing Retry saving title, bounded 24-point row and controller persistence callback. Removing ineffective zIndex/SwiftUI activation modifiers avoids layering redundant workarounds. The design system explicitly permits native AppKit bridges, and keeping this single-purpose bridge beside its owning shared notice does not warrant an additional abstraction.

Strict public click/persist/relaunch tests are unchanged. Candidate native flows/regressions/Gallery are still running at this review point; neither actual mouse success nor final visual fit is inferred from the source. No repository edits.

## Native current-bounds accessibility activation

Comparison `267cd7e...2456cdd`: no additional actionable standards findings. The native button subclass overrides only its accessibility activation point, deriving the current bounds midpoint and converting through its actual window into screen coordinates. It retains superclass behavior before window attachment and recomputes the point after moves rather than caching stale geometry. Ordinary NSButton target/action, title, intrinsic sizing and persistence callback remain unchanged. This narrow override does not constitute Refused Bequest: the button retains its native behavior and specializes the documented accessibility seam responsible for its observed bad hit point.

The final net diff contains no diagnostic probes, launch flags, test coordinate workaround or weakened click assertion. Strict default-click qualification is restored. New final native flows remain pending at review time; causal probe evidence supports the correction but is not itself a passing final journey. No repository edits.

## Truthful native accessibility frame candidate

Comparison `2456cdd...a3b425d`: no additional actionable standards findings. The ineffective activation-point override is removed. AccessibleButton instead reports its actual current native bounds converted through the current window to screen coordinates, falling back to superclass behavior before attachment. This corrects the reported accessible region without widening physical hit targets, altering layout, caching coordinates, changing persistence or weakening the ordinary public click test. The specialized NSButton continues to retain its inherited native semantics; no actionable smell is introduced by this small accessibility correction.

The prior activation candidate did not pass strict native qualification. The new strict run is pending at this review point; this review grants no acceptance or mouse-success claim. No repository edits.

## Final hosted accessibility-structure correction

Comparison `a3b425d...c5886e8`: no additional actionable standards findings. The parent HStack no longer receives accessibilityHidden(false); only the potentially blank message Text receives its own hidden state. Retry is already conditionally absent when no failure exists, so its native accessibility ownership no longer inherits the whole-row modifier. This narrows metadata ownership without changing layout, callback, store policy or public tests. The actual-bounds native frame getter remains accurate and had demonstrably applied in the earlier candidate; it must not be described as ignored.

New evidence supersedes the provisional diagnosis: hosted run `40098938199` passed all three strict default-click flows at `c5886e8`, with no centered-coordinate test correction. The one-variable parent-to-message accessibility change resolves the previously failing hosted composition in that qualified scope. The local minimal harness did not reproduce that composition and is a bounded negative experiment, not evidence against the actual hosted red-to-green. Keep the now-qualified combination; no further speculative simplification is warranted before integration. No repository edits.


## Spec

# #53 final Spec source review

Reviewed43668a8...ba0ce9a (root current at review), carrying forward earlier service/app reviews against authoritative SHELL-APPEARANCE.md. Known native Retry activation correction remains pending runtime qualification and is excluded from a completion claim. No edits.

**No new actionable source findings.** Prior false checking detail is corrected to “These checks do not scan folders,” without claiming a global scan state. Typed alert attention validates present metadata and preserves read/write/submission blockers; details distinguish paused decisions from polling and retain snooze/quit/login boundaries. Footer entry clears secondary navigation directly while suppressing configure/sample/request side effects. Gate-off builds remain informational on-demand.

Process-owned appearance uses one NSApplication owner for native chrome and content; the competing workspace preferredColorScheme override is removed. The labelled native picker exposes its selected value, and source review matches the separately reviewed final Reset captures: appearance-clear failure retainsDark, later-service failure after successful clear appliesAutomatic, completeReset appliesAutomatic. Existing journal/execution guards remain before appearance clearing; Clear preserves appearance. Partial Reset copy stays stage-specific. Badge counts actionable eligible categories only, hides at zero with reserved geometry and accessibility wording; toolbar execution→scan→destination precedence remains intact. No filesystem authority, auto-selection/scan, notification cadence or background lifecycle change is introduced.

## Focused missing-window diagnostic result

Run40096673703 atba0ce9a passes both unchanged History journeys: initial47.335seconds and minimum41.672seconds. Full native log contains no history-launch missing-window, post-ShowStill or missing-history diagnostic attachment names. The optional recovery branch did not supply a passing path: missing launch still unconditionally fails, and the original No completed runs assertion remains. No product fix was made for the earlier missing-window regression.

This rules out an invariably broken focused History launch at that source; it does NOT establish the cause of40094532205 or reproduce its capacity→History ordering. Keep the failed broader run disclosed and require final same-order regression after the Retry correction. Current pending native appearance/footer/regression work, real OS authorization/delivery, all-window/dialog behavior, VoiceOver/localization and supported OS/CPU/full-suite certification remain separate gates. Gallery presentation is inert, not service/OS proof; future milestones and M8 deferral remain preserved.

## Native Retry final increment —267cd7e

Reviewedba0ce9a..267cd7e. The final notice uses a shared live/Gallery NSButton target/action bridge with native intrinsic size and accessibility label; coordinator callback updates with SwiftUI changes. Its sole action remains retrySaving, so it cannot alter session choice, navigation, scans, recovery or other preferences. Prior experimental zIndex and accessibility activation-point override are removed. No actionable source finding in this bounded correction. The observed failure cause (ordinary click ignored; edge delivery to neighboring NSClipView) supports a native-control activation correction rather than changing persistence policy. Final flows40096952080, same-order16-regression40096954114 and Gallery verification remain pending; source review does not replace their actual click/keyboard/layout evidence. NSApplication appearance ownership is unchanged from the passing focused History source.

## Native activation-point correction —2456cdd

Reviewed267cd7e..2456cdd app increment: ActivationButton overrides the native accessibility activation point using current bounds center converted through the containing window into screen coordinates, with superclass fallback before window attachment. This follows control movement/resizing rather than storing stale coordinates. Native button target/action, intrinsic size, label and persistence-only callback are unchanged. No actionable Spec finding or authority expansion.

Positive physical probe40097534795 established that the default edge activation missed while an actual center event reached mouseDown/action, dismissed the notice and storedDark; its original strict test remained failing and is diagnostic evidence only. Final probes/flags/custom test coordinates are removed; the unchanged strict public click/persist/dialog/Quit-relaunch journey must pass at the final source. That final native result remains pending, and earlier16-regression progress does not certify this later activation change. No all-platform/VoiceOver claim is inferred from the override.

## Actual native accessibility frame —a3b425d

Reviewed2456cdd..a3b425d. The ineffective activation-point override is removed and AccessibleButton instead reports its actual current bounds converted into window/screen coordinates, retaining superclass fallback before attachment. No source-level Spec issue found: this describes the native control's real hit region rather than inventing a hidden action target, changes no visual/layout/persistence logic and follows later movement. Source and public test callbacks remain unchanged.

The prior center override did not satisfy strict run40097907948; it is not accepted evidence. Measured actual bounds x779/width89 versus expanded AX x778/width91 explain why a default max-minus-one event could fall on the excluded actual boundary. The new truthful frame predicts an interior event, but final strict40098317083 is pending and must demonstrate the unchanged click/persist/dialog/Quit-relaunch flow. No accessibility or platform universality is claimed from the geometry correction alone.

## Notice accessibility containment —c5886e8

Revieweda3b425d..c5886e8: accessibilityHidden(notice == nil) moves from the whole reserved HStack onto its blank/message Text. Retry button is already structurally absent without saveFailed, so no unavailable action is newly exposed. With a failure, the real native button remains accessible without an enclosing visibility modifier; reserved24-point layout, status/message identity, persistence callback and native bounds reporting remain unchanged. No actionable Spec finding in this increment.

Earlier frame correction alone did not resolve ordinary edge activation. This containment change is another bounded hypothesis; strict final native journeys are still running and no fix is proven by source review. Preserve all earlier failing evidence and unchanged strict public assertions until actual green.

## Actual final strict qualification —c5886e8

Native40098938199 passes unchanged ordinary default-click persistence/dialog/Quit-relaunch at both sizes (26.729/20.780seconds) and badge journey48.387seconds. No final custom coordinate assertion or probe path supplies acceptance. All10final originals were individually reviewed with no remaining blockers; see shell53-final-flows-visual-review.md. The parent-hidden-to-message-only change is the last causal variable in this bounded comparison, not a universal accessibility explanation. Earlier16-regression267cd7e669.742seconds and these later final flows are combined scoped evidence; broad OS/accessibility/full-suite limits remain preserved.

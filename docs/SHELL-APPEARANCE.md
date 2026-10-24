# Shell and appearance — #53 locked contract

User-confirmed October 24, 2026, Q1–Q13 and consolidated confirmation. Parity N05–N07/A04. Implemented at application source `c5886e8`, with [bounded qualification](validation/shell-appearance.md) and independent source reviews. This extends the existing connected flow and capacity contracts without reopening them.

## Live selection badge

Cleanup plan's sidebar badge counts categories containing currently actionable selected eligible files, not files. Downloads with one or twenty selected files is one category. Hide at zero. Suspended, stale, blocked and consumed approvals do not count; restored eligible choices update immediately without automatic selection. Exact files/sizes remain in Plan. Accessible name includes “Cleanup plan, 1 category selected” with correct pluralization. Reserve space without moving the label or changing window geometry. No persistence of cleanup selections across Quit.

## Appearance preference

Automatic/Light/Dark is process-owned and shared across all Still windows, saved across close/reopen and Quit. Automatic follows macOS. Apply immediately without layout animation, window resizing, navigation/selection/scroll/focus loss or scan interruption. Apply consistently to dialogs and secondary windows. Missing preference uses Automatic quietly; invalid or unreadable preference falls back to Automatic with a quiet explanation and no automatic repair or unrelated data reset.

A failed write retains the chosen appearance for this session. A compact persistent message near the appearance control explains that it could not be saved; Retry saving retries persistence only. A successful later choice/retry clears the message. No focus stealing. Use bounded reserved status/action space, preserving full native labels and keyboard access.

Clear completed history preserves appearance. Confirmed Reset local app data clears the appearance preference independently: once clearing succeeds, all windows switch to Automatic even if a later reset step fails. If clearing appearance fails, retain the current choice and report that failure. Do not claim blanket success after partial Reset. Existing unresolved-recovery/execution guards remain authoritative; no new Reset bypass.

## Toolbar context

Priority: active cleanup execution, then existing active scan status, then actual destination/secondary-page context. Preserve existing progress/Stop/return-to-scan controls and navigation behavior. A selected or remembered scope must never label editable Plan or History as read-only. Ordinary copy:

| Destination | Context |
|---|---|
| Overview | On-demand storage review |
| Cleanup plan | Choose files, then review |
| Explorer | Read-only storage inspection |
| History | Recorded cleanup activity |
| Locations & access | Scan locations and access |
| Storage alerts | Capacity checks only |

Results, Recovery, Local records, diagnostics and gated tool pages retain their own accurate context. Consequences remain beside relevant actions. Synthetic fixture disclosures remain explicit in Debug/Gallery, not misleading live claims.

## Monitoring footer

Use one compact reserved text-and-symbol row, not a taller status stack. Known blocking/unavailable/read-write/delivery failure takes priority: Alerts need attention. Otherwise initial verification: Checking alerts…; valid snooze: Alerts snoozed; verified effective monitoring with no known blocker: Storage alerts on. Explicitly disabled alerts: On-demand scanning. Monitoring intent alone is never sufficient for “on”. Unapplied threshold edits do not change effective state; applied threshold and real monitoring evidence do. A paused capacity decision is attention even when the poller remains active. Keep underlying monitoring/notification policies unchanged.

Checking/on/snoozed/attention footer is a native keyboard-accessible action opening Storage alerts directly, with no setting change, notification request, automatic scan, implicit retry or permission prompt. Details explain actual blocker(s), snooze time and effective state. Ordinary on-demand footer is informational. Non-enabled builds retain on-demand footer and existing feature gates. Never imply continuous folder scanning, operation after Quit, or launch-at-login; login behavior remains separately explained. Do not add background timers or keepalive.

## Shared design and verification

Reuse grouped sidebar, white Light/near-black Dark surfaces, shared tokens/components and same live/Gallery status controls. Text plus symbols; color alone carries no meaning. Preserve minimum900×640 and initial requested1120×760 (actual host clamp recorded), exact stable outer bounds, selection/scroll anchors and reachable actions across states/themes. Avoid tall footer regression fixed in #49. Maintain all approved filesystem/confirmation/recovery flows.

User explicitly approved the additional public appearance-preference service seam with disposable settings and controlled read/write failures. Existing approved public app journeys cover selection/navigation/status, appearance, Reset and geometry. Use vertical red→green; source reviews and individually reviewed original native Light/Dark initial/minimum captures before integration. Gallery proves presentation only; controlled OS settings do not certify real permissions, background delivery, every macOS appearance/VoiceOver configuration or supported-platform coverage. M8 remains deferred.

## Decision trace

Q1 badge categories; Q2 saved app-wide appearance; Q3 destination context; Q4 truthful monitoring states; Q5 direct status route; Q6 Reset/Clear and session fallback; Q7 actionable badge authority; Q8 monitoring priority; Q9 invalid/unreadable fallback; Q10 toolbar precedence/copy; Q11 non-disruptive save retry; Q12 partial Reset truth; Q13 gating and background limits. All accepted; consolidated lock explicitly confirmed. The contract is implemented within the source-bound checks and limits in the qualification report.

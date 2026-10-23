# Alert monitoring orchestration

The production monitoring controller now lives in the StorageAlerts package. The native app supplies only OS operations through `AlertMonitoringSystem`: notification authorization/submission, startup capacity, time, persisted episode state and the 15-minute tolerant timer. `StorageAlertsController` retains native notification actions and delegate presentation. Views, labels, threshold semantics and future-milestone gating are unchanged.

This implements the existing M5 contracts in SPEC.md and the Storage alerts handoff: re-enabling must resume authorized capacity monitoring, unavailable effective monitoring must not leave an alert-only poller, and explicit Quit stops monitoring while preserving preference/login intent.

## Reproduced failures and fixes

Public `AlertMonitoringController` actions and observable monitoring state are exercised with controlled system operations; the tests never request real notifications, alter login registration or scan files.

- Start monitoring, hold an activation's authorization response, disable and re-enable. Previously the old process-wide sampling flag discarded the new sample; requested alerts remained on without effective monitoring or a timer until another activation. Sampling now belongs to its monitoring generation. The new generation starts exactly one poller; late denied authorization from the old generation cannot stop it. Capacity is sampled for the renewed enable, and the same low episode remains suppressed without another notification.
- A newly observed startup capacity smaller than the configured threshold previously marked monitoring ineffective but retained its poller. The invalid-threshold path now cancels polling while retaining the saved preference and existing actionable status.
- Stopping for termination during held authorization previously allowed its completion to restart polling. Termination now invalidates the monitoring generation before cancellation. It preserves the saved enabled preference and independent login intent.

Each regression was observed failing against the extracted existing behavior before its fix. Tests assert public effective state, actual controlled pollers/capacity observations and notification outcomes, rather than private generation flags. Existing durable episode, reservation and delivery-gate tests remain intact.

## Verification and limits

On the local arm64 macOS/Xcode development host, all 24 StorageAlerts package tests pass. The native Debug app compiles with the same production controller source. This is focused feature verification, not a full native suite or real notification/service-management qualification. No visible presentation changed, so no new visual acceptance is claimed. Real authorization UI, native notifications, window-close/menu-bar interactions and login approval still require disposable OS qualification; commercialization signing remains separate M8 work.

Independent review reproduced a fourth issue newly reachable through renewed sampling: an old held submission completed after disable/re-enable, genuine recovery and acceptance of a fresh low episode. Fixed-identifier stale cleanup erased the fresh pending request while its episode remained suppressed. The public regression first failed with an empty pending-request model. Every submission now receives an immutable identifier; stale completion removes only its own identifier. Opt-out/reset cancel captured in-flight and last-accepted identifiers, including the previous-version fixed `Still.lowSpace` identifier. The fresh episode's notification survives the obsolete completion and is not replayed at the next check. Tracking is bounded to in-flight attempts plus the last accepted request; no asynchronous broad enumeration or global prefix removal is used.

System acceptance is still distinct from display. Pending-request cancellation does not recall already delivered banners; genuine OS delivery remains a disposable qualification task.

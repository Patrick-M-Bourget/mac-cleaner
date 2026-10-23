# Alert monitoring orchestration

The production monitoring controller now lives in the StorageAlerts package. The native app supplies only OS operations through `AlertMonitoringSystem`: notification authorization/submission, startup capacity, time, persisted episode state and the 15-minute tolerant timer. `StorageAlertsController` retains native notification actions and delegate presentation. Views, labels, threshold semantics and future-milestone gating are unchanged.

This implements the existing M5 contracts in SPEC.md §§9–10 and the Storage alerts handoff: re-enabling must resume authorized capacity monitoring, unavailable effective monitoring must not leave an alert-only poller, and explicit Quit stops monitoring while preserving preference/login intent.

## Reproduced failures and fixes

Public `AlertMonitoringController` actions and observable monitoring state are exercised with controlled system operations; the tests never request real notifications, alter login registration or scan files.

- Start monitoring, hold an activation's authorization response, disable and re-enable. Previously the old process-wide sampling flag discarded the new sample; requested alerts remained on without effective monitoring or a timer until another activation. Sampling now belongs to its monitoring generation. The new generation starts exactly one poller; late denied authorization from the old generation cannot stop it. Capacity is sampled for the renewed enable, and the same low episode remains suppressed without another notification.
- A newly observed startup capacity smaller than the configured threshold previously marked monitoring ineffective but retained its poller. The invalid-threshold path now cancels polling while retaining the saved preference and existing actionable status.
- Stopping for termination during held authorization previously allowed its completion to restart polling. Termination now invalidates the monitoring generation before cancellation. It preserves the saved enabled preference and independent login intent.

Each regression was observed failing against the extracted existing behavior before its fix. Tests assert public effective state, actual controlled pollers/capacity observations and notification outcomes, rather than private generation flags. Existing durable episode, reservation and delivery-gate tests remain intact.

## Verification and limits

On the local arm64 macOS/Xcode development host, all 23 StorageAlerts package tests pass. The native Debug app compiles with the same production controller source. This is focused feature verification, not a full native suite or real notification/service-management qualification. No visible presentation changed, so no new visual acceptance is claimed. Real authorization UI, native notifications, window-close/menu-bar interactions and login approval still require disposable OS qualification; commercialization signing remains separate M8 work.

A possible overlap between a stale notification submission and a newer request sharing the fixed notification identifier has not been reproduced or changed in this slice. Existing reservation/delivery protections remain; this report does not certify that separate overlap.

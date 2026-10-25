# #27 final Spec review

Reviewed clean HEAD `336fcb99b1381f03f8ff0e34c3c62c900d668495` against fixed point `65a836c`, the locked GitHub #27 body and `docs/STORAGE-ALERTS.md` Q1–Q7.

No actionable source/spec findings.

- Shared display capacity uses the process-owned observable controller. The only Refresh action calls `capacity.request(.manual)`; it cannot enter the separate alert policy sampler. The monitoring timestamp remains independently sourced.
- Permission is separately shown; the OS request remains exclusively on explicit enablement with unknown permission. Activation reads permission without prompting, denied permission stops polling, and authorization generations reject superseded responses. Settings launch does not claim recovery.
- The applied threshold is distinct from the draft. Explicit Apply requires changed, valid input against current shared total; unavailable/refreshing capacity prevents applying. Enablement uses the applied preference, so pending edits cannot silently become active. Saved values survive unknown totals.
- Shared pure threshold, permission and quiet-explanation surfaces are reused in the inert Gallery. No test-send/preview feature or monitoring-policy, login, snooze, lifecycle or navigation expansion was introduced.
- Spec, handoff, design system and parity overlay consistently preserve M5 and the separate #28/#29 acceptance. Contract Q7 requires “Genuine macOS authorization/delivery evidence”; current documents correctly say qualification pending. Controlled native fixtures cannot close that gate.

This is source review, not native visual qualification or real macOS notification delivery certification. Final evidence/status documentation must retain the genuine OS acceptance item open unless separately satisfied.

# M8 — Commercialization

Approved October 23, 2026. [Ticket #40](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/40) preserves distribution work moved out of the feature-building critical path.

## Retained work

- Approve release versions, included feature set and actual supported OS/CPU matrix.
- Developer ID signing, secure timestamps, final Hardened Runtime and entitlement review.
- Correct the release-preflight timestamp and malformed-entitlement gaps; agree its public CLI test boundary when this milestone resumes, then add focused disposable fixtures. The earlier question is deferred and does not block feature development.
- Final archive privacy/dependency review, export, notarization, stapling and Gatekeeper assessment.
- Clean-account quarantined/offline installation, signed manual update and uninstall; no debug artifacts or orphaned registrations.
- Record final artifact/archive hashes, signing/notary results, lifecycle evidence and known limitations.

## Development boundary

Feature work and its required safety/platform checks continue using local builds and normal ad-hoc test signing. Do not request distribution credentials, run notarization or spend feature cycles on release-preflight corrections unless commercialization is explicitly prioritized. An individual native integration may still require identity/permission qualification; document that specific requirement. This decision does not enable unvalidated cleanup adapters or remove data-safety checks.

M7 retains functional/platform/accessibility hardening. #35 records that evidence; #40 consumes it for commercialization. No feature ticket should depend on #40. Existing unsigned archive and development-preflight results remain preparation evidence, not signed distribution qualification. The retained procedures and historical observations are in [release qualification](validation/release-qualification.md).

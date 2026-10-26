# #18 close-and-clean Standards review

Reviewed `4b738f3...d069c517f264ede5bf8106c95e404d1de9230eba` read-only. Sources: root AGENTS.md, docs/README.md, docs/MILESTONES.md, docs/DESIGN-SYSTEM.md, docs/agents/{domain,issue-tracker,triage-labels}. No tests executed.

**No blocking standards findings.** No hard documented requirement violation identified.

Repository authority says “Keep mutation capability behind a small, reviewable executor interface” (docs/README.md); this qualification-only CLI keeps descriptor-relative no-follow traversal and deletion localized. It neither introduces a production adapter nor relaxes the personal-file executor. M3 explicitly requires “supported versions/roots, owner inactivity, races and recovery semantics” (MILESTONES.md); the probe records its actual artifact provenance, guards hosted execution, rejects observed activity, and labels the remaining final-unlink race rather than claiming an exclusive lease.

Process and filesystem review: subprocess calls use argument arrays; shell variables are quoted; extracted Stable must carry the Google bundle identity and designated vendor signature; extraction does not invoke installer scripts. Directory-chain identities, ownership and write-access checks precede bounded cache-leaf removal; symlinks, unknown shapes, hardlinked leaves and changed directories refuse the operation. Errors cause nonzero exit, and the helper reports stopped/partial counts when deletion has begun. Artifacts contain synthetic profile facts, hashes and official provisioning metadata, not browsing contents from a personal profile. Disposable-root disposal remains the hosted runner’s responsibility.

DESIGN-SYSTEM requires changed native screens to reuse components and undergo Light/Dark review; no screen or production UI changed here, so additional Gallery/capture work is inapplicable.

Fowler heuristics were considered as judgement, not invented repository mandates. Existing monolithic disposable harness structure and compact Python style do not justify an architectural refactor for this small experiment. Duplicated Stable/CfT startup assertions are modest and preserve distinct qualification conditions; no speculative abstraction is requested.

Limits: this is a source/standards review, not native qualification or proof of semantic preservation. Existing declared credentials/autofill/history/session and platform qualification gaps must remain visible in the final capability decision.

## Narrow follow-up — protected semantics

Read-only review of `66e1f83..58b0fdf`, limited to genuine.mjs fixture additions; no tests run. **No new blocking standards findings.** Same repository authority and judgement criteria apply.

The added authentication cookie, service worker, offline shell, navigation history and restored-tab probes stay inside the generated loopback origin and disposable profile root. Credentials are random synthetic tokens; persisted evidence records booleans/counts rather than token values. No preferences/database edits, personal profile discovery or installed-browser access were introduced. CDP calls retain the existing 15-second timeout; navigation/readiness loops have explicit iteration bounds, and offline emulation resets in `finally`. Failed mandatory assertions remain fatal; restored-tab/history unavailability is recorded separately instead of being silently promoted to a passing preservation claim.

No new architectural abstraction is warranted for these experiment fixtures. The report still explicitly states “No saved password/autofill or download-history UI qualification”; synthetic HttpOnly authentication is correctly distinct from saved-password qualification. Native execution evidence must determine which semantic assertions actually pass, and cannot convert the partial report into production permission.

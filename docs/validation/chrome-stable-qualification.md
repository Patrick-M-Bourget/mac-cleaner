# Chrome Stable qualification #18 — bounded blocker decision

October25,2026. Locked [CHROME-CLEANUP](../CHROME-CLEANUP.md) Q1–Q6. This pass completed the first remaining prerequisite investigation; it did not complete #18 or qualify a Stable build.

## Result

No supported external exclusive coordination guarantee was established. [Pinned macOS source and exact residual race](chrome-stable-qualification/ownership.md) show why Chrome's singleton and internal backend tracker do not supply an external cleaner lease. The existing disposable helper checks an entry, then separately unlinks its name; a replacement or in-place modification after the final check remains outside the approved manifest guarantee. Descriptor-relative/no-follow traversal does not make this pair identity-conditional or prevent browser reopen.

Under Q6's explicit stop rule, do not repeat the prior closed-owned-process CfT cache test or download Stable merely to obtain another regeneration result. No production code, test, workflow, native screen or positive allowlist changed. No new test pass, native permission, browser launch, personal profile inspection or Stable compatibility is claimed. No screenshots are required for this documentation-only decision.

## Additional completed research

[Stable distribution/provenance](chrome-stable-qualification/stable-provenance.md) distinguishes official moving consumer Stable downloads from versioned CfT binaries. Future hosted qualification must pin the actual observed artifact/version/signature and contemporaneous release metadata; a matching CfT version number does not certify Stable. The transient release lookup is recorded only as research, not a supported version.

## Remaining work and resume condition

#18 remains open; #19 remains blocked by #18; production allowlist remains empty. Need a supported maintenance API or externally enforceable cooperative ownership/isolation design that preserves exact approved targets across browser/helper reopen and final removal. Absence of such a mechanism in this research is not a proof that every possible design is impossible. A different action/scope contract requires separate explicit product approval; this pass does not weaken the lock or add a guidance-only substitute.

Once a concrete mechanism is established, qualify one genuine Stable release/profile layout in a disposable hosted environment, followed by the remaining protected credential/autofill/history/download/session/offline semantics, actual denial, swaps, shared ownership and unsupported layouts. Existing CfT evidence remains useful but bounded in [chrome-owned-profiles](chrome-owned-profiles.md). M3/M8 and all other milestones remain unchanged.

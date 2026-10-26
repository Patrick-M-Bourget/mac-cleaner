# Standards review — Xcode capability #16

Reviewed frozen `15a0cb2...56c157b` (commits `3b4f918`, `7f426df`, `56c157b`) without edits, builds or personal-data inspection.

**No actionable documented-standard violations found.**

- **Authority and scope:** AGENTS.md and docs/README.md require the consolidated product contract and milestone gates. The change stays in reusable Core capability, disposable qualification and its ledger; no #17 app controls, new navigation or unsupported native permission claim are introduced. docs/XCODE-CLEANUP.md and docs/validation/xcode-intermediates.md explicitly retain the pending qualification gate.
- **Test seam:** The TDD skill requires public behavior at approved seams, rather than private helpers. New tests import StillCore publicly, exercise observation/inspection/approval/execution/records, and inject controlled native process snapshots or owned disposable files. They do not assert private implementation. Native qualification uses the same public module and preserves source/run attribution; failed historical workflows remain labelled failed.
- **Module design:** The codebase-design skill favors deep modules and locality. XcodeIntermediates encapsulates opaque session/generation-bound approval, descriptor mutation and journal outcomes. Mapping and native owner observation are separately concentrated; callers do not reconstruct filesystem authority. Adapter-specific isolation from Chrome is appropriate because the frozen exact-file contract differs from cache-group cleanup.
- **Validation discipline:** docs/DEVELOPMENT.md pins hosted Xcode26.6 and distinguishes local builds, public fixtures and genuine native evidence. The workflow pins that toolchain; the report does not equate the 192 Core checks/app build with successful native qualification. Run40335032639 remains pending at this review boundary.

**Baseline heuristics:** No material naming, duplication, feature-envy, data-clump, speculative-generality or scattered-change issue warrants a repair in this bounded diff. Similar no-follow/identity patterns are safety-specific adapter implementations, not sufficient reason to introduce a cross-adapter abstraction. Existing broader tooling and native/manual platform gates are outside this standards review.

This is a source standards review, not capability certification or an approval to close #16/unblock #17.

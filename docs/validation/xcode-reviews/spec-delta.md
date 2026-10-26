# #16 Spec delta review

Reviewed `git diff 56c157b...f937636` against locked `docs/XCODE-CLEANUP.md` Q1–Q7 and the qualification ledger. No edits or tests performed.

No actionable source/spec findings.

The production delta is bounded to installation identification: Apple anchor/identifier, strict native-executable validation and authenticated secured Info.plist/CDHash replace expensive full resource traversal and the previously unauthenticated product-version resource. The observed signed bundle build24959/CDHash are pinned separately from the17F113 product label. The ledger explicitly limits this guarantee rather than implying validation of every compiler/SDK resource.

Frozen target identities, local/no-follow object checks, standard project mapping, owner checks, protected artifact exclusions, changed-leaf skips, scope/owner safety stops and durable execution semantics are unchanged. Qualification diagnostics remain worker-only; no #17 app action or new product scope is enabled.

The earlier60-second action timeout is retained as uncertain, without claiming zero mutations or successful preservation/recovery. The follow-up retains journals and captured output on timeout and adds diagnostics around the same public environment calls. This addresses evidence loss without weakening the executor contract or treating a larger timeout as qualification.

Q1 states “proceed to #17’s app journey only after the capability gate passes.” The changed installation gate still requires actual source-bound Core action, preservation and interruption/reload/replay evidence. The ledger correctly keeps #16 open and #17 blocked pending that run; local tests and the no-project timing diagnostic do not satisfy the native capability gate.

## Spec review — 734d7d7 versus 91c4cf5

Reviewed #18/#19 current acceptance and CHROME-CLEANUP.md rules 5–7 against the frozen six-file qualification diff. No production adapter, allowlist, app flow, or ordinary personal-file executor changes are introduced. No blocking scope/protection defect found.

- **P2 — Preserve native fault evidence on failure (native-faults.py:76).** Rule 7 requires concrete failures to be reported, and the evidence contract requires native observations and negative results to remain distinguishable. The structured report is written only after all fault cases and teardown assertions pass. A later native reopen/helper/teardown failure therefore drops already-observed index-swap/access-denial results and the failing case from the uploaded JSON artifact. Save incrementally and in a failure/finally path, with the concrete failure and completed checks, then rethrow; do not convert a failure to success. The workflow log remains evidence, but is less precise than the intended source-bound report.

- **P3 — Correct the headed probe’s preservation description (headed.mjs:1).** “No password DB, preference or Keychain changes” conflicts with normal UI Add/Save, which deliberately asks Chrome to persist synthetic credentials/address state. Rule 7 requires honest evidence limits. Say no *direct* database/preference/Keychain manipulation; do not imply saving creates no storage changes.

Qualification limits, not implementation defects: standard-profile.py explicitly establishes mapping only (`cleanupExercised: false`); it does not establish split-root removal/relaunch semantics. The new probes must be run successfully before recording their gates as passed. Managed/shared/overridden layouts and broader OS/CPU coverage remain unsupported/future, rather than a renewed exclusive-lease prerequisite. Existing documented #18-open/#19-blocked status is accurate at this source.


## Narrow follow-up — standard-proof authority, source 657c12c

Reviewed commits 1ce89f0 and 657c12c against preceding 87d7676, limited to cache-group.py, standard-profile.py and public negative tests. No blocking scope/provenance issue found within the approved normal qualification threat model.

The new mode requires actual hosted Darwin execution, same-run/source trusted proof, initially absent default roots, exact browser-reported Default profile, canonical exact standard cache scope, unchanged root/group device/inode/owner identities, same-run runner-contained vendor provision, executable digest and strict Google signature. Process fixtures cannot authorize standard mode. Default custom-root constraints remain intact; no production adapter or personal-file executor changes occur. Existing activity/no-follow/revalidation/partial-stop behavior applies after proof validation.

The standard probe snapshots browser-created protected profile data around removal, requires positive removal, asset re-request and regenerated asset-pattern entries after relaunch. The pre-existing mapping-only limitation is superseded only if this new native run passes; source inspection is not that pass. Managed/shared/overridden layouts remain outside support. The proof is trusted experiment output, not cryptographic authority against adversarial same-user tampering, consistent with the approved residual-race contract.

Local observation: both public standard-proof negative test methods pass on the current Mac. No genuine browser was launched locally. Previous P3 header finding is resolved in later source; P2 native-fault report retention should be assessed against its later incremental-report fix, outside this narrow diff.


## Narrow follow-up — saved-address semantics, fa8192d versus 8f610f7

No blocking spec mismatch found in this bounded change. CHROME-CLEANUP rules 3 and 7 require preservation of protected autofill data/semantics; #18 acceptance says autofill sentinels remain unchanged. They do not require every synthetic webpage suggestion interaction to succeed. Normal Chrome Add/Save followed by an exact five-field normal Edit-dialog read before cleanup and again after actual cleanup/relaunch establishes a meaningful saved-address record preservation boundary if the native run passes. Exact Web Data SHA-256 equality immediately around removal supports that observation without substituting an empty database or directly seeded record. UI reads occur before Cancel, so the second observation does not repair the saved fields. Password fill and download-history/file assertions remain independent and strict.

This is deliberately narrower than successful address form filling. The original pre-clean suggestion preview/commit failures must remain failures, with no claim that this run repairs, certifies or universally supports website autofill. The source explicitly records that limitation and renames checks to savedAddressRecordBefore/AfterCleanup. The prior source’s absence of committed pre-clean fill does not itself demonstrate cleanup-related data loss because cleanup had not happened.

Before closing #18, the native evidence must show positive asset-cache removal, genuine relaunch, exact before/after records, unchanged around-cleanup Web Data bytes and the independent password/download checks; this review cannot certify pending run40259148625. Docs and issue status should describe “saved-address record preservation through normal settings UI,” not “address form fill passed.” No new production capability, personal-file authority or global settings change is introduced. No browser was launched during this source review.

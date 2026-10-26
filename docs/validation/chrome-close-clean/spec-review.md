# Spec review — Chrome close-and-clean qualification

Reviewed frozen d069c517f264ede5bf8106c95e404d1de9230eba against 4b738f3. Read-only source review; no tests run. Native results pending.

**No blocking source findings for this partial qualification slice.** No production allowlist, UI, personal-file executor or prior exact-file helper changed.

Contract rule 5 permits “eligible entries generated inside that same approved group.” cache-group.py:51–53 approves directory identities; :57–71 enumerates current permitted leaves. test_cache_group.py:5–16 genuinely inserts a later leaf after approval and verifies both deletion and a protected sibling. Replacement/symlink cases :17–30 exercise refusal without deleting the prior cache.

Rule 6 requires “stop unstarted work and report partial outcomes.” cache-group.py:74–87 observes processes and revalidates path/ancestor and index-directory identities before each removal; :89–91 records removed count and failure. No-follow traversal, same-user checks, link-count checks and bounded leaf enumeration are present. These are bounded safeguards, not race elimination; the residual final-unlink race is stated explicitly.

Rule 7 requires disposable environments and actual Stable provenance. provision-stable.py:7–10 guards hosted arm64/fresh RUNNER_TEMP destination; :16–25 records Google HTTPS artifact/hash; :26 extracts rather than installs; :31–42 verifies bundle ID and strict vendor signature including team requirement. genuine.mjs:12–34 checks hosted execution, exact extracted bundle/hash/version. The native helper uses actual process output only on hosted runners. Local tests use an explicit owned fixture.

**Qualification limitations to preserve in final evidence:** This adds only two controlled tests: later-leaf/protected-sibling and replaced-directory/symlink. There is no controlled partial-deletion, index-directory swap, malformed/denied process observation or real access-denial qualification here. genuine.mjs:189/198 tests active/reopened state before removal, not a reopen during deletion. Its custom, headless profiles with mock keychain (:99) do not qualify standard-root discovery, real credentials/autofill or session/tab semantics. Report limitations (:74) correctly retain these gates. closeOwned (:130–140) can terminate its own disposable process group; record that this is fixture teardown, not evidence of production graceful-close behavior. Keep #18 open/#19 blocked and allowlist empty until the explicitly remaining acceptance is satisfied.

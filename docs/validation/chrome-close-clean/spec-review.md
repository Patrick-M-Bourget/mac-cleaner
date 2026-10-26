# Spec review — Chrome close-and-clean qualification

Reviewed frozen d069c517f264ede5bf8106c95e404d1de9230eba against 4b738f3. Read-only source review; no tests run. Native results pending.

**No blocking source findings for this partial qualification slice.** No production allowlist, UI, personal-file executor or prior exact-file helper changed.

Contract rule 5 permits “eligible entries generated inside that same approved group.” cache-group.py:51–53 approves directory identities; :57–71 enumerates current permitted leaves. test_cache_group.py:5–16 genuinely inserts a later leaf after approval and verifies both deletion and a protected sibling. Replacement/symlink cases :17–30 exercise refusal without deleting the prior cache.

Rule 6 requires “stop unstarted work and report partial outcomes.” cache-group.py:74–87 observes processes and revalidates path/ancestor and index-directory identities before each removal; :89–91 records removed count and failure. No-follow traversal, same-user checks, link-count checks and bounded leaf enumeration are present. These are bounded safeguards, not race elimination; the residual final-unlink race is stated explicitly.

Rule 7 requires disposable environments and actual Stable provenance. provision-stable.py:7–10 guards hosted arm64/fresh RUNNER_TEMP destination; :16–25 records Google HTTPS artifact/hash; :26 extracts rather than installs; :31–42 verifies bundle ID and strict vendor signature including team requirement. genuine.mjs:12–34 checks hosted execution, exact extracted bundle/hash/version. The native helper uses actual process output only on hosted runners. Local tests use an explicit owned fixture.

**Qualification limitations to preserve in final evidence:** This adds only two controlled tests: later-leaf/protected-sibling and replaced-directory/symlink. There is no controlled partial-deletion, index-directory swap, malformed/denied process observation or real access-denial qualification here. genuine.mjs:189/198 tests active/reopened state before removal, not a reopen during deletion. Its custom, headless profiles with mock keychain (:99) do not qualify standard-root discovery, real credentials/autofill or session/tab semantics. Report limitations (:74) correctly retain these gates. closeOwned (:130–140) can terminate its own disposable process group; record that this is fixture teardown, not evidence of production graceful-close behavior. Keep #18 open/#19 blocked and allowlist empty until the explicitly remaining acceptance is satisfied.

## Protected semantic follow-up review

Reviewed 66e1f83..58b0fdf (frozen follow-up 58b0fdf), read-only/no tests. **No blocking source findings.** Native execution remains pending and source inspection is not a positive qualification result.

The restored-session path observes preexisting targets before creating the new inspection tab (genuine.mjs:131–155). It does not manufacture the expected history-b/session-second tabs or history-a traversal after reopening. The earlier real Page.navigate calls (:255–260) create pre-cleanup history; Page.getNavigationHistory and Page.navigateToHistoryEntry test the restored tab's persisted back stack. An unavailable restoration is explicitly reported rather than asserted as passed. This is bounded history/back-stack evidence, not browser history UI or all session fidelity.

Synthetic authentication is actually server-set HttpOnly (:62–65); the pre-cleanup check verifies document.cookie cannot see it (:228). Post-cleanup /account succeeds without another /login (:276), so authentication is not reconstructed. This qualifies a synthetic website login session only; saved-password/keychain semantics remain explicitly unsupported.

Offline shell is populated by the pre-cleanup service-worker installation (:72–77/:229), with no later registration/cache.put. After relaunch the test requires persisted service-worker control, disables page networking, navigates to /offline-app, checks the token-bearing shell and unchanged server request count (:279–289). This is genuine bounded offline navigation from an already online-controlled page, as the limitations state; it does not claim offline browser startup or all service-worker behavior.

Report fields carry booleans, counts, fixed fixture filenames and restoration observations. They do not serialize random authentication/local-storage tokens, cookie headers, response bodies or credentials. Assertion diagnostics can contain synthetic fixture tokens if an equality fails; no personal data is involved, and no successful evidence report includes these tokens.

Keep actual native outcomes distinct from source capability; retain saved-password/autofill, download-history UI, custom-root/standard-discovery, broader compatibility and remaining negative-case gates. No production allowlist/UI/personal-file protections change.

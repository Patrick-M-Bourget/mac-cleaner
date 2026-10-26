# Chrome native close-and-clean — bounded Stable evidence

October25,2026 (native job UTC October26). Contract: revised [CHROME-CLEANUP](../CHROME-CLEANUP.md) rules5–7. Native/helper source `d069c517f264ede5bf8106c95e404d1de9230eba`; controlled follow-up `66e1f83` adds an observation sequence/partial-stop test, with `dd12044` fixing workflow routing. Real process/removal behavior is unchanged. This advances #18; it does not close #18, unblock #19 or enable a production allowlist.

## Genuine Stable result

[Chrome job40254902201](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40254902201/job/121354556185) passed every step in88 seconds on macOS26.6.2 arm64, Node22.23.4. Overall workflow was canceled only after the successful Chrome job/artifact upload, to stop an accidentally routed unrelated native job. Never describe the entire workflow as green; subsequent routing-only fix excludes that job.

- Actual Google Chrome Stable156.0.8078.48, `com.google.Chrome`, Google team `EQHXZ8M8AV`. Strict bundle/executable/framework verification passed; main bundle uses Apple anchor/Google identity requirement. Executable hash and deep/strict bundle signature also verified after the experiment. Official moving package extracted with pkgutil into runner temp; no installer/scripts/updater setup, re-signing, quarantine removal or policy workaround. The package is a268,364,334-byte observed artifact with SHA256 `53edc513a6706607e77ae781f476368f6098421e000e2e586033a597c1c49651`; executable SHA256 `4f71e9dbe725fec1110977b6a6dd0708fb32fbde9c905b4b461cef880ac08288`.
- Two explicit custom profiles, Default and Profile1, sequentially: real process observations refuse active and reopened browsers before removal. After closing the owned browser, five genuine downloaded-asset leaves per profile were removed and five regenerated after a cache-miss request.
- Generated Cookies, History, Login Data, Web Data and Preferences bytes were unchanged immediately around removal. Cookie, localStorage, IndexedDB and CacheStorage response values survived genuine relaunch. Actual512KiB downloaded file survived. This is not saved-password/autofill, history traversal, download-history UI or complete offline-app semantic qualification.
- [Original provision](chrome-close-clean/provision.json) and [original report](chrome-close-clean/report.json) retain exact source, signatures, versions and observed limits. No personal browser/profile or account was accessed. Mitigation flags do not establish absence of all outbound traffic.

## Public disposable boundaries

First missing-public-helper red, then green. Final local checks: three group methods plus two unchanged exact-leaf methods pass. A later eligible leaf inside the approved group is included while a protected sibling stays unchanged. Replaced group and symlink are refused. A controlled process sequence closed → closed → helper-running causes exactly one removal then a stopped result, preserving the remaining target. That last case was first red, then green at66e1f83; it is controlled between-work evidence, not a native Chrome-reopen-during-deletion result.

Real process enumeration is hosted-only; local tests use an explicit owned process-observation fixture. Group approval pins root/ancestor identities and ownership; no-follow directory traversal and index-directory identity checks reject observed scope conflicts. Only recognized candidate simple-cache leaves are enumerated, never arbitrary directories recursively. Personal-file production executors and the earlier exact-leaf helper are unchanged.

[Spec](chrome-close-clean/spec-review.md) and [Standards](chrome-close-clean/standards-review.md) source reviews found no blockers for this bounded slice. Root separately reviewed the final fixture-only sequence and routing changes. No native app screen changed; no new screenshot, app-build, whole-suite or real-user qualification is claimed.

## Remaining acceptance and supported scope

Still unqualified: native between-work reopen/partial stop; index-directory swap and actual access denial; standard-root mapping, shared/ambiguous ownership and enterprise/helper association; saved-password/autofill persistence, download-history UI and cold-start offline-app launch. Final27c1db6 now establishes bounded restored tabs/history traversal, authenticated website-session preservation and online-initiated service-worker offline navigation as recorded below. Headless/mock-keychain/custom-root evidence does not certify real Keychain, headed standard-profile behavior, minimum OS or Intel. Additional OS/CPU and unsupported cache groups are retained future scope, not an excuse to demand an exclusive lease for this model.

Production support remains disabled pending the remaining accepted capability requirements. No #19 UI/executor or generic plan refactor is included. Prototype browser/profile → shared plan → permanent confirmation/results remains the design target.

The accepted residual boundary is ordinary-use best-effort detection: process observations before and between targets are not a lease, and descriptor-relative checks do not eliminate every final-name-operation race. Do not claim adversarial same-user protection. Owned process-group termination in experiment teardown is limited to that disposable group; it does not qualify graceful production browser shutdown or authorize force-quit. The earlier exclusive-lease finding is historical to the stronger superseded model, not a blocker reintroduced here.

## Final protected-semantic qualification —27c1db6

[Final focused workflow40255923214](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40255923214) fully succeeds; Chrome job121357620359 completes in56 seconds. Actual Stable156.0.8078.48 artifact/executable hashes match the first recorded pass, with untouched vendor signatures before/after. Both owned custom profiles pass:

- A synthetic HttpOnly-authenticated website session works after genuine relaunch without another login; this is not saved-password-manager/Keychain qualification.
- A previously installed service worker serves the offline shell after fresh-process relaunch, with CDP network disabled, correct synthetic content and no additional shell request to the fixture server. Initial target setup uses an online-controlled page; cold-start offline launch is not qualified.
- Both genuinely created tabs restore (2/2) before the harness creates inspection targets. An existing persisted history stack actually navigates back. No preferences, browser database seeding or replacement tabs manufacture restoration.
- Existing protected-file/site-state checks and actual downloaded-file survival pass again. Download-history UI, saved passwords and autofill remain unqualified.

[Final original report](chrome-close-clean/27c1db6/report.json), [provenance](chrome-close-clean/27c1db6/provision.json) and [semantic note](chrome-close-clean/semantic-note.md) retain exact facts. Earlier58b0fdf [report](chrome-close-clean/58b0fdf/report.json) is preserved: auth/offline/back traversal passed but only1/2 tabs were observed. It lacked a pre-close second-tab navigation-complete wait. The nine-line27c1db6 correction waits for actual completion; final2/2 does not retroactively alter the earlier observation or establish that it was data loss. No restore flag or browser preference changed to obtain the result.

Both review axes accepted the semantic fixture diff; root separately reviewed the narrow pre-close completion correction. This is the final genuine source for this slice. Three controlled group methods plus two unchanged exact-leaf methods retain their prior pass; this is not a new whole-app suite. #18 remains open for the specific remaining required native/profile/semantic acceptance above; additional OS/CPU and unsupported groups stay future scope. #19 remains blocked, positive production allowlist empty, personal-file exact-target policy unchanged.

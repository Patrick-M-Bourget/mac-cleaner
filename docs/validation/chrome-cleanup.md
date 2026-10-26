# Chrome cleanup #19 — qualified delivery

The bounded #19 feature is implemented and qualified for integration through [PR72](https://github.com/Patrick-M-Bourget/mac-cleaner/pull/72). The approved journey is Overview → browser/profile review → shared Cleanup plan → consequence-specific confirmation → separate outcomes/History. Final app presentation is `ceec55f`. Its production cache adapter is identical to the full successful `23e2219` genuine Chrome qualification: `git diff 23e2219..HEAD` is empty for ChromeCache.swift, ChromeCacheExecution.swift and ChromeCacheJournal.swift.

This is one qualified Chrome adapter, not completion of all M3 or M8. Downloads retain their exact-target approval, identity checks and Trash executor. No personal Chrome/profile/account was inspected during qualification.

## Compatibility and genuine Swift proof

[Workflow40264317079](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40264317079), source `23e2219`, fully succeeds in its bounded Swift qualification lane. Fourteen public Chrome Core fixture checks pass. The genuine browser experiments invoke the actual production Swift service rather than the earlier Python mutation helper. Unchanged originals: [provision](chrome-cleanup/23e2219/provision.json), [two-profile report](chrome-cleanup/23e2219/report.json), [headed report](chrome-cleanup/23e2219/headed.json).

Qualified artifact: regular vendor-signed Google Chrome Stable **156.0.8078.48**, `com.google.Chrome`, Google team `EQHXZ8M8AV`; macOS **26.6.2**, arm64. Executable SHA256: `4f71e9dbe725fec1110977b6a6dd0708fb32fbde9c905b4b461cef880ac08288`. Observed official PKG SHA256: `53edc513a6706607e77ae781f476368f6098421e000e2e586033a597c1c49651`. Bundle/executable/framework signature verification and post-run verification pass. JSON OS25.6.0 is the Darwin kernel version, not the product version.

Both owned custom profiles, Default and Profile 1, refuse active/reopened Chrome, remove5 genuine downloaded-asset cache leaves each, and regenerate cleared assets after relaunch. Checked Cookies, History, Login Data, Web Data and Preferences bytes remain unchanged immediately around closed-cache removal. Real downloaded files, authenticated HttpOnly website sessions, service-worker offline navigation, persisted back-history and2/2 restored tabs survive. Headless password storage is not treated as real Keychain qualification.

The separate headed fixture uses normal Chrome Add/Save/Edit UI without mock Keychain or an automation flag. Swift removes6 cache leaves; the saved username/password fills after relaunch, the exact saved-address record remains in normal Edit fields, Web Data bytes stay identical, and download-history UI/file contents survive. Universal website address-suggestion acceptance remains unqualified; saved-record retention is the proven boundary.

These actual Swift deletion runs use explicit owned **custom roots**. Earlier [#18 standard split-root removal/regrowth and native fault evidence](chrome-close-clean.md) remains independently source-bound Python-helper evidence; it is not relabelled as standard-root Swift deletion. Public Swift disposable fixtures cover ownership, changed-root refusals, cancellation, durable records and protected sentinels under explicit owned custom roots. Unknown/shared/managed/redirected layouts remain unavailable.

## App journeys and visual qualification

| Source and workflow | Actual bounded result |
|---|---|
| `fe83162`, [40265139115](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40265139115) |8 individual UI methods pass: initial/minimum mixed cleanup, rescan/new profiles, unavailable/empty states, partial Clear, precise Reset, and initial/minimum existing Downloads journeys. Overall workflow **fails** the two test-query problems and separate live-helper refusal described below. |
| `802ad2d`, [40265922104](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40265922104) |1/1 shared-gallery method passes, both themes and sizes. |
| `345d723`, [40266115536](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40266115536) |3/3 final presentation methods pass: Chrome-only and initial/minimum mixed cleanup, including selection, Cancel/focus restoration, permanent confirmation, actual cache removal and protected sentinels. |
| `ff5d928`, [40266203098](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40266203098) |1/1 Stop regression passes: stopping Downloads preserves the unstarted Chrome leaf and records cancellation/zero removals. |
| `ceec55f`, [40266856314](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40266856314) |1/1 final Chrome-only method passes at both sizes, including correct toolbar results context and no phantom Trash success. |

The composed scoped runs cover **11 distinct public UI methods**. This is not a claim of one final whole-suite run. Later result/header/context changes preserve Downloads-only defaults and do not change its approval/executor. Local app/test-target builds pass through final presentation.

[47 selected original PNGs](../visual/chrome-cleanup/manifest.json) were inspected individually in Light/Dark at hosted initial1024×640 and minimum900×640. The [per-set visual review](../visual/chrome-cleanup/REVIEW.md) records source mapping and viewport limits. Mixed lower captures show Chrome heading/profile/status while counts and permanence paragraphs remain below the captured viewport. Complete Chrome-only captures visually qualify the identical shared ChromeResultsSection. We do not infer offscreen layout, zero counts or broad accessibility support from clipped images.

## Review corrections and recovery

Independent Standards/Spec reviews at baseline77da877 → frozen8118f25 found mixed-stage cancellation, completed-history retention and partial-maintenance feedback gaps. Focused followups through final app/source changes find those resolved and no new actionable personal-file or scope regression.

- The original Stop regression genuinely fails at `0333a59`/[40263915306](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40263915306): stopping Downloads still removes the future Chrome leaf. `c91b78b` carries one latched cancellation request from before capacity sampling through both stages; Quit invokes the same boundary. Final Stop green is recorded above. Completed work is not rolled back.
- Partial Clear/Reset regressions genuinely fail at `23e2219`/[40264318932](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40264318932), after reaching their intended actions. `e8e94ab` preserves committed per-store counts and distinguishes Chrome inspection-preference failure from appearance/remaining-preference failure. Their final individual UI methods pass atfe83162.
- Completed Chrome history expires after90days, with a20,000,000-byte component bound inside the existing250,000,000-byte combined completed-cleanup payload allowance. Lifecycle maintenance coordinates the stores; unknown Chrome storage makes Trash history maintenance read-only. Unresolved records never expire, survive Clear, block Reset/replay and are never automatically resumed. The hard Chrome archive bound can refuse new writes rather than discard recovery facts.
- Shared SelectionSummary defaults to “Selected for Trash” for Downloads only and uses “Selected for cleanup” whenever Chrome is included. Grouped results have one shared heading; Chrome-only outcomes do not claim files were moved to Trash. Removed bytes and separately sampled capacity remain distinct.

## Preserved negative and diagnostic evidence

The first UI/gallery problems were test/integration defects, not successful qualification: duplicate category accessibility identifiers, label-versus-value lookups and XCTest’s128-character string-lookup limit. Corrections retain the original Downloads identity and read actual native text values. The old workflows remain failed; the later scoped greens are reported separately.

Repeated native runs sometimes correctly refuse a remaining live Crashpad helper. Fixture-only teardown now proves a newly created helper’s UID, executable inside the verified bundle, start identity and exact owned Crashpad database before a bounded natural wait or scoped SIGTERM. A source-pinned `BREAKPAD_DUMP_LOCATION` override contains only the spawned disposable fixture’s crash database. It does not change production Chrome settings, grant authority over a default/personal profile, kill unknown processes or exempt helpers from the app’s guard.

The [f40723c repeat report](chrome-cleanup/f40723c/report.json) proves Default cleanup/protected-state checks and exact fixture-helper containment, then stops **before Profile 1 cleanup** on unidentified-current-user process evidence. The overall workflow fails; the app’s failclosed Unknown behavior is not a preservation failure or a reason to weaken activity checks. There is no automatic cleanup retry.

A proposed exited-process false-positive hypothesis was tested in [40267931766](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40267931766), source `f8cdbd9`. The actual public Native environment call passes while an owned child is exited but unreaped. macOS returns no BSD information for that entry and the adapter correctly skips it. The hypothesis is **not reproduced**. [Diagnostic assessment and original log](chrome-native-process.md) preserve the setup failure, corrected observation and limits. Normal Core CI skips this explicitly opted-in hosted diagnostic. **No production process policy changed.** The successful23e2219 qualification therefore covers the exact current production adapter.

## Practical limits

Chrome and its relevant helpers must be closed. If a live helper persists after normal Quit, or process/ownership/access evidence remains uncertain, cleanup stays unavailable and the user can recheck explicitly; Still does not terminate a browser or helper. Qualified no-follow/process checks are safeguards, not an exclusive external lease or atomic snapshot. Ordinary-use residual reopen/write/final-name-operation races remain explicitly accepted for this cache-group model only.

No broader browser/version/OS/CPU, GPU/code-cache, shared/managed/redirected layout, provider, native permission/bookmark, universal autofill, comprehensive localization/accessibility, signing/notarization or commercial-release qualification is claimed. Site/offline data, cookies, credentials, history, downloads and tab/session state remain protected. All future milestones and M8 deferral remain preserved.

# Safari asset-cache capability investigation

Issue #20 · 2026-10-22 · M3. **No supported direct-mutation configuration is established.** Browser-native guidance is the capability result for every OS/Safari version. The feature remains in the roadmap; this report does not silently replace the asset-only contract with broad website-data deletion.

## Observed environment and evidence boundary

Read only Safari's application-bundle version metadata: Safari 27.0.1. `sw_vers` reported macOS 27.0.1, build 26A434. Compiled and ran fixtures with Xcode 27.1 via process-local `DEVELOPER_DIR`. No personal Safari profile, history, cookie, password, session, cache or downloaded file was read or mutated. No privacy permission was requested or changed.

The four Swift Testing cases validate the public capability decision and protected disposable sentinels. They **do not** validate native Safari storage mappings, actual TCC authorization, helper ownership, or real cache mutation. Synthetic access and owner signals cannot certify those facts. There are no claimed supported native configurations; therefore there is no falsely inferred successful permission/coordination test.

## Reproduce

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Validation/SafariProbe
```

All four tests pass. Red→green: denied access initially returned an executable profile and failed three assertions; fail-closed results fixed that. A second case failed until even claimed access/profile/inactivity provided explicit unvalidated-mapping and ownership reasons. An owner-active/unknown case failed until its actionable writing-risk explanation was returned. Temporary protected fixtures remain byte-identical after capability assessment. That sentinel test validates refusal without side effects, not a functioning deletion adapter.

## Profile/shared decision

Apple documents separate profile history, cookies and website data, while several other settings/data categories are shared. This does not establish an asset-cache file-to-profile mapping or prove that a filesystem cache directory contains only regenerable assets. The result label is **Safari cache boundary unknown**. Do not assign all cache bytes to Personal, invent per-profile totals, or equate unknown with shared. An eventual validated shared group must be counted once and explain every affected profile; an unknown group has no selectable targets or zero-byte claim.

No filesystem root, layout identifier, Safari build or OS combination is allowlisted for mutation. Directory names from third-party cleaners are hypotheses, not evidence. Do not enumerate guessed private paths to fabricate a mapping. WKWebsiteDataStore documentation concerns data associated with a WKWebView configuration; it is not evidence of authorization to manage Safari's separate browser profiles.

## Access and owner policy

Treat read access as independent from cleanup safety. Denied/unknown access means unavailable coverage, never an empty cache. Apple's Privacy & Security guide describes Safari among data protected by Full Disk Access; actual access depends on the signed app/context and requires separate native tests. Full Disk Access remains optional and cannot turn an unsupported mapping into supported cleanup. Do not request broader access merely to unlock a capability that still cannot execute.

A closed Safari window is not ownership coordination. Future validation must account for Safari, Safari Networking/WebContent and other relevant helpers, profile sharing, container services and new writers starting after observation. A process-name list or user assertion that Safari is closed is insufficient exclusive ownership evidence. Never force-quit, signal helpers, remove locks or run privileged commands. Active/unknown owners explicitly receive guidance; even a claimed inactive signal currently remains unsupported.

## Protected data and executor contract for #21

Protect cookies, credentials/passwords, autofill, history, tabs, sessions, bookmarks/Reading List, offline content, local storage, IndexedDB, service workers and downloads. The disposable sentinel tree includes these categories under synthetic Profile/Shared paths, with binary bytes checked unchanged. These are synthetic categories, not real Safari path claims.

The app should show unsupported status and browser-native guidance, expose no selection or permanent-cleanup approval for Safari, and reject a forged/stale Safari action at executor entry. A future adapter must establish:

1. Explicit OS/Safari build + rule-version allowlists from disposable native profiles, including default/multiple profiles and real profile/shared boundaries.
2. Proven asset-only membership excluding protected/offline data, measured read coverage and truthful unknown sizes.
3. Identity/scope/volume and symlink-ancestry evidence, exact target materialization, one shared plan, and fresh owner/access/layout checks.
4. Reviewed no-follow mutation with target-swap/concurrent-write fixtures, changed-target skips, permanent-deletion consequences and no scope widening.
5. Durable intent/outcome journals, cancellation stopping unstarted work and interrupted-operation reconciliation without automatic replay.

Until those gates pass, any Safari action remains guidance-only. A byte-identical protected fixture pass cannot compensate for unknown native semantics.

## Browser-native guidance and consequences

Apple documents Safari > Settings > Privacy > Manage Website Data. This operates on website data and can sign users out or change behavior, including effects in other apps. Present it as a broader browser-owned management option with that consequence; never label it an equivalent asset-only cleanup or invoke it automatically. Do not automate Settings with Accessibility or Apple Events. Users remain in control of Safari's own final approval.

## Primary sources checked

- [Apple: use Safari profiles](https://support.apple.com/en-us/105100): profile separation, shared settings, and profile-deletion consequences. UI separation is not a documented cache-path mapping.
- [Apple: clear Safari cache and cookies](https://support.apple.com/guide/safari/manage-cookies-sfri11471/mac): native management route and broader website-data consequences.
- [Apple: Privacy & Security settings](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac): Safari data appears in Full Disk Access coverage. No actual permission grant was exercised here.
- [Apple: WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore): web-view datastore API. Inferring Safari profile cleanup authority from it would exceed the documented scope.

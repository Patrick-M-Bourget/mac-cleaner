# Release qualification preparation — #35

Status: **not qualified; do not distribute this development artifact**. Prepared October23,2026 from5e849e8. This document records evidence and actionable gates, not an OS support promise. #14 personal validation and outstanding #34 performance qualification remain blockers. Each subsequent integration changes the candidate and must be recorded before release.

## Candidate feature boundary

The proposed first candidate is M1: explicit user-selected folder inventory, coverage/unknown accounting, local iCloud information/guidance, explicit Quick Look/Reveal, Downloads exact-file session selection, bulk/refinement, consequence confirmation, native Trash, cancellation/partial results, fresh explicitly approved retry and durable startup recovery. Completed-history/reset work must pass #13 before inclusion. No personal cleanup has been authorized by release preparation.

M2–M6 remain conditional development routes behind `--future-milestones`; their presence in source does not qualify them for distribution. Cloud eviction, Xcode/browser/tool-cache mutation and Docker mutation are not enabled by this ticket. No release may advertise an adapter without its separate capability/version gates. Do not run qualification with the future flag and describe it as M1 evidence.

## Actual environment and evidence

| Observation | Evidence / limit |
|---|---|
| Local native host | macOS27.0.1 build26A434, arm64; Xcode27.1 build27A9275 selected per-command through DEVELOPER_DIR |
| Minimum deployment setting |14.0; **not** proof of macOS14 runtime compatibility |
| Intel/universal | No Intel runtime exercised; no Intel/universal support claim |
| CI | native.yml requests macos-26/Xcode26.6; attach candidate's actual successful run/artifact rather than treating configuration as execution evidence |
| #11 integration |87 core tests, native build-for-testing, focused initial/minimum cancellation/retry journeys passed; [qualification](cancel-retry.md) |
| #34 | Owned50k/100k measurements/progress evidence in [scanner performance](scanner-performance.md); million-entry/reference-host and remaining fixture gates are incomplete |
| Appearance/geometry | Existing [design-system](../DESIGN-SYSTEM.md), [visual evidence](../visual/README.md), and per-ticket captures; screenshot review does not certify VoiceOver or every preference/display |
| Signing availability | `security find-identity -v -p codesigning` returned0 valid identities; no credentials requested/imported |
| Current artifact | Development/ad-hoc or signing-disabled builds are explicitly rejected by preflight; neither is a Developer ID release |
| Release metadata | Project currently has no approved marketing/build version; preflight rejects absent identifiers |

## Required-reason API audit

Primary authority: [Apple API categories/reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), checked October23,2026. This is a source-purpose audit, not an Apple approval statement. Final archive must contain the bundled manifest and undergo Xcode's archive privacy report/dependency audit. [Platform applicability research](privacy-required-reason-research.md) supersedes the earlier blanket C617.1 release blocker: current Apple documentation does not establish required-reason declarations as a native macOS Developer ID/notarization prerequisite. The preflight's purpose checks enforce the repository's chosen inventory, rather than proving Apple's distribution requirements.

| Actual use | Declaration |
|---|---|
| Selected-folder timestamps/stat metadata for inventory, fresh identity checks and exact mutation | FileTimestamp3B52.1; access originates in explicit selection |
| App-owned local journal/baseline/state metadata validation | C617.1 eligibility is not established for unsandboxed Application Support, and no such declaration was added. This is not an established macOS distribution blocker; see the platform applicability research. Recheck channel, data practices and dependencies for the final candidate. |
| Display startup/selected-volume capacities and observed changes locally | DiskSpace85F4.1 |
| Scanner progress cadence / tool timeout elapsed intervals via systemUptime | SystemBootTime35F9.1 |
| App-only login preference via UserDefaults.standard | UserDefaultsCA92.1 |

No tracking or collected-data declarations are added. No derived metadata is uploaded. Future alert behavior and diagnostics export require purpose review before their inclusion; do not infer permission to transmit from the display reason. Source grep is an audit aid, not a complete transitive-framework API detector. Apple documents the app-container reason; this preparation deliberately leaves the unsandboxed Application Support interpretation unresolved instead of adding an unsupported declaration.

## Read-only artifact preflight

Run from repository root using the intended final exported `.app`:

```sh
python3 tools/release/preflight.py /absolute/path/Still.app > /absolute/path/preflight.json
```

Exit0 means only the executable checks passed. `releaseQualified` remainsfalse until the manual evidence gates are signed off. Exit1 records failed checks; exit2 records an invalid input/tool failure. The script never launches, signs, submits, staples, changes trust, registers login, prompts for permission or modifies the app. It checks version identifiers, bundle/executable, absence of debug dylib/test bundles, Developer ID authority, actual Hardened Runtime flag, strict signature integrity, dangerous debug/runtime entitlement exceptions, bundled privacy purposes, architecture, existing stapled ticket and Gatekeeper assessment. It records executable SHA256; retain a SHA256 of the final distribution archive too. It does not inspect every embedded dependency's purpose or certify user workflows.

The current signing-disabled Debug artifact was rejected (exit1) for missing release version, Developer ID/runtime/integrity, privacy additions not yet bundled, missing notary ticket and Gatekeeper failure. Local Release compilation succeeded on this arm64 host with signing disabled; its privacy-purpose checks pass after bundling the additions, while distribution/version/notary checks correctly remain failed. No Release execution or distribution signing occurred.

## Remaining qualification checklist

Record candidate commit, exported archive hash, hardware/OS/build/toolchain, tester, date and linked evidence for every row. Use an isolated account or clean disposable Mac/VM for installation lifecycle; do not erase the user's records or real Trash.

- #13 and #14: finish completed-history/reset and explicitly reviewed personal usefulness walkthrough. Personal mutation requires the user's separate concrete approval. Record actual Trash-held bytes versus independently observed capacity; later recurrence is a manual session.
- #34: finish million-entry and declared reference-host performance/memory/cancellation budgets; use owned fixtures. Record storage/provider/mount boundaries exercised and exclusions.
- Native accessibility: keyboard-only picker→inspect→select→confirmation Cancel/approve→Stop→result→fresh retry; verify focus, Space/Return/Escape, menu shortcuts and recoverable window closure. VoiceOver must announce row selection, mixed category state, consequences, progress and every outcome/recovery action. No screenshot substitutes for this pass.
- Preferences/layout: light/dark, increased contrast, reduced motion/transparency, long filenames and localized/pseudolocalized strings at initial/minimum windows; multi-display restoration and disconnected display. Record actual configurations, not blanket claims from one test.
- Platform matrix: runtime-test each advertised OS/CPU. macOS14 deployment compilation alone does not qualify14, and an arm64 binary alone does not qualify Intel. Start with only actually tested configurations after all remaining gates pass.
- Privacy/security: inspect final archive privacy report, API-purpose coverage, dependencies, Info.plist versions and entitlements. Verify no debug root overrides/debug-only mutation delay exist in Release and no installer/root helper/background registration is introduced.
- Distribution: Developer ID Application certificate, secure timestamp, Hardened Runtime; notarization accepted log and staple validation; Gatekeeper launch of quarantined download in clean account, offline stapled launch, actual selected-folder/Trash behavior and recovery. No credential enters Git/logs.
- Installation/update/uninstall: drag signed app to Applications; launch without registration by default. Quit safely, install next signed version manually over old bundle, relaunch and inspect retained unresolved journal without restoration as approval. Test uninstall after disabling optional login intent, Quit and remove app; confirm no orphaned login/menu helper. Retain local recovery state by default; deletion/reset must use documented guarded product flow. Do not remove OS grants or empty Trash automatically.

## Manual signed distribution outline (not executed)

Choose approved marketing/build versions and distribution identity through Xcode; Archive Release, inspect archive privacy report, export Developer ID distribution, notarize using Xcode's distribution workflow, inspect accepted notary log and staple. A CLI operator may use an already configured Keychain profile with `xcrun notarytool submit --keychain-profile <profile> --wait` against a prepared archive; never place a password or key in this repository. Run `xcrun stapler validate` and the preflight against the final app, then package using `ditto -c -k --keepParent` and record archive SHA256. Revalidate the downloaded packaged artifact on a clean machine; archive creation is not installation evidence.

Apple references: [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Developer ID distribution](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html). No signing/submission was attempted in this preparation.

# Xcode cleanup boundary capability report

Issue #16 · 2026-10-22 · M3 investigation, independent of the M1 personal build.

## Result

**Fixture policy and one bounded genuine owned-project experiment established; production mutation remains guidance-only.** No personal/default DerivedData, user source, archive, dSYM or project was scanned, modified or removed. The later [genuine native experiment](NativeExperiment/README.md) builds its own minimal project and removes one exact owned generated object, separately from the synthetic suite below. The package has no public initializer accepting an external cleanup root: each probe owns a newly created temporary tree. It is a reproducible negative/positive policy experiment, not the app's cleanup adapter.

Toolchain observed: Xcode 27.1 (27A9275), Apple silicon. Selection was process-local using `DEVELOPER_DIR`; the global developer-directory setting was unchanged. Only this toolchain ran these synthetic fixtures; this is not evidence that every Xcode 27.1 on-disk layout is validated. Other versions are guidance-only.

## Reproduce

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Validation/XcodeProbe
```

Six public-boundary tests pass. They cover positive object cleanup, unchanged source/archive/dSYM/application/source-directory sentinels, unknown versions/layouts, symbolic links, active/unknown owners, owners becoming active after review, changed targets, and interruption without automatic continuation. Fixtures are unique per test and removed afterward. Swift Testing reports six tests; the separate XCTest runner reports zero because this package has no XCTest cases.

TDD evidence: the first owner/version test failed against an unrestricted policy and then passed after gating. Positive cleanup exposed a `/var` versus `/private/var` URL alias bug and passed after relative-path handling was corrected. A same-length replacement test failed because textual Date formatting discarded timestamp precision; numerical timestamps fixed it. That test now observes skipped status and retained original content.

## Exact fixture allowlist

The temporary tree models `DerivedData/Probe-*/Build/Intermediates.noindex/**.o`. Only regular leaf object files are candidates. Neither the DerivedData directory nor a project directory is a target. Component matching rejects `Sources`, `SourcePackages`, `.dSYM`, `.xcarchive` and `.app` ancestors even inside the otherwise eligible tree. Products, indexes, logs, compilation/module caches, package checkouts, simulator data, DeviceSupport and every other layout remain untouched. A name/path alone is insufficient evidence for production classification.

Production discovery may inspect the explicitly enabled default root `~/Library/Developer/Xcode/DerivedData`. Custom and relative build roots require separately verified scope and project ownership; never infer eligibility simply because a folder is named DerivedData. Archives are protected independently of location. Whole-project/whole-Build deletion is forbidden because diagnostics or user data can occur below them.

## Executor contract for #17

1. Present supported measured findings read-only until capability validation succeeds. Evidence must include actual Xcode version/build, rule version, authorized root and volume/resource identities, project association, file type, ownership, modification state, allocation semantics and completeness.
2. Materialize exact leaf identities in the shared draft. Final confirmation discloses permanent removal and rebuild/regrowth cost. Source, archive and diagnostic exclusions apply at every ancestor and survive aliases/custom paths. No recursive broad-directory mutation.
3. Establish owner inactivity immediately before approval and execution. At minimum include Xcode, xcodebuild, XCBBuildService and relevant compiler/build helpers. A process-name snapshot cannot prove absence of a new build or identify every custom builder. Failed enumeration, unidentified ownership, active builds or inability to exclude concurrent owners means guidance. Never terminate owners or delete their locks to proceed.
4. Revalidate every approved identity, scope/volume, ancestor symlinks, ownership and modification evidence immediately before mutation. A changed/unavailable target is skipped; new files never join the batch. The fixture compares device/inode/size/creation/modification observations, but this is only a preflight demonstration.
5. Production mutation must use an independently reviewed descriptor-relative, no-follow executor that holds verified parent identities and defines its remaining name-swap/concurrent-writer limitations. Plain `removeItem(at:)` after a path check is not certified race-safe. If isolation/exclusive ownership cannot be established, keep mutation disabled. The fixture deliberately labels its path-based remove as disposable-only.
6. Journal immutable intent durably before each mutation; record individual succeeded/skipped/failed outcomes afterward. Cancellation stops unstarted items; no rollback promise. A crash between unlink and outcome is unresolved and requires reconciliation, never automatic replay. The fixture's consumed run token/stop boundary demonstrates one-process interruption only; durable crash recovery belongs to the application executor.
7. Count estimated allocated release separately from observed volume change; no exact APFS exclusive-space promise. No privilege escalation, root helper, content reading for real scans or shell `rm -rf`.

## Remaining gate

The [genuine native experiment](NativeExperiment/README.md) now establishes one isolated minimal C-project layout, real archive/dSYM protection and exact descriptor-relative owned-object removal/regeneration. Before #17 can enable direct cleanup: extend genuine generated-project evidence to the claimed layouts and project types, establish real Xcode/build-helper ownership coordination, validate adversarial swaps, hard links, permissions and volumes, and integrate durable recovery. A successful synthetic suite does not satisfy these live semantics. The supported user behavior today is inspection and guidance; uncertainty fails closed.

## Primary sources

- [Apple: manage project-generated file locations](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html) documents default DerivedData and Archives roots, generated data, relative/custom/shared build locations. This motivates preserving custom-layout uncertainty rather than broad recursive deletion.
- [Apple: build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference) documents configurable intermediate and product locations; a default directory is not a universal ownership guarantee.
- [Apple: adding identifiable symbol names to a crash report](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report) explains the diagnostic role of symbol information. The product's stricter rule protects every dSYM regardless of perceived reproducibility.
- [Apple: FileManager.removeItem(at:)](https://developer.apple.com/documentation/foundation/filemanager/removeitem(at:)) documents removal, not exclusive build ownership or transactional rollback. Those capabilities are not inferred from the API.

Further #16 progress: [the actual Swift/package/custom-output session](NativeExperiment/SWIFT-SESSION.md) extends native coverage and records a real SIGKILL event boundary. It explicitly leaves general owner/isolation and production action eligibility unsupported; no app mutation authority is added.

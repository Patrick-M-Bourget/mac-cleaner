# Genuine owned Xcode experiment

October23,2026 · #16 evidence for conditional #17 · **Production mutation remains unsupported.**

This is a real C command-line Xcode project/build/archive experiment, distinct from the original synthetic policy suite. The script accepts no external project/root. It creates one private0700 `StillXcodeNative-*` temporary root containing sources, a shared scheme, explicit `DerivedData/Probe-native` and an explicit `Archives/Probe.xcarchive`. Only its owned generated objects are considered. The project has no packages, custom script phases, dependencies, signing account, network install or personal data. Product execution is unnecessary and is not performed.

## Reproduce

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 Validation/XcodeProbe/NativeExperiment/run.py > /tmp/still-xcode-native.json
```

Requires the exact observed Xcode27.1/27A9275, macOS host with available macOS SDK, Python3 and at least512MB free temporary storage. The script pins DEVELOPER_DIR per child process and never changes global selection. It uses explicit project/scheme/configuration/destination/derivedDataPath/archivePath, disables automatic package resolution and signing, limits each build/archive to120seconds and removes only its newly created root afterward. Never adapt it to accept personal roots. Xcode may maintain its ordinary shared build services; the explicit output root is not a sandbox for arbitrary build scripts, which this minimal project deliberately lacks.

## Actual result

Local host macOS27.0.1/26A434, arm64. [Machine-readable observed evidence](evidence.json):

- Real build exited0 in2.404seconds; archive exited0, producing an actual `.xcarchive` and product/archive dSYMs.
- Two generated regular objects appeared under `Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64/{main,helper}.o`, totalling4,120logical bytes. These are actual compiler outputs, not seeded `.o` text fixtures.
- While the owned archive xcodebuild child was active, an attempted action using the two-object manifest returned active/unknown and removed nothing. Completion is observed only for child processes this harness launched.
- After both owned builds returned, the manifest froze device/inode/size/mtime/ctime. A replacement of `main.o` was skipped; unchanged `helper.o` was removed through descriptor-relative no-follow ancestry and fresh leaf checks. A new `.o` created after review remained untouched. No whole folder or broad `Build` deletion occurred.
- Source/project/scheme4files, actual archive6files and product dSYM3files had identical SHA256 before/after the manifest action. Hashes are computed only for owned disposable protected fixtures, never personal code/symbols.
- Another real build exited0 in1.391seconds and regenerated the removed object. Source and archive hashes remained unchanged; normal rebuild may update generated product/symbol outputs independently of cleanup.
- The private experiment root was removed after completion. No user DerivedData, archive, project or other personal root was enumerated or modified. These bytes/times do not estimate user savings or guarantee rebuild duration.

The original six Swift fixture tests still supply policy-only unknown-version/layout, symbolic-link, active/unknown-owner, changed-target and interruption cases. This new experiment does not silently relabel them as native Xcode tests.

## What is and is not established

Established: the exact generated-object layout above on one genuine27.1 minimal C/macOS project, actual symbol/archive placement, own active-child rejection, finite exact-manifest deletion, replacement/new-discovery exclusion, protected artifacts and actual regeneration. It supports an object-leaf rule investigation rather than recursive DerivedData cleanup.

**Not established:** mapping arbitrary user DerivedData to project ownership; default/custom/relative output configurations; Swift/package/plugin/script-generated data; GUI Xcode, shared XCBBuildService, compiler/helper inactivity or exclusion of a new unrelated build; shared/hardlinked artifact handling in genuine projects; additional volumes/permission providers; durable application journal integration. This experiment observes its own child xcodebuild return status, which is not a general owner-inactivity oracle. It does not enumerate/terminate other processes or remove locks.

The descriptor walk is stronger than a path-only remove, but the final fresh-stat→unlink name interval does not atomically bind the expected inode or exclude a new writer. No universal hostile-concurrent-process guarantee is claimed. Fixture root privacy and owned build sequencing delimit this experiment; production must define and validate its actual concurrency/ownership contract. No registration, broad grant or approval bypass was introduced.

## Next frontier

#17 should remain unavailable for personal roots. A bounded next **#16 qualification slice** can generate a Swift/package project with isolated custom intermediate/product paths and establish a documented ownership/session contract for a root the app can genuinely bind. Verify real helper activity/conflicts and late writers using only that owned project, then exercise descriptor mutation plus durable intent/outcome and cancellation with protected symbol/archive/source sentinels. If reliable ownership cannot be established, retain guidance instead of adding an action. Only after that contract passes should #17 gain shared-plan permanent-action UI and production execution; an empty allowlist or this one experiment is not that qualification.

For immediate product implementation, #30 exclusions and #32 reviewed local diagnostics remain independent useful work after their documented dependencies; they do not require pretending an adapter is qualified.

Primary sources checked October23,2026: [Apple build settings](https://developer.apple.com/documentation/xcode/build-settings-reference) describes configurable object/intermediate/product and dSYM locations; [build-setting precedence](https://developer.apple.com/documentation/xcode/configuring-the-build-settings-of-a-target) documents command-line overrides; [debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information) explains dSYM generation/diagnostic importance. Local `xcodebuild -help` confirms explicit derivedDataPath/archivePath. These sources inform boundaries; the actual paths above come from the owned run.

## Swift/package/custom-output follow-up

The [genuine Swift session experiment](SWIFT-SESSION.md) now records custom build settings, local-package compilation, actual owned compiler/build-service descendants, protected native archives/symbols, tracked late-writer refusal and a signal-9 durable-event observation. Production owner coordination remains unsupported; this does not enable #17. Its first custom archive configuration failed and is preserved separately from the successful isolated default archive layout.

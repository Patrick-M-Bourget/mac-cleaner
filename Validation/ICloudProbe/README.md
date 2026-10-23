# Disposable iCloud feasibility probe

Capability decision: **local eviction unsupported / guidance only**. The public metadata available to this probe does not establish Keep Downloaded/pinning policy. No eviction code is included, even when upload and download flags appear healthy. A successful metadata call is not evidence of server durability or safe eviction.

## Run

Requires macOS 14 or later and an installed Swift 6 toolchain. From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Validation/ICloudProbe
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Validation/ICloudProbe icloud-probe --inspect-disposable /explicit/path/StillCloudProbe-unique-id/disposable.txt
```

The caller must create **only synthetic disposable content** under that exact filename and a uniquely named disposable parent. Never point this at existing personal cloud content, shared folders, backups or credentials. The path convention prevents accidental ordinary-file invocation; it cannot certify that supplied content is disposable. No directory traversal is performed. Symlinks and nonregular files are rejected. Placeholder representations that do not expose a regular-file URL remain unsupported.

The command only requests Foundation resource metadata and emits a path-free JSON capability report. It never opens file contents, hashes files, starts downloads, requests credentials or calls a mutation API. Filesystem metadata errors return a nonzero exit status without printing the supplied path. Missing optional values remain unknown. A false transfer-error value means no error was returned in that observation, not that networking was verified online.

## Evidence captured October 22, 2026

Test host reported macOS 27.0.1 (26A434), arm64, Swift 6.4; this is the tested host, not a supported-release declaration. SDK compilation targets macOS 14. No signed sandboxed app or Intel/macOS-14 runtime was exercised.

Five public-boundary tests (including six parameterized scenarios) passed. Red/green cycles first failed for absent assessment API, missing safety guidance, and absent disposable metadata inspection. The local disposable-file test verified unchanged bytes, modification date and allocation after inspection. It does not prove iCloud non-hydration.

| Scenario | Synthetic policy observation | Real disposable iCloud evidence |
|---|---|---|
| Placeholder | notDownloaded reports already-placeholder; no eviction | Not run |
| Current local copy | still blocked by unvalidated pinning | Not run |
| Stale downloaded copy | guidance identifies stale version | Not run |
| Pinned / unknown pinning | all observations fail closed; no invented pin detector | Not run |
| Pending upload / transfer | incomplete upload and active transfer blocked | Not run |
| Conflict | conflict/unknown status blocked | Not run |
| Offline / transfer errors | error observation blocked; missing fields blocked | Not run |
| Metadata-only observation | local disposable bytes/allocation unchanged | Cloud non-hydration not verified |
| Eviction retaining online original | Not attempted; no mutation API exposed | Not run; unsupported |

No disposable cloud account or fixture was available during implementation. Real cloud scenarios above were deliberately not fabricated. Issue completion is an **unsupported capability decision with a reproducible safe probe**, not a successful native eviction qualification.

## Gate for revisiting eviction

Use a separate disposable macOS account and disposable cloud content; obtain an independently reviewed pinning/sync contract before adding a mutation path. Record OS/SDK/account configuration without identifiers. For each matrix row, take resource-metadata/allocation observations before and after repeated probes while monitoring downloads in a disposable environment. No preview/content access is allowed during the non-hydration experiment. Reproduce errors/offline states explicitly rather than inferring them from nil metadata.

Only after the scan and pin/sync gates pass may a separately opted-in experiment call Foundation eviction on that exact disposable target. Independently verify the online original in the disposable account on another device or iCloud web, and that the local copy becomes a placeholder; record inconclusive verification as unsupported. Do not infer reclaimable bytes from logical size or an API returning success. Guidance stays enabled when any gate fails. This package intentionally cannot perform that experiment yet.

## Primary-source basis

- [Apple: evictUbiquitousItem](https://developer.apple.com/documentation/foundation/filemanager/evictubiquitousitem(at:)): removes the local version while preserving the cloud item; ordinary deletion has different consequences. No extra coordinated write is needed.
- [Apple: isUbiquitousItem](https://developer.apple.com/documentation/foundation/filemanager/isubiquitousitem(at:)): cloud targeting does not establish upload completion.
- [Apple: downloading statuses](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus): current is latest known to device; downloaded is stale; notDownloaded is a placeholder state.
- [Apple: downloadRequested](https://developer.apple.com/documentation/foundation/urlresourcevalues/ubiquitousitemdownloadrequested): download intent is not documented as proof of Keep Downloaded/pinning policy. Treating it as a pin flag would be an unsupported inference.

Foundation NSURL resource-key headers in the installed SDK were also inspected. This investigation found no sufficient pinning contract; it does not claim that no such supported API can exist on any platform/version. Broader File Provider mechanisms require their own applicability and entitlement investigation before use.

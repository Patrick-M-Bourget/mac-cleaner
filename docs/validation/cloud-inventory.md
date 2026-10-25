# Read-only iCloud storage opportunity

Issue #5 · October 22, 2026 · M0 inventory capability with a consented, bounded partial personal assessment.

## What the application measures

Only a user-selected folder is scanned. The inspector's iCloud section groups regular-file resource identities into positively local downloaded copies, positively nonlocal/not-downloaded items, and unknown local/download states. Cloud membership itself can be unknown. Repeated hardlink identities count once. Packages, symlink targets, other volumes and unobserved/inaccessible entries remain outside the measured subtotal; scan completeness and observation time accompany the report.

Local allocated bytes are distinct from cloud-only logical size and cloud-only allocated bytes. A placeholder may occupy metadata allocation; it is not forced to zero. A missing allocated measurement produces Unknown. Partial/unreadable coverage or unmeasured package contents keeps complete cloud totals Unknown; any known local allocation is labelled only as an observed subtotal. A failed root never claims zero iCloud storage. These are inventory observations, not exclusive space or reclaimable-byte promises. APFS sharing and snapshots prevent a simple subtraction from predicting free capacity.

Foundation supplies iCloud membership, current/downloaded/notDownloaded metadata, upload-complete, uploading, downloading and conflict flags. Missing flags stay Unknown. “Current” is the latest version known to this device; a downloaded version can be stale. Neither status certifies remote durability. Pinning/Keep Downloaded remains Unknown: no supported contract has passed validation. Every report remains read-only with eviction unavailable, consistent with the [disposable feasibility decision](../../Validation/ICloudProbe/README.md).

The app never opens contents, generates thumbnails, hashes files, starts a download or executes eviction while building the report. Quick Look is separate and requires explicit action plus fresh positive local-state and identity checks. No personal cloud folder is selected by tests.

## Recorded evidence

Disposable policy fixture: three synthetic 1,000-byte ordinary files with injected provider-metadata observations. One confirmed local copy reports 200 allocated bytes; one not-downloaded item reports 1,000 logical bytes and 10 allocated bytes; one has unknown cloud membership. The report preserves unknown upload/pinning evidence and exposes no eviction capability. This establishes accounting and UI policy only; it is not a live iCloud non-hydration experiment.

Native fixture journey: choose the suite-owned temporary folder through NSOpenPanel, scan its text file, inspect path/size, read the cloud section and its explicit unknown pinning state, and retain unchanged file contents and outer-window geometry. Ordinary local fixtures do not establish which real iCloud provider/OS layouts return usable metadata.

## Personal assessment — consented bounded observation

The user explicitly approved metadata-only inspection of their iCloud Drive folder on October 22, 2026. The public scanner ran once on that standard root, with a 10,000-entry bound and a 45-second process guard. It completed after 22.2 seconds at the entry bound. No contents, previews, hashes, downloads or mutation APIs were requested; no OS grants were sought and the scope was not broadened. Metadata-only operation is not independent proof of provider non-hydration. No private paths, filenames, contents or account identifiers are included here.

The observed subset contains 9,343 confirmed iCloud file identities, all reported cloud-only; no positively local downloaded iCloud file was observed in that subset. The 0-byte **observed local-cloud allocation subtotal** is not a whole-folder or whole-Mac zero claim. The 107,033,674,874-byte logical subtotal covers all observed regular-file identities and is not a local allocation or reclaimable-space estimate. The remaining tree and protected/unmeasured package contents are unknown. Full cloud logical/allocation totals remain Unknown.

Path-free aggregate evidence (UTC timestamp corresponds to October 22 evening in Toronto):

```json
{
  "assessment": "partial-selected-scope",
  "cloudOnlyFiles": 9343,
  "confirmedCloudIdentities": 9343,
  "durationSeconds": 22.2085919380188,
  "eviction": "unsupported",
  "issueCounts": {
    "entryLimit": 1
  },
  "logicalKnownSubtotalBytes": 107033674874,
  "maximumEntries": 10000,
  "observedAt": "2026-10-23T01:34:12Z",
  "observedEntries": 10000,
  "observedFileIdentities": 9390,
  "observedLocalCloudAllocatedBytes": 0,
  "observedLocalCloudFiles": 0,
  "unknownCloudStateCount": 0,
  "unknownMembershipCount": 0,
  "unmeasuredPackageOrOtherContents": true,
  "volumeAvailableBytes": 9756143616,
  "volumeAvailableMetric": "Important usage",
  "volumeCapacityBytes": 245107195904
}
```

This records a real consented personal assessment with explicitly partial coverage. It does not claim a complete account inventory or an eviction qualification. To finish a whole-scope opportunity assessment, use a separately approved larger bounded scan or narrower explicit locations and record aggregate coverage rather than committing paths. No second scan was performed merely to expand this evidence.

## Priority decision and unsupported conditions

The implemented report can reveal a measured opportunity after valid user-selected observations. The consented observed subset supplies **no evidence of material local iCloud-download allocation**; the unobserved remainder remains unknown. Continue the core Downloads workflow rather than prioritizing eviction from cloud logical sizes. Production local eviction remains **unsupported**. Unknown pinning, missing upload/conflict/transfer evidence, stale copies, incomplete coverage, unavailable metadata and unqualified File Provider layouts prevent interpreting local allocation as safely evictable space. Preserve guidance and the conditional M2 milestone until independent disposable and personal evidence supports a different decision.

Primary references: [Apple downloading status](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus), [iCloud membership](https://developer.apple.com/documentation/foundation/urlresourcevalues/isubiquitousitem), [allocated-file size](https://developer.apple.com/documentation/foundation/urlresourcevalues/totalfileallocatedsize), and [download intent](https://developer.apple.com/documentation/foundation/urlresourcevalues/ubiquitousitemdownloadrequested). Download intent is not treated as a pinning flag.

Native negative-membership evidence: on the tested host, URL resource values omitted the optional ubiquitous-item flag for a disposable ordinary file. The reader now uses the explicit [FileManager iCloud-targeting predicate](https://developer.apple.com/documentation/foundation/filemanager/isubiquitousitem(at:)) only after valid metadata reads and with matching before/after filesystem identity. Apple's predicate returns false for a nonexistent item too, so a missing/changed item fails the identity checks rather than becoming an ordinary local file. This predicate reports iCloud targeting, not upload completion, pinning or generic third-party-provider safety. Injected/failed metadata remains Unknown.

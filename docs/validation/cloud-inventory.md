# Read-only iCloud storage opportunity

Issue #5 · October 22, 2026 · M0 inventory capability with an outstanding personal-assessment gate.

## What the application measures

Only a user-selected folder is scanned. The inspector's iCloud section groups regular-file resource identities into positively local downloaded copies, positively nonlocal/not-downloaded items, and unknown local/download states. Cloud membership itself can be unknown. Repeated hardlink identities count once. Packages, symlink targets, other volumes and unobserved/inaccessible entries remain outside the measured subtotal; scan completeness and observation time accompany the report.

Local allocated bytes are distinct from cloud-only logical size and cloud-only allocated bytes. A placeholder may occupy metadata allocation; it is not forced to zero. A missing allocated measurement produces Unknown. These are inventory observations, not exclusive space or reclaimable-byte promises. APFS sharing and snapshots prevent a simple subtraction from predicting free capacity.

Foundation supplies iCloud membership, current/downloaded/notDownloaded metadata, upload-complete, uploading, downloading and conflict flags. Missing flags stay Unknown. “Current” is the latest version known to this device; a downloaded version can be stale. Neither status certifies remote durability. Pinning/Keep Downloaded remains Unknown: no supported contract has passed validation. Every report remains read-only with eviction unavailable, consistent with the [disposable feasibility decision](../../Validation/ICloudProbe/README.md).

The app never opens contents, generates thumbnails, hashes files, starts a download or executes eviction while building the report. Quick Look is separate and requires explicit action plus fresh positive local-state and identity checks. No personal cloud folder is selected by tests.

## Recorded evidence

Disposable policy fixture: three synthetic 1,000-byte ordinary files with injected provider-metadata observations. One confirmed local copy reports 200 allocated bytes; one not-downloaded item reports 1,000 logical bytes and 10 allocated bytes; one has unknown cloud membership. The report preserves unknown upload/pinning evidence and exposes no eviction capability. This establishes accounting and UI policy only; it is not a live iCloud non-hydration experiment.

Native fixture journey: choose the suite-owned temporary folder through NSOpenPanel, scan its text file, inspect path/size, read the cloud section and its explicit unknown pinning state, and retain unchanged file contents and outer-window geometry. Ordinary local fixtures do not establish which real iCloud provider/OS layouts return usable metadata.

## Personal assessment — not run

No consented personal folder selection occurred during implementation. No private paths, filenames, contents, account identifiers or inferred personal storage totals are committed. **The acceptance criterion requiring a consented personal assessment remains outstanding.** The actual personal iCloud opportunity is not yet known, and eviction must not be prioritized solely from synthetic numbers.

To complete that gate, the user can run the native app and explicitly choose the relevant iCloud folder. Record only a redacted summary: scan interval, OS/app build, coverage status, unique confirmed-local/cloud-only/unknown counts, local allocated bytes with unknown count, and selected-volume capacity metric. Do not copy paths or content into the repository. Distinguish an incomplete selected-scope subtotal from the whole Mac's storage consumption. If provider non-hydration has not been established in a disposable account, say so before undertaking broad personal assessment and use the separate feasibility protocol first.

## Priority decision and unsupported conditions

The implemented report can reveal a measured opportunity after valid user-selected observations. At present the personal opportunity is **unassessed**; production local eviction remains **unsupported**. Unknown pinning, missing upload/conflict/transfer evidence, stale copies, incomplete coverage, unavailable metadata and unqualified File Provider layouts prevent interpreting local allocation as safely evictable space. Preserve guidance and the conditional M2 milestone until independent disposable and personal evidence supports a different decision.

Primary references: [Apple downloading status](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus), [iCloud membership](https://developer.apple.com/documentation/foundation/urlresourcevalues/isubiquitousitem), [allocated-file size](https://developer.apple.com/documentation/foundation/urlresourcevalues/totalfileallocatedsize), and [download intent](https://developer.apple.com/documentation/foundation/urlresourcevalues/ubiquitousitemdownloadrequested). Download intent is not treated as a pinning flag.

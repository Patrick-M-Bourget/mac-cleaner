# Redacted diagnostics — #32

M6 future-gated development capability. From Overview launched with `--future-milestones`, choose **Review diagnostics**. This does not scan files or read raw history records. The explicit action freezes an allowlisted JSON snapshot; Save opens native NSSavePanel and writes only the reviewed bytes to the selected local destination. No automatic upload, service, fallback save location or cleanup action exists.

## Payload and privacy

Included: numeric app/build version or Unknown, OS version, CPU architecture, current session scope count, latest retained scan's observed entry count, selected count and fixed scan/cleanup/startup-recovery status/error-code enums. Counts are observations held in this process, not whole-Mac totals or historical capacity/reclaimable estimates. No observation time, host/user name, bundle account identifier or raw record is included. Uninspected/partial/unavailable status remains explicit; a 0 count means no retained observations rather than measured zero storage.

Excluded: paths, filenames, resource/batch/account/volume identifiers, raw error text/domains, contents, credentials, browser/cloud metadata and recovery records. Raw untrusted log/error dictionaries are not accepted. Version strings accept only bounded numeric dotted formats; injected path/email/identity strings become Unknown. The native adapter constructs the snapshot from typed aggregate/status values and Bundle/ProcessInfo, not by redacting arbitrary serialized records afterward. A saved report may still disclose intentionally shown OS/version/count/status information; inspect the exact preview before Save.

The preview stays frozen through cancellation/failure and changing underlying app state. Back returns to Overview; a new explicit Review diagnostics action replaces it with a new snapshot. Guarded Reset discards the local preview and preserves #13's operation/recovery protections. Export refuses the known local app-state subtree, including canonical parent-symlink aliases; an unavailable protection root fails closed rather than allowing an unchecked destination. It cannot clear/modify journal records or create approval authority.

## Public boundary evidence

Red→green public preview API: private sample path/email/resource-like and UUID strings supplied as versions do not appear, invalid versions become Unknown, and parsed JSON has exactly the documented field allowlist. Fixed enum error codes carry no raw descriptions.

Red→green public save workflow: cancellation leaves the reviewed payload unchanged; an actual missing-parent write fails without redirecting; successful explicit save bytes equal the preview exactly. An owned unresolved-authority sentinel and directory contents remain unchanged except for the selected report file. This covers local output behavior, not native dialog authorization.

After merging history/reset 38a593e and scanner follow-up, the final core suite passed 103 tests. Final native Debug build-for-testing and Release compilation both passed (Release signing disabled; no distribution claim). These checks use disposable data and injected/typed status; no personal folder, OS grant, service registration or network export is involved.

A further red→green preservation fixture refuses direct and symlink-aliased destinations inside the protected app-state directory, preserves the unresolved sentinel and immutable payload, and permits the explicitly selected external report. A missing protection root fails without creating a fallback file.

## Native UI qualification

Two focused journeys are supplied for initial and minimum sizes: bind an owned isolated state root, seed one actual durable unresolved record, open future Overview→diagnostics, verify payload excludes the fixture path/name/resource/batch identity, inspect both appearances, open native Save and Cancel, verify identical preview and retained unresolved journal/source sentinel. Shared components/scrolling and fixed reachable Back/Save are exercised without changing app window bounds.

Initial and minimum behavior journeys passed (24.2s/22.1s); the affected initial journey with explicit cancelled-status/dialog-dismissal assertions passed again (21.2s). Public UI verified native Save Cancel, unchanged payload, fixed action bounds and preserved actual unresolved SQLite/source fixture. The final destination-protection addition is independently covered by public core fixtures; it changes no preview layout or cancellation behavior.

**Visual qualification remains pending.** Inspected [blocked captures](../visual/diagnostics-blocked) for initial/minimum Light/Dark contain the “Enable ChatGPT Computer Use” onboarding window. They document the blocker, not design acceptance or unobscured review. No warning dismissal, new permission grant or preference workaround is part of this ticket. Shared components and fixed action composition are in source, but fidelity must be reviewed again from unobscured captures before visual qualification. VoiceOver/localization/OS-matrix/native destination-write failures remain broader manual gates; actual file write/cancellation semantics are separately covered at the public core boundary.

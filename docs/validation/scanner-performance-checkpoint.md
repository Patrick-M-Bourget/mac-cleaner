# Scanner performance checkpoint — paused for design-system priority

Historical checkpoint: implementation resumed after the design-system migration; see [current evidence and remaining qualification gates](scanner-performance.md). The measurements below describe the paused revision. Work stopped on October 22, 2026 when product priority changed to establishing the design system and migrating existing screens. This branch is not approved for integration yet.

## Implemented checkpoint

Public optional `ScanCancellation` and `ScanProgress` boundaries preserve existing scan callers and ScanResult fields. Preliminary progress contains at most 256 recent observations, is explicitly incomplete and never becomes cleanup authority. Native composition consumes a buffering-newest-one stream with generation guards; Stop acknowledges the request immediately while an in-flight OS metadata operation may still need to return. Scan and issue counts are bounded. Native coverage-error rendering shows a bounded initial set of issues with remaining-count guidance.

Before stopping, 37 merged core tests and the native build passed. No new native progress/scrolling UI test has been run. Current tests do not certify blocked-provider cancellation or cloud non-hydration.

## Actual owned-filesystem evidence

The reproducible release-mode runner lives under Validation/ScanBenchmark. It creates only an owned temporary root, checks disk headroom conservatively, and removes that root afterward. It does not inspect or clean personal files.

- [Million-entry preflight](benchmarks/scanner-million-preflight-checkpoint.json): declined before creating a fixture. Requested reservation 17,457,741,824 bytes exceeded 3,463,704,576 available bytes. No million-entry filesystem result is claimed.
- [50,000-file failing checkpoint](benchmarks/scanner-50000-failing-checkpoint.json): 50,000 owned zero-byte files plus 50 directories, complete coverage, scan 5.3597 seconds; first useful progress 0.00144 seconds; cancellation-start-to-worker-stop upper bound 0.00057 seconds at an ordinary metadata boundary.
- **Peak process resident memory was 586,547,200 bytes, exceeding the documented 300 MB target. This is a failure, not a qualified performance result.** Baseline process RSS was 34,111,488 bytes. Foundation autorelease/resource-cache retention is a hypothesis to investigate next; no fix has been applied or validated.

Host: Apple silicon, eight processors, 16 GiB RAM, macOS 27.0.1; selected volume capacity 245,107,195,904 bytes. This is not the specified 512 GB reference host. The recorded timing/memory is scoped to this fixture and process. The RSS value comes from MACH_TASK_BASIC_INFO resident_size_max (bytes), including process startup/fixture preparation, not an isolated instrumented scan-only allocation count. Current Apple XNU kern_resource.c maps ru_maxrss to that peak; old archived getrusage manual units differ, so no Linux-style kilobyte conversion was applied.

## Remaining work after design-system migration

Fix and remeasure memory retention without weakening metadata, identity, scope, cloud or unknown-total rules. Then add remaining clone/compressed/sparse/Unicode/changing-identity and mount-boundary fixtures, actual native progress/cancellation/scroll verification, and a safely provisioned million-entry/reference-host benchmark. A generated enumeration policy test is not a substitute for actual filesystem evidence. Existing 100,000-entry limit intentionally yields partial coverage on larger trees; exhaustive million-entry coverage is not implemented.

Coordinate resumed scanner/native changes with issue #10 refresh generation and pending-plan rules. Keep ScanProgress non-authoritative and preserve public ScanResult compatibility. No additional implementation should proceed on this checkpoint until the design-system priority is complete.

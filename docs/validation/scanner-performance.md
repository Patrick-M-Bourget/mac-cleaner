# Bounded scanner performance — #34

October 22, 2026. This implementation makes scanning progressive and bounded; **hosted million-entry workload evidence is recorded below; reference-host release qualification remains open**. The earlier [failed checkpoint](scanner-performance-checkpoint.md) is retained as evidence, not erased by the improvement.

**Later implementation:** [directory-stability evidence](directory-stability.md) records the current #39 policy and a new actual 50k benchmark. The measurements below describe #34 before directory ancestry/evidence checks; they are historical evidence, not qualification of the newer scanner.

## Public behavior and limits

`FolderScanner.scan(_:cancellation:onProgress:)` preserves existing callers through optional default arguments. A serial scanner actor executes synchronous blocking metadata work off MainActor, without creating a task per file. Cancellation checks surround metadata boundaries; requesting `ScanCancellation.cancel()` is synchronous and independent of the busy actor. An already blocked filesystem/provider call must return before worker termination. No sub-second stop guarantee is claimed for an unresponsive OS provider.

`ScanProgress` contains preliminary observed counts/subtotal and at most 256 recent observations. The first useful observation publishes immediately; later callbacks are coalesced to at most roughly ten per second plus the final flush. Native composition consumes a newest-one stream and checks the scan generation before applying updates/results. During an active native scan, the existing Stop action occupies the shared fixed bottom action strip so it stays reachable at minimum size. Preliminary progress has no selection or execution authority. Stop acknowledges immediately with explicit waiting guidance. `InspectionSession` checks task/token cancellation before updating its remembered reports.

Each scan retains at most 100,000 entries, depth 64 and 1,000 ordinary issues plus a terminal bound explanation. Reaching a bound is partial coverage, never a complete scope total. Scope protections, packages, link identity de-duplication, unknown allocation/cloud metadata and volume-versus-inventory distinctions remain intact. An identity/type change during metadata collection is rejected before publishing that row. This is observation consistency, not atomic execution safety.

Per-entry autorelease pools now include enumerator advancement and metadata reads. Retained observations use fresh path URLs instead of prefetched enumeration URLs that retain Foundation metadata caches. This directly addresses the prior 586,547,200-byte peak. The new `ScanProgressSummary` reuses the design system's summary/status surfaces, appears in its gallery, shows only five recent names and offers no per-file mutation controls.

## Reproducible owned-filesystem benchmark

Build/run from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --package-path Validation/ScanBenchmark
Validation/ScanBenchmark/.build/release/ScanBenchmark --entries 50000
Validation/ScanBenchmark/.build/release/ScanBenchmark --entries 100000
Validation/ScanBenchmark/.build/release/ScanBenchmark --entries 1000000
```

The runner creates only its named owned temporary root, reserves 16 KiB per requested file plus 1 GiB free headroom before creation, rechecks headroom while creating batches, and removes its root on exit. No personal files are scanned or cleaned. Files are empty, with one directory per thousand files. Reported peak is process-wide MACH_TASK_BASIC_INFO `resident_size_max` in bytes, including startup/fixture creation; it is not a scan-only allocation measurement. Native UI tests were not running during these benchmarks. Other host work is not controlled, so elapsed times are observations, not universal completion promises.

Host: Apple silicon, eight processors, 16 GiB RAM, macOS 27.0.1 (26A434), Xcode 27.1, 245,107,195,904-byte volume. This is **not** the 512 GB reference environment.

| Actual owned fixture | Scan time | First useful progress | Process peak RSS | Result |
|---|---:|---:|---:|---|
| 50,000 files + 50 directories | 5.400 s | 0.00164 s | 113,590,272 bytes | Complete 50,050 observations |
| 100,000 files + 100 directories | 10.949 s | 0.00154 s | 206,012,416 bytes | 100,000 observations, entry-limit partial coverage |
| 1,000,000 requested files | Not run | Not measured | Not measured | Preflight declined; 17,457,741,824 reserved bytes exceeded 6,980,366,336 available |

Raw reports: [50k final](benchmarks/scanner-50000-final.json), [100k final](benchmarks/scanner-100000-final.json), [million preflight](benchmarks/scanner-million-preflight-final.json). The earlier intermediate [50k memory check](benchmarks/scanner-50000-autorelease.json) independently measured 113,639,424 bytes. Ordinary metadata-boundary cancellation start-to-worker-stop upper bounds were 0.00044 s and 0.00051 s respectively. These include scan startup until its first callback requests cancellation; they do not measure blocked-provider termination.

These actual bounded fixtures meet the documented first-results <3 s, cancellation <1 s at an ordinary returning metadata boundary, and process peak <300 MB targets on this host. They do not certify arbitrary path lengths, every provider or a million-entry/reference-host workload. The memory bound is for one bounded scan process, not an unlimited number of remembered scopes or histories.

## Disposable fixture coverage and remaining gates

Public scanner tests cover progress batches, cancellation, bounded metadata failures, changing identities (red before fix, green after), sparse logical versus allocated bytes, hardlink identity de-duplication, Unicode/long filenames and protected package boundaries. Actual APFS `clonefile` succeeded on this host; distinct clone identities retain separate logical lengths without implying exclusive reclaimable allocation. A disposable `ditto --hfsCompression` copy was attempted using the system tool's documented option; `UF_COMPRESSED` stayed false here, so **native compressed-file qualification remains open**. The test records that condition and checks ordinary logical-size semantics; it does not substitute a plain file for a compressed fixture.

A genuine mounted-volume boundary/unmount fixture, a positively compressed file, non-returning provider cancellation, cloud non-hydration and the specified reference hardware remain integration gates. The hosted million-entry workload is now recorded in the follow-up below. Existing symlink/scope fixtures do not prove genuine mount behavior. No mounts, cloud downloads or OS permission changes were performed to obtain these results. Default retained-entry limits intentionally prevent exhaustive million-entry inventory in this slice.

## Native journey and checks

50 StillCore tests passed. Native build-for-testing passed after merging integration `6c641fc`. Final focused initial-size and minimum-size public Stop journeys passed **2/2** (75.72 seconds total test time), each using its own 50,000-file tree, actual folder picker and both appearances. They observe preliminary progress within a three-second wait, verify Stop's frame remains inside the window, scroll during scanning, click Stop and observe acknowledgement/stopped text within a one-second wait, preserve window bounds, expose no Review cleanup action from preliminary observations and verify the owned sentinel remains present. This is focused journey evidence, not a full-suite run or blocked-provider termination guarantee.

The first fixed-strip verification failed a pre-click `isHittable` assertion although its video showed Stop visible in the fixed slot. Final tests verify geometry and actual interaction rather than treating that accessibility flag as the user outcome. No fixed delay or larger fixture was added to mask it. Earlier initial/minimum progress journeys also passed before Stop moved into the persistent strip; they are not substituted for final validation.

Actually inspected [Light](../visual/scanner-progress/progress-Light.png), [Dark](../visual/scanner-progress/progress-Dark.png), [minimum Light](../visual/scanner-progress/progress-minimum-Light.png) and [minimum Dark](../visual/scanner-progress/progress-minimum-Dark.png) native captures at 1120×760 and 900×640: shared surfaces, white light sidebar, bounded five-name preview, incomplete-coverage message and fixed reachable Stop control. The component also has an inert gallery example. These captures cover the changed progress presentation; they do not repeat every screen's design review. OS accessibility and deployment-target qualification remain separate gates.


## Hosted million-entry workload — October 23 follow-up

The manual `benchmark` suite in [native.yml](../../.github/workflows/native.yml) builds the existing Release benchmark and runs its owned million-file fixture on an ephemeral macOS runner, with the original 16 KiB/file plus 1 GiB headroom reservation unchanged. It records source/run/toolchain/host metadata and uploads raw reports. The native UI job does not run for this selection. The local low-space preflight result above remains historical; no million-file tree was created on the user's Mac.

[Initial hosted run 39997624851](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39997624851) created the complete million-file fixture, but process peak reached 715,096,064 bytes. Already **598,163,456 bytes** were resident before scanning: the generator retained Foundation temporary objects. This result did not meet the 300 MB process budget and is preserved. `db70c50` drains an autorelease pool for each fixture-file creation, without changing scanner logic, scope, deadlines or limits. A local 1,000-file smoke completed and removed its owned tree; only the hosted runner repeated the million-file workload.

[Corrected run 39998429826](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39998429826), source `db70c50`, completed the benchmark on macOS 26.6.2/Xcode 26.6, arm64 VirtualMac2,1, three CPUs, 7 GiB RAM, 343,073,095,680-byte volume. This is **not** the specified 512 GB reference environment.

| Measurement | Observed |
|---|---:|
| Created fixture | 1,000,000 files, 1,000 batch directories |
| Fixture creation | 76.010 seconds |
| Resident/process peak before scan | 9,043,968 bytes |
| Whole-process peak after scan | **172,949,504 bytes** |
| First useful progress | **0.06069 seconds** |
| Largest progress batch | 256 observations |
| Retained observations | 90,175 |
| Scan duration | 32.088 seconds |
| Coverage | Partial: cooperative time limit |
| Ordinary-boundary cancellation upper bound | **0.001596 seconds** |

The observed process peak, first-progress and normal metadata-boundary cancellation meet the documented 300 MB / 3 second / 1 second budgets on this host. This is a **million-entry workload with bounded partial observation**, not complete million-entry inventory or a strict wall-clock interruption guarantee. The cooperative 30-second deadline needs an in-flight OS call to return. No findings beyond the observed partial coverage are inferred, and no growth baseline is authorized.

Raw [final report](benchmarks/scanner-million-hosted-final.json), [environment](benchmarks/scanner-million-hosted-final-environment.json), [before-pool report](benchmarks/scanner-million-hosted-before-pool.json) and [source/run/hash manifest](benchmarks/scanner-million-hosted-manifest.json) preserve both results. #34 still requires the declared reference host, genuine mount/provider/non-returning-I/O and positively compressed-file qualification described above. This benchmark does not close those gates or qualify a release.

## Opt-in genuine volume/compression harness

The [owned-volume fixture harness](../../Validation/FilesystemFixtures/README.md) now makes genuine mount boundary, explicit mounted-scope, disconnected-scope and positively compressed metadata qualification reproducible on ephemeral hosted CI. Local Debug compilation and the personal-host refusal guard passed; **hosted runtime results are not yet recorded**. No disk image was attached on the personal Mac. A compression attempt only qualifies when native `UF_COMPRESSED` is actually set and allocation is known smaller than the literal 1 MiB logical fixture. Unsupported compression stays an explicit remaining gate. The harness uses one 64 MiB HFS+ image, a private owned root and exact image/device verification before non-forced detach; failed or ambiguous cleanup preserves the fixture instead of traversing a possible mount. This does not qualify APFS mount variants, removal during blocked I/O, personal/cloud-provider behavior or the 512 GB reference environment.

# Docker read-only inventory — issue #33

Decision: **no real Docker runtime/version is qualified yet**. The app never probes an installed CLI, daemon, context, socket or Docker home directory automatically. Selecting a CLI and Inspect currently checks availability and returns runtime/provenance guidance without executing it. No Docker installation, daemon startup, container launch, prune, delete, disk shrink/move or elevation is offered.

## What can be inspected

The future-milestones Overview opens a secondary Docker storage screen. An explicit file picker can read metadata for the chosen regular disk-image file: logical file length and optional host allocated bytes. That measurement does not prove Docker ownership or VM virtual capacity. No image contents are read. Unknown capacity/allocation remains Unknown; no zero fallback or exclusive-reclaim promise is used. A generic image's logical length is deliberately not relabelled virtual capacity.

A clearly labelled synthetic daemon report demonstrates Images and Local Volumes. Volumes are identified as persistent application data, even if the daemon might label some usage reclaimable. Daemon summary strings, possible shared image layers and host sparse-file allocation are separate; they are never summed as additive disk usage. This app offers no cleanup action for any category.

## Reproduce disposable evidence

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StillCore --filter Docker
```

Fixtures use owned `StillDockerProbe-<UUID>` directories only. A sparse 64 MiB file verifies logical length remains separate from unknown VM capacity, optional allocation and unverified ownership, without changing its modification time. Allocation is not asserted equal to logical size or a fixed block size. This does not test Docker.raw semantics for a released Docker Desktop build.

A disposable helper accepts only `--version` and `--host unix://<owned>/daemon.sock system df --format json`; anything else fails. It emits controlled JSON-lines output and leaves a persistent-volume sentinel unchanged. This demonstrates the command boundary and fixture parsing only: **the helper is not Docker, and no daemon was contacted**. The explicit dummy endpoint and disposable HOME/DOCKER_CONFIG prevent accidental default-context use. Timeout/output-limit and exact-argument tests exercise the shared bounded Process seam; no shell evaluation or credentials are used by native inventory.

`fixture-only-1` parsing recognizes category/count/active/size/reclaimable fields, rejects unknown categories/versions and invalid counts, and retains unavailable metric strings as optional Unknown values. Runtime qualification is always false, including successfully parsed fixtures. Unknown output, tool/access failure, missing daemon qualification or timeout yields guidance rather than an executable promise.

## Primary-source basis

[Docker system df](https://docs.docker.com/reference/cli/docker/system/df/) documents daemon usage summaries and JSON formatting. It distinguishes shared/unique image size and supports verbose reporting; daemon-reported reclaimability is not a promise of host-file exclusive release. [Docker CLI formatter source](https://github.com/docker/cli/blob/master/cli/command/formatter/disk_usage.go) exposes the category/count/size/reclaimable summary shape. This moving source is a research pointer, not a pinned released-version contract.

[Docker Desktop Mac storage FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) directs users to Desktop settings for the configured image location and distinguishes maximum disk-image size from actual host space consumed. Paths can change, so this app does not infer ownership from `Docker.raw` or search a default path. It does not surface the FAQ's destructive recovery commands as app actions.

## Remaining qualification

Use an already available, independently isolated genuine disposable Docker runtime; do not start a personal daemon or install a runtime merely to test this feature. Record exact CLI/Engine/Desktop versions, local ownership and endpoint identity, daemon configuration and a pinned machine-output contract. Confirm readonly command behavior and persistent-volume sentinels across offline, denied, timeout and unknown-output cases. Independently correlate configured image metadata with Desktop's capacity/allocation measures, preserving sparse-file and shared-layer caveats. No such runtime was available/used for this implementation, so genuine Docker integration remains unproven.

Process launch stalls and descendant-process cleanup limitations of the shared tool runner remain additional gates. Native file metadata checks do not certify every provider's non-hydration behavior. No personal Docker metadata or contents were accessed during testing.

Recorded verification: 34 merged StillCore tests passed; native build passed. A focused native UI smoke passed future Overview → synthetic Docker report → Back with unchanged window bounds, visible persistent-volume labels and distinct unknown host/VM measurements. It selected no personal tool or file and changed no OS settings. Real Docker compatibility is not inferred from these checks.

## Explicit selected local runtime implementation — October 23 follow-up

The earlier no-op selected-CLI scaffold is superseded. The future route now accepts an explicitly selected local executable and an initially empty absolute Unix socket field, then executes **only after Inspect**. It never discovers a personal installation, daemon or context. This is a narrowly supported inspection implementation, **not genuine Docker runtime qualification**.

Official release provenance (downloaded into owned research cache solely to calculate hashes; no Docker installation/start/daemon contact):

| Official archive | SHA256 of `docker/docker` bytes |
|---|---|
| [macOS arm64 28.5.1](https://download.docker.com/mac/static/stable/aarch64/docker-28.5.1.tgz) | `f2b5f74bd7837f1b98e52bff9df1666d84eb6666cd9118b6c5c6e8eb56fc02ec` |
| [macOS x86_64 28.5.1](https://download.docker.com/mac/static/stable/x86_64/docker-28.5.1.tgz) | `eb49f960a02f4541c9827811aa098f12f33b2be9ebca89b5934ddb397d402c7f` |

No Docker binary is redistributed or installed by Still. The selected file is opened nonblocking with no symlink following, verified regular with a 128 MiB limit, streamed into a private 0700 workspace and hashed. Only an exact pinned snapshot becomes executable (0500). Launch uses that snapshot, never the selected mutable path. The workspace/config are removed after completion. An explicitly entered canonical existing Unix socket is required; symbolic links/control characters/remote URLs are rejected. Socket access denial gives contextual guidance without changing permissions. The endpoint is not a claim of Docker ownership or a guarantee against concurrent external changes.

CLI commands use `--config <private empty config> --host unix://<explicit socket>`, a scrubbed environment and private HOME/TMPDIR. `version --format '{{json .}}'` must identify CLI and Engine 28.5.1 before `system df --format json`. Each command has a 5-second read deadline and 64 KiB combined output limit. Timeout, unavailable, unsupported/malformed and denied results discard prior daemon measurements; raw stderr is not displayed. Shared Process launch-stall/descendant limitations remain release gates, as previously recorded.

[Pinned 28.5.1 formatter source](https://github.com/docker/cli/blob/v28.5.1/cli/command/formatter/disk_usage.go) defines the four summary categories and string counts/sizes. Runtime reports require all four unique categories, valid nonnegative total/active counts and bounded printable size/estimate fields. Unknown measurements stay unknown. The synthetic gallery parser remains separate and may demonstrate a subset. Neither a valid schema nor exact CLI hash qualifies a real Engine/storage setup.

TDD evidence: untrusted selected executable rejected before execution (red missing public capability → green); pinned CLI/Engine schema (red missing parser → green); truncated/oversized metric report rejection (red assertions → green). Nine focused Docker tests pass locally, including a controlled helper accepting only exact explicit-endpoint version/report commands with isolated HOME/config and unchanged persistent-data sentinel. That helper **is not Docker**. Local native build-for-testing passed. Native Light/Dark initial/minimum screenshots and the focused public journey are to be reviewed on the integration revision before this UI change is accepted. No genuine Docker Engine, personal runtime, personal socket or personal image was inspected.


Additional transport evidence: the **genuine official pinned arm64 CLI** was run through the public `inspectSelected` boundary against an owned synthetic Unix HTTP server. This exercised staged-byte provenance, isolated configuration, real vendor version/report formatting and strict parsing. The synthetic server advertised Engine 28.5.1/API 1.51 and one active 12 GB persistent volume. Observed output: four categories, Local Volumes 1 total / 1 active / 12GB. The complete request log contained only `GET /_ping`, `GET /v1.51/version`, `GET /_ping`, `GET /v1.51/system/df`; no POST or DELETE was received. A separate disposable persistent-data sentinel had identical SHA256 before/after. The owned server processes/socket/fixture were then removed; no background probe remains. This is **genuine CLI + synthetic daemon evidence**, not genuine Engine/Desktop qualification. The official binary was downloaded into research cache and never installed. Research probe sources/logs are outside the repository under the implementation notes cache. All **121 StillCore tests** passed on the final core implementation; the focused Docker subset has nine tests.

### Endpoint edit invalidation

Changing the socket field clears prior daemon evidence and its synthetic/live provenance, then requests a fresh explicit inspection. Reassigning the identical path does not discard a report. Independently selected disk-image metadata is retained, since it is a separate observation and never claimed to belong to the daemon. The existing native public journey now shows a report, changes the endpoint, and asserts prior volume/report evidence disappears, guidance resets, host/VM unknown states remain and window bounds stay fixed in both appearances/sizes. The regression was written before the model change; the old implementation has no socket-change handler and cannot satisfy its new guidance/evidence assertions. No native red execution was performed locally; hosted execution is pending root integration. No real daemon is contacted by this regression.

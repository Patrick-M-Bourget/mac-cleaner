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

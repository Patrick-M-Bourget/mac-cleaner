# pip inventory qualification — issue #24

A **genuine disposable** Python 3.9 / pip 21.2.4 environment passed read-only cache inventory. This qualifies the tested disposable command/output context, not arbitrary installed interpreters or newer pip releases. Ordinary user-selected installations currently return qualification guidance before any tool invocation. No cache mutation, package install/download, credential request or elevation is offered by the app.

## Reproduce

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StillCore --filter genuineDisposablePipInventoryPreservesOwnedEnvironment
```

Prerequisite: trusted existing Apple Command Line Tools `/usr/bin/python3` with bundled ensurepip. The observed host was Apple silicon macOS 27.0.1, Python 3.9.6, ensurepip/pip 21.2.4 and Swift 6.4. No global Python or pip is installed/upgraded by this test. Missing tools or different bundled versions fail this exact qualification test; they must not be relabelled as validated 21.2.4. Bootstrap requires no network according to ensurepip's documented contract.

The test creates an owned `StillPipProbe-<UUID>` root and an empty venv, then invokes that venv's ensurepip using bundled components. Bootstrap is **test provisioning**, distinct from ordinary inventory; the app never bootstraps an interpreter. HOME/TMPDIR/cache are inside the owned root. After provisioning, a synthetic 29-byte wheel-named sentinel is seeded in an alternate cache root. It is not a valid installed package and is never installed.

Before inventory, the test snapshots every owned regular-file byte sequence, entry names, symlink destinations and modification dates including the root. During inventory it invokes the actual venv pip with `--version`, `cache dir`, `cache info`, and `cache list --format=abspath`. It verifies reported cache scope, one listed wheel, 29 logical bytes, then compares the entire owned snapshot unchanged. Access times are deliberately not compared because the test's verification reads may affect them. Temporary files and venv are removed only within that owned boundary afterward. No personal interpreter/pip/cache is inspected.

## Scope and size semantics

`PipInventory` preserves configured cache and tool-reported summary separately from listed wheel paths and metadata measurements. `PipCacheReport` distinguishes optional logical/allocated bytes per wheel. Wheel listing is **not the complete HTTP cache inventory**, and reported aggregate strings are not exclusive reclaimable space. Missing allocations remain optional/Unknown. No cleanup authority is created from any preview.

The parser recognizes only the observed pip 21.2.4 / Python 3.9 output contract. Unknown versions, output changes, out-of-root or noncanonical traversal paths, conflicting wheel counts, unavailable tools and symlink escapes produce unsupported guidance/errors. Actual returned roots are checked against the explicitly selected disposable cache, including macOS `/private/var` versus `/var` aliases. No fixed home-cache path is assumed.

The shared Process boundary uses executable/argument arrays, bounded output and time, null input and sanitized environment. Inventory passes Python `-I -B`, pip version-check suppression, PIP_CONFIG_FILE=/dev/null and explicit --cache-dir. There is no shell evaluation. Existing system-boundary tests cover timeout, output cap and literal metacharacters. Process launch itself and complete descendant-process termination remain qualification limits; the tested pip inventory commands did not spawn unbounded work. This is not a general arbitrary-interpreter sandbox.

## Native interface and remaining gates

The `--future-milestones` Overview offers secondary **Review pip cache opportunities**, explicit interpreter/cache pickers, Inspect and a labelled recorded disposable evidence reference. Selecting arbitrary paths does not establish interpreter startup/site-package provenance, so those remain unexecuted and unsupported. The recorded reference redacts paths and identifies its synthetic seed; it is not presented as the user's cache. No additional primary navigation item or mutation action is added.

To enable a selected real installation, separately establish trusted interpreter/module initialization and exact pip provenance, qualify its version and configured environment with unchanged-state evidence, and constrain command semantics. Modern pip/HTTP-v2 output, alternate Python versions, minimum-OS/Intel runtime and user-config applicability are not certified by this experiment. Mutation belongs to #25 and requires its own approval/protection contract.

## Primary sources

- [Python ensurepip](https://docs.python.org/3/library/ensurepip.html): bundled bootstrap without internet. [Python venv](https://docs.python.org/3/library/venv.html): environment creation and optional pip provisioning.
- [pip cache](https://pip.pypa.io/en/stable/cli/pip_cache/): dir/info/list and absolute-path output. [pip caching](https://pip.pypa.io/en/stable/topics/caching/): wheel versus HTTP caches, on-disk layout is an implementation detail.
- [pip configuration](https://pip.pypa.io/en/stable/topics/configuration/): PIP_CONFIG_FILE=os.devnull disables config loading. [pip general options](https://pip.pypa.io/en/stable/cli/pip/): cache path and version-check suppression. Python -I differs from pip --isolated; the latter ignores environment variables, so it is not silently substituted. No undocumented analytics flag is invented.

Recorded implementation validation: 29 merged StillCore tests passed, including the genuine disposable environment and complete owned snapshot comparison. Native build passed after shared session-selection integration. A native UI smoke passed the future Overview → pip reference → Back journey with stable bounds; it did not execute an interpreter or modify OS settings. These observations do not qualify arbitrary user installations.

## Separate mutation-boundary evidence (#25)

A [genuine owned vendor-command experiment](../../Validation/PipMutationExperiment/README.md) now demonstrates that21.2.4 pattern removal widens beyond the frozen reviewed manifest and does not bind resource identity. Actual commands run only in disposable owned venv/cache trees with seeded wheel-shaped fixtures. The app's ordinary installations remain unexecuted/guidance-only, and no production mutation is enabled. Inventory compatibility does not imply mutation compatibility.

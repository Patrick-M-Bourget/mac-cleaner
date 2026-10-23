# pip inventory qualification — issue #24

Read-only selected-cache inventory now supports the narrowly verified Apple Command Line Tools Python 3.9 / bundled pip 21.2.4 runtime; see the October 23 capability section below. Arbitrary selected interpreters are never executed. Earlier genuine disposable venv qualification remains recorded as historical supporting evidence. No cache mutation, package install/download, credential request or elevation is offered by the app.

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

## Historical native interface and remaining gates (before October 23 follow-up)

The `--future-milestones` Overview offers secondary **Review pip cache opportunities**, explicit interpreter/cache pickers, Inspect and a labelled recorded disposable evidence reference. Selecting arbitrary paths does not establish interpreter startup/site-package provenance, so those remain unexecuted and unsupported. The recorded reference redacts paths and identifies its synthetic seed; it is not presented as the user's cache. No additional primary navigation item or mutation action is added.

To enable a selected real installation, separately establish trusted interpreter/module initialization and exact pip provenance, qualify its version and configured environment with unchanged-state evidence, and constrain command semantics. Modern pip/HTTP-v2 output, alternate Python versions, minimum-OS/Intel runtime and user-config applicability are not certified by this experiment. Mutation belongs to #25 and requires its own approval/protection contract.

## Primary sources

- [Python ensurepip](https://docs.python.org/3/library/ensurepip.html): bundled bootstrap without internet. [Python venv](https://docs.python.org/3/library/venv.html): environment creation and optional pip provisioning.
- [pip cache](https://pip.pypa.io/en/stable/cli/pip_cache/): dir/info/list and absolute-path output. [pip caching](https://pip.pypa.io/en/stable/topics/caching/): wheel versus HTTP caches, on-disk layout is an implementation detail.
- [pip configuration](https://pip.pypa.io/en/stable/topics/configuration/): PIP_CONFIG_FILE=os.devnull disables config loading. [pip general options](https://pip.pypa.io/en/stable/cli/pip/): cache path and version-check suppression. Python -I differs from pip --isolated; the latter ignores environment variables, so it is not silently substituted. No undocumented analytics flag is invented.

Recorded implementation validation: 29 merged StillCore tests passed, including the genuine disposable environment and complete owned snapshot comparison. Native build passed after shared session-selection integration. A native UI smoke passed the future Overview → pip reference → Back journey with stable bounds; it did not execute an interpreter or modify OS settings. These observations do not qualify arbitrary user installations.

## Separate mutation-boundary evidence (#25)

A [genuine owned vendor-command experiment](../../Validation/PipMutationExperiment/README.md) now demonstrates that21.2.4 pattern removal widens beyond the frozen reviewed manifest and does not bind resource identity. Actual commands run only in disposable owned venv/cache trees with seeded wheel-shaped fixtures. Arbitrary installations remain unexecuted; the narrowly verified read-only capability below supersedes the earlier guidance-only boundary. No production mutation is enabled. Inventory compatibility does not imply mutation compatibility.

## Explicit selected-cache capability — October 23 follow-up (#24)

The earlier guidance-only production boundary is superseded **only** for fixed Apple Command Line Tools Python 3.9 with bundled pip 21.2.4. This is not support for arbitrary user-installed pip. The user selects the interpreter and cache, then explicitly starts inspection. No personal cache is discovered or inspected by default.

Before executing Python, the adapter checks that the selected executable resolves to `/Library/Developer/CommandLineTools/usr/bin/python3`, verifies that binary and the complete Python3.framework with `codesign --verify --deep --strict --test-requirement==anchor apple`, and checks the bundled `pip-21.2.4-py3-none-any.whl` SHA-256 `fa9ebb85d3fd607617c0c44aca302b1b45d87f9c2a1649b46c26167ca4296323`. The inspected host's signature resource envelope explicitly includes this wheel. Failure does not fall back to another interpreter or installed pip.

The launcher uses `-I -S -B`; the app supplies a fixed script adding only that verified bundled wheel before `runpy.run_module`. Site initialization, `.pth` files, user/site packages and current-directory imports are bypassed. A sanitized environment sets HOME/TMPDIR to `/var/empty`, PIP_CONFIG_FILE=/dev/null, PIP_NO_INDEX=1 and version-check suppression. Commands are limited to version, cache dir, cache info and cache list --format=abspath; no shell, bootstrap or install is involved. `--cache-dir` explicitly overrides pip's normal configured root. This is a vendor cache observation under an explicit root, not discovery of the user's configured default.

A bounded no-follow metadata preflight (100,000 entries, 64 levels, five seconds) refuses symlinks, volume crossings and unreadable/incomplete traversal before tool commands. This matters because pip's `os.walk` can follow a symlink when it is the initial `http` or `wheels` traversal root. Vendor command output/time limits remain. Observations are not atomic against a concurrently changing cache; no mutation authority follows from any result. An adversarial concurrent filesystem replacement is not certified by this evidence.

The live UI exposes checked optional wheel logical/allocated subtotals and the observation time. Values may share allocations (for example hardlinks), so these are not exclusive reclaimable bytes. The pip 21.2.4 summary covers legacy `http` and `wheels`; HTTP-v2 and other contents remain unmeasured and total cache allocation remains Unknown. Unknown output/version still refuses support. Only the first 20 wheel paths are rendered; measurements cover all returned wheels.

Local red → green evidence: the existing selected adapter initially returned unsupported and no wheels for the genuine signed runtime; the new owned-cache test now reports one 29-byte synthetic wheel and compares all owned bytes, names, links and modification dates unchanged. A second red test exposed out-of-scope metadata through an `http` root link and passed after preflight refusal. An executable script fixture proves untrusted selection is not executed even for a version request. Checked-subtotal tests preserve Unknown for Int64 overflow and missing allocation. Nine focused pip tests passed on local macOS 27.0.1 / Apple silicon, Xcode 27.1; genuine command provenance is broader than a canned fixture, while seeded cache contents are deliberately synthetic. Native Debug build-for-testing passed including the added native journey; hosted source-pinned native capture qualification is now recorded in the integration evidence below.

Version-pinned primary implementation references: [pip 21.2.4 cache command](https://github.com/pypa/pip/blob/21.2.4/src/pip/_internal/commands/cache.py), [filesystem enumeration and size helpers](https://github.com/pypa/pip/blob/21.2.4/src/pip/_internal/utils/filesystem.py), and [Python 3.9 isolation/site/bytecode switches](https://docs.python.org/3.9/using/cmdline.html). [Current pip caching documentation](https://pip.pypa.io/en/stable/topics/caching/) explains that on-disk layout is an implementation detail and HTTP-v2 appeared in 23.3; it does not certify this adapter for current pip.


## Integration review and native evidence

Independent Standards and Spec reviews of `4443ee2...8c6f137` found no actionable pip findings. [Hosted run 39997810637](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39997810637) passed all **125 core tests**, including the genuine selected-cache capability, and the historical pip reference journey. Its overall native result was 2/3 because the new live journey's DEBUG fixture was not preloaded; no tool command was reached. An initial alias-only correction still failed in [run 39998512555](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39998512555). The diagnostic identified XCTest's separate sandbox temporary directory rather than the application's temporary directory. DEBUG-only setup now accepts that exact runner-container parent, retaining UUID, owner and device/inode checks. Release adapter behavior is unchanged by these test-setup corrections.

[Final focused run 39999016735](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39999016735), source `174c96a`, passed **1/1**, zero failures, **96.378 seconds**. The user journey explicitly clicks Inspect on the owned selected cache, runs the real verified Apple runtime/bundled pip, observes one wheel and 29 logical bytes, preserves exact window bounds and verifies the seed bytes and cache entries unchanged. It repeats at initial/minimum sizes and both appearances. This focused suite skips unrelated package checks; the unchanged core sources passed in the preceding full core check. Together the three tool journeys have passing evidence across runs; no single green full native suite is claimed.

All eight [original native captures](../visual/pip-inventory/manifest.json) were individually reviewed at 1024×640 and 900×640: selected scope and completed report in Light/Dark, shared reading/sidebar/summary surfaces, accessible native controls and wrapped long disposable paths. The top of the live summary shows count, logical and allocated subtotals; the report continues below the viewport in the scroll region. These are actual tool observations of a synthetic owned cache, not a personal pip assessment. They do not qualify modern pip, arbitrary Python installations, Intel, minimum macOS or personal cleanup.

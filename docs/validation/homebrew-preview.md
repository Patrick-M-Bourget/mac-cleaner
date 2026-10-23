# Homebrew preview qualification — issue #22

Decision: **real Homebrew preview unsupported until a released build passes disposable-installation qualification**. No production versions are qualified. Choosing an executable and Inspect leaves it unexecuted, including --version. The tool name/executable bit is not proof of trusted Homebrew identity or read-only runtime behavior. Missing/unknown installations produce guidance. No install, elevation, cleanup, automatic PATH/cache search or user-package inspection occurs.

The future-milestones Overview contains a secondary Homebrew review screen. It records an explicitly chosen executable, shows unavailable version/configuration evidence honestly, and includes a clearly labelled synthetic preview example. There is no cleanup action or primary Homebrew sidebar. This is retained M3 development capability, not M1 scope.

## Reproduce disposable evidence

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StillCore
```

Tests create an owned `StillHomebrewProbe-<UUID>` helper installation, prefix/cache fixture and package sentinel. A test-only internal qualification seam invokes its exact executable with `--version`, `--prefix`, `--cache`, then `cleanup --dry-run`. The helper accepts only those arguments, checks no-auto-update/no-analytics environment, reports one candidate and leaves sentinel bytes unchanged. This is **not an actual Homebrew installation** and does not certify any released Homebrew build. Test expectations use independent literal fixture output.

Additional system-boundary tests execute printf/sleep without shell evaluation, preserving literal metacharacters and exercising output-limit/timeout errors. Missing tools, mismatched versions, out-of-root output and unknown output forms fail closed. The synchronous runner uses Process executableURL/arguments, nonblocking pipe draining, a five-second deadline, 64 KiB combined output cap, null stdin and an allowlisted environment. It runs from a bounded background operation in native composition. The current native path never runs it because no build is qualified. Direct-child termination does not establish whole-descendant-process cancellation; subprocess-spawning behavior must be qualified before any released build can use it.

## Primary evidence and limits

[Official Homebrew manpage](https://docs.brew.sh/Manpage) documents cleanup --dry-run as a removal preview, --prefix/--cache configuration queries, HOMEBREW_NO_AUTO_UPDATE and HOMEBREW_NO_ANALYTICS. The runner additionally disables Bootsnap, automatic install cleanup/autoremove and sudo through documented environment controls. These flags reduce incidental behavior; they do not independently prove all startup/runtime writes are absent.

[Homebrew Cleanup source documentation](https://docs.brew.sh/rubydoc/Homebrew/Cleanup.html) shows dry-run output paths and guards around some write behavior; it explicitly labels the implementation private and unstable. Thus human-readable strings cannot be treated as a stable machine schema. This implementation's `Would free:` line is deliberately fixture-only and is **not asserted to be Homebrew's released summary format**. Estimates remain tool-reported strings, never promised reclaimed bytes or approval identities.

Before qualifying a build: use an existing separately provisioned disposable Homebrew installation; record exact version/build, binary/script provenance, architecture, configured prefix/cache and environment; inspect source/runtime semantics for all invoked commands; verify a complete before/after disposable tree including logs, cache DB, lockfiles and package sentinels; exercise timeout, spawned child, output changes and failed roots. Define an exact versioned parser/command contract and show actual configured roots. Any unknown semantics remain guidance. No real personal Homebrew installation was invoked during this ticket.

Downstream #23 must separately validate mutation boundaries, exact target approval and permanent consequences. This preview cannot authorize cleanup.

Observed implementation checks: 16 merged StillCore tests passed after integrating partial-coverage scanner work; native app build passed. One native UI smoke exercised future Overview → Homebrew → synthetic example → Back, retaining window geometry. No executable picker or real tool was invoked by that UI test. The runner's deadline begins after Process.run returns; OS launch stalls and descendant process cleanup remain additional qualification limits.

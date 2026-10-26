# Chrome native process diagnostic — bounded result

The controlled exited-child experiment passes. It does **not** reproduce the proposed zombie false-unknown hypothesis, and no production process policy was changed.

## Source-bound observations

[Dedicated run 40267931766](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40267931766) at `f8cdbd98f3d9a5c2f756500bbd185e419ce810e9` passed the public `NativeChromeCacheEnvironment.browserIsRunning` check while an owned `/usr/bin/true` child was exited and deliberately unreaped. Swift forbids fork, so the fixture uses supported `posix_spawn` and establishes the exited/unreaped condition with `waitid(WEXITED|WNOWAIT)` before calling the public boundary. No browser or personal profile is opened.

The [original hosted log](chrome-cleanup/f8cdbd9/chrome-native-process.log) records child PID 7740, matching wait PID 7740, wait event code 1 (`CLD_EXITED`), `proc_pidinfo` result 0 versus expected 136 bytes, and `proc_pidpath` result 0. Parent/UID/state fields printed as 0 are **unpopulated** because the BSD-info read failed; they do not identify a root-owned process or establish a kernel process state. The existing Native policy correctly skips this unavailable/dead entry and returns false.

The earlier run 40267672850 at fea04ad failed **test setup**, because it incorrectly required libproc to expose `SZOMB` for the exited entry. That run never reached the public Native call and is not a production behavior regression. The corrected observation above supersedes that assumption.

## Correctly refused repeat

The [f40723c report](chrome-cleanup/f40723c/report.json) and [vendor provenance](chrome-cleanup/f40723c/provision.json) preserve the later failed repeat at [run 40266863569](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40266863569). Default completed actual Swift cache cleanup and protected-state checks. Profile 1 then stopped before cleanup with an unidentified current-user process; its final refusal reports removed 0. This is an honest fail-closed Unknown result, not evidence of protected-data damage or a demonstrated zombie bug.

That repeat also records actual fixture-only crash-database containment and exact owned-helper teardown. The harness sets source-supported `BREAKPAD_DUMP_LOCATION` only for its spawned disposable browsers, verifies new PID/UID/start/executable/exact synthetic database association, and may SIGTERM only those proven fixture helpers after normal browser closure. It never grants the application termination authority, ignores an unknown live process, or establishes that ordinary production Quit always stops every helper.

## Containment and evidence limits

This global process observation is a manually opted-in diagnostic experiment, not a deterministic normal Core regression under arbitrary helper churn. It requires **all** of `STILL_CHROME_PROCESS_PROBE=1`, `GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=github-hosted`. Only the dedicated `chrome-native-process-only` workflow step sets the opt-in. Normal Core CI and local tests skip the experiment. Child cleanup treats ECHILD as already reaped, makes only bounded reap attempts, and never signals an uncertain PID.

Runner-only Unknown diagnostics retain PID/parentPID/UID/raw status/pathLookupFailed observations **after** refusal, without arguments or paths; they do not promise to capture the exact earlier failing PID.

All three production Chrome Core source files remain unchanged from the fully successful two-profile and headed Swift qualification at 23e2219. That positive evidence remains source-equivalent; a safely refused repeat does not require repeated broad qualification until green. This diagnostic adds no compatibility, personal-file authority, automatic retry or production-policy relaxation. Final app/UI qualification is recorded separately.

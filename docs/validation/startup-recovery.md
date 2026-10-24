# Interrupted cleanup recovery — #12

October 22, 2026. Recovery reads durable local journal facts after relaunch. It does not invoke an executor, restore a plan, request file access, inspect original paths or search Trash. A recorded outcome is historical evidence; current file location is separate and unverified.

## State contract

`CleanupRecoverySnapshot` groups interrupted batches through the public journal `records()` boundary. Pending targets are known not started because no operation intent was committed. Intent and unknown states remain unresolved regardless of whether an original exists. Recorded succeeded/failed/skipped/cancelled outcomes remain distinct, including terminal outcomes alongside interrupted targets in the same batch. Completed-only batches belong to history rather than a startup interruption prompt. No record state is rewritten by reading recovery.

The app reads its existing SQLite journal off MainActor at startup; the explicit History recovery route refreshes that presentation from durable records. `SQLiteCleanupJournal(url:readOnly:true)` uses SQLite READONLY/NOFOLLOW and skips schema creation, chmod and durability-setting writes; its mutation methods reject calls. A missing journal creates nothing and leaves Overview available. Unreadable, corrupt or unsupported storage presents blocked recovery instead of an empty successful result. SQLite may use its normal read/WAL locking machinery; read-only here means no cleanup records or schema are modified.

Interrupted records open a secondary read-only review on startup; Overview retains a route back. The review uses shared native headers, summary/settings/status rows and a fixed Return to Overview action. Another cleanup begins through the existing manual scan, selection and new approval flow. Recorded resulting locations are shown only when actually persisted; Reveal is an explicit Finder action for recorded successes, with unverified-location wording. There is no guessed Trash path, broad Trash lookup, automatic retry or universal Undo.

The cached startup snapshot is presentation state, not reset/retention authority. History clearing/reset reads current durable records again, preserves unresolved records and honors active-operation guards. Aggregate growth storage remains independent.

## Owned crash-injection evidence

Build/run the isolated harness:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c release --package-path Validation/RecoveryProbe RecoveryProbe --run
```

The parent creates one disposable root per run. Child processes use actual `TrashExecutor`, the actual SQLite journal and public journal/operation adapters. Each child is killed with SIGKILL at a selected boundary, bypassing ordinary Swift cleanup/SQLite close. The parent reopens the actual database read-only and reads recovery twice, verifying source/holding bytes remain unchanged. The operation adapter renames its own file into its own holding directory; it does **not** call native Trash or inspect personal files.

| Interruption boundary | Reopened durable state | Recovery |
|---|---|---|
| Before batch claim | No target records | No interrupted batch |
| After committed claim, before intent | Pending | Not started; no automatic execution |
| After durable intent, before operation | Intent | Unresolved, original still present |
| After owned rename, before outcome | Intent | Unresolved even though original is missing |
| After committed outcome | Succeeded | Recorded terminal outcome, no interruption prompt |

All five actual SIGKILL boundaries passed on macOS 27.0.1. [Raw report](benchmarks/recovery-sigkill.json) records signal 9, persisted states and unchanged repeated recovery. The first harness draft used `_exit` immediately after requesting self-SIGKILL and observed normal exit status 71 before signal delivery; it was corrected to wait for actual termination, and only signal-9 runs qualify this report. This is process-crash/WAL-reopen evidence, **not power-loss or genuine native Trash qualification**; #9 separately records native Trash checks.

## Tests and native evidence

75 StillCore tests passed at this checkpoint, including reopened missing-original intent, mixed known/pending/unresolved outcomes, replay rejection, read-only mutation rejection/no creation, corrupt-database failure and no recovery authority from ordinary session-only choices. Public tests observe journal results and owned files, not private table shapes.

Native build-for-testing passed. **3/3 focused native journeys passed** (38.42 seconds): initial/minimum startup review in both appearances; known success/failure versus unresolved/not-started evidence; fixed return action and stable window bounds; relaunch retaining unresolved records; an empty session plan after return; missing/corrupt journal and mismatched state-root binding failing closed. Owned holding bytes and persisted states stay unchanged. These tests use only identity-bound disposable app state described in [development instructions](../DEVELOPMENT.md); they never seed the normal app journal.

Actually inspected [initial Light](../visual/recovery/recovery-Light.png), [initial Dark](../visual/recovery/recovery-Dark.png), [minimum Light](../visual/recovery/recovery-minimum-Light.png) and [minimum Dark](../visual/recovery/recovery-minimum-Dark.png) native captures. Shared hierarchy, white light sidebar, wrapped owned paths, distinct recorded evidence and fixed return action remain readable at 1120×760 and 900×640. The four seeded records are explicitly disposable fixture facts, not claims of real cleanup.

Remaining manual gates include real power loss, damaged storage/WAL recovery, OS permissions, Finder integration, VoiceOver, Increased Contrast, localization and deployment-target compatibility. The existing records() API reads all durable records; pagination/bounded history management belongs to the following history work and must never silently truncate unresolved records. No personal Trash scan or target metadata inspection occurs at startup.

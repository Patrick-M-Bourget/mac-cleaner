# Genuine Swift/package/custom-output session (#16)

October 23, 2026. **Experiment passed; production Xcode cleanup remains
unsupported.** This extends the previous minimal C experiment with an actual
Swift target, local Swift package, custom build outputs, native descendant
observations and a real process-crash journal boundary. It does not implement
#17, a parallel production executor, a general build lock or app recovery.

## Reproduce

```sh
python3 Validation/XcodeProbe/NativeExperiment/test_swift_contract.py
```

The public command test invokes `swift_session.py` with no arguments. The script
accepts no external root/project. It requires exactly Xcode 27.1 build 27A9275 and
1 GiB temporary free space, sets DEVELOPER_DIR only in child environments, creates
a new private 0700 `StillXcodeSwift-*` root and generates all sources/project/
package files there. No remote package, script phase, dependency installation,
signing account, product execution or personal Xcode/default DerivedData access
is involved. Xcode's normal shared build services can run; the output root is not
a sandbox for arbitrary build scripts, which this fixture deliberately lacks.

Every build/archive/rebuild has a 120-second cooperative process deadline;
build-settings observation has 30 seconds, `ps` observations five seconds and
owned-child termination ten seconds. It never kills by process name, signals
shared services, removes build locks or changes global developer selection.
Failures or uncertain owned-process shutdown preserve the root rather than
traversing a possibly active tree. The synthetic writer is tracked in the same
owned-process collection as the builds. Successful completion removes only the
freshly created fixture tree.

The one public command test first failed because `swift_session.py` was absent.
The first genuine implementation then built the Swift package/custom outputs,
but an archive using the same OBJROOT/SYMROOT overrides failed Xcode's native
`BuildProductsPath` lookup. [Recorded initial failure](swift-session-initial-failure.json)
retains the exact native error and explains that the early harness did not retain
its complete temporary log. The refinement does not fabricate a missing Xcode
directory: its successful archive uses a separate explicit owned DerivedData and
normal archive output layout. Those two configurations are not conflated.

## Actual native result

[Observed report](swift-session-evidence.json), macOS 27.0.1 arm64:

- Actual Swift/local-package build succeeded in **3.596 seconds**; archive in
  **2.828 seconds**; rebuild in **1.765 seconds**. Full public command test passed
  in **10.221 seconds**. Only this host/toolchain is qualified as an experiment.
- `xcodebuild -showBuildSettings -json` confirmed custom OBJROOT/SYMROOT. Three
  compiler-generated regular objects totaling **16,192 logical bytes** appeared
  in custom intermediates: package `OwnedSupport.o`, target `helper.o`, `main.o`.
  No allocation, exclusive released space or general path-classifier claim follows.
- Repeated process observations retained only descendants of the exact owned
  xcodebuild child. Actual observations included **SWBBuildService, swift-driver,
  swift-frontend, clang, ld and dsymutil**. Transient parenthesized names are the
  process metadata returned by `ps`; they are not persistent identities or locks.
  Other process rows were not retained. Seeing these children does not prove the
  absence, identity or inactivity of other GUI/shared/future build owners.
- A separate owned Python writer created a synthetic new `.o` after review and
  stayed active. The experimental operation refused while that known writer was
  active. After its successful exit, the original exact manifest omitted the new
  file. This is real tracked-process rejection and late-discovery preservation,
  not a native compiler-race or general external-writer detector.
- The first experiment operation persisted an exact intent, removed one approved
  object, persisted its outcome and recorded cancellation with two unstarted
  original targets. It deliberately attempts no further work in that operation.
  **This is a cancellation scenario, not an application cancellation implementation.**
- A separate experiment operation freshly fingerprinted one remaining original
  object. Its forked child fsynced intent, unlinked that exact leaf and terminated
  itself with actual **SIGKILL (9)** before outcome recording. It accepted no
  caller-supplied worker root. Parent wait status proves signal termination.
- Read-only journal observation derived unresolved `(operation, target)` pairs
  from persisted intents minus recorded outcomes, independently read the cancelled
  unstarted targets, and left journal bytes unchanged. An absent target did not
  manufacture success or replay. [The report](swift-session-evidence.json) includes
  actual relative-target journal records and unresolved pairs. This establishes
  **process-crash observation**, not power-loss durability, an application journal
  schema, authoritative retry approval or integration with app recovery.
- Six source/project/package files, six actual archive files and three actual
  product-dSYM files had identical before/after SHA-256 maps around the two exact
  removals. The owned source/archive hashes also stayed unchanged across rebuild;
  regenerated product symbols can naturally change. The removed genuine objects
  reappeared after a real successful rebuild. The late synthetic discovery remained
  unselected. No compiled fixture product was executed.

## Enforceable capability/action contract

| Context | Decision and evidence |
|---|---|
| This fresh private experiment root, exact known recipe, successful tracked builders/writer exit, actual settings mapping and exact current manifest | Experimental exact-leaf removal only; parent directories opened without following links, target owner/type/link count/device/inode/size/mtime/ctime rechecked. Durable event scenario surrounds each operation |
| Known tracked build/writer still running, missing successful completion, unsupported artifact or changed/unavailable identity | Refuse/skip. Do not remove locks, terminate an owner to unlock cleanup, add new discoveries or replace approved targets |
| An arbitrary user project, default/custom DerivedData, GUI Xcode or shared/unidentified helper ownership | **Production unsupported.** Own-child completion and process snapshots cannot establish exclusive ownership or exclude a new writer |
| Final stat-to-unlink name swap or concurrent writer after observation | Not atomically excluded. Descriptor-relative ancestry reduces scope but is not proof of a race-free production action |
| Intent without a recorded terminal outcome after crash | Unresolved observation only; no inferred success, replay, restored approval or automatic retry |

The app must retain guidance whenever general owner/layout/exclusive-access
preconditions cannot be established. A user assertion that Xcode is closed, an
ownerInactive boolean or this passing experiment cannot confer production
mutation authority. There is no new supported production version/root allowlist
and no change to M1 Downloads-only cleanup.

The remaining #16 gate is a genuine owner coordination/isolation contract that
covers GUI Xcode, shared SWBBuildService/XCBBuildService, independent build tools,
new writers and final mutation races, plus the claimed real configurations.
The current observations **do not establish that contract**. If it cannot be
established safely for ordinary installed projects, #17 must remain guidance;
none of its preserved permanent-cleanup, shared-plan, consequence, cancellation,
results or durable recovery requirements is silently removed. Additional project
plugins/scripts, package dependencies, hard links, access/volume cases, OS/CPU
matrix and real application-journal integration also remain unqualified.

[Source/evidence hashes](swift-session-manifest.json) bind the successful local
experiment to its exact scripts and unmodified report. Protected hashes cover
only generated disposable fixtures; no personal code or symbol content was read.

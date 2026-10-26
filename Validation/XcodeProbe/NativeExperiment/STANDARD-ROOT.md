# Hosted standard-root mapping delta — #16

This new discovery run answers the missing default DerivedData/project-association question. It reuses the existing owned C recipe; it does not repeat previous archive, Swift/custom-output or crash experiments. **No production configuration is qualified by this harness alone.**

Dispatch the existing `native.yml` workflow with suite `xcode-standard` on the reviewed branch. It selects Xcode26.6 on fresh hosted macOS26 and invokes:

```sh
python3 Validation/XcodeProbe/NativeExperiment/standard_root.py --output "$RUNNER_TEMP/xcode-standard-evidence"
```

The command refuses outside GitHub-hosted macOS before default-root or process inspection. It requires absent standard DerivedData and Xcode preferences before generating a private no-script/no-remote C project. It supplies no derivedDataPath/OBJROOT/SYMROOT overrides and makes no preference changes. The actual toolchain/OS/source/run, invocation, original build/settings output, native plist metadata, generated leaf identities and captured owned-descendant lifetime observations are retained in `xcode-standard-evidence`.

`WorkspacePath` is a candidate observed key, not a documented public schema. Missing or different metadata is retained as a concrete unsuccessful mapping result; no inferred basename fallback exists. Build settings are queried only for the generated owned project as independent qualification evidence. Production discovery must not execute arbitrary user projects to obtain settings.

No generated artifact or source is deleted, no helper is signaled and no lock removed. Output trees remain for hosted runner disposal. Only descendants of the exact owned build are retained from hosted process observations; post-build rows observe previously captured PIDs and do not establish a general inactivity guarantee. PID reuse can make these observations ambiguous; they never authorize mutation. A deadline preserves the fixture, with the workflow timeout controlling runner disposal.

Local syntax compilation passed; an actual local invocation refused immediately with `Fresh GitHub-hosted macOS runner required`. Native mapping remains unobserved until the workflow runs. Following actual schema evidence, remaining public Core and native owner checks must pass before #16 enables #17.

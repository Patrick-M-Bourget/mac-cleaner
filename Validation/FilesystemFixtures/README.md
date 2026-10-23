# Genuine owned-volume scanner fixtures

This opt-in qualification harness exercises the public `FolderScanner.scan` seam against a genuine mounted HFS+ image. It is not app functionality and is not part of ordinary package tests. It refuses to provision images unless both GitHub Actions and its `github-hosted` runner environment are declared. Do not bypass that guard on a personal Mac or persistent runner.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --package-path Validation/FilesystemFixtures
python3 Validation/FilesystemFixtures/run.py --ci-owned-images --executable Validation/FilesystemFixtures/.build/release/FilesystemFixtures --reports "$RUNNER_TEMP/filesystem-fixture-reports"
```

The Python orchestrator creates a private UUID temporary directory, requires 512 MiB free headroom and creates one 64 MiB HFS+ image. It requests an exact mountpoint beneath its root with no Finder browsing or auto-open. It saves the returned attach plist, obtains the device only from its exact mounted entity, and independently checks `hdiutil info -plist` associates that device with its owned image. Native `st_dev` must differ between parent and mounted scope. It creates only a known 17-byte sentinel and a 1 MiB repeated-byte compression source, and copies the latter onto the mounted volume with system `ditto --hfsCompression`.

The Swift executable observes public scan results:

- Scanning the parent reports `.differentVolume`, descends into no mounted descendants and exposes unknown complete totals.
- Explicitly scanning the owned mounted subfolder observes the known sentinel.
- The compressed candidate preserves its known 1 MiB logical length. Qualification requires actual native `UF_COMPRESSED` and a known smaller allocated length. If the filesystem/tool declines compression, the report explicitly says unsupported; an ordinary file is never labeled positively compressed.
- After the orchestrator detaches the exact verified device, the former subfolder is unavailable and reports no complete total. This covers disconnected scope recheck, not removal during an in-flight provider call.

`finally` handles ordinary failures and SIGINT/SIGTERM by revalidating the exact image/device mapping before a normal non-forced detach. It removes the owned root only after confirmed detach and an unmounted mountpoint. Unknown mappings, ambiguous attach results, timeouts and detach failures preserve the root rather than guessing a device or recursively traversing a possible mount. SIGKILL/runner termination cannot guarantee cleanup; ephemeral runner disposal is the final boundary. No elevation, real-volume changes, user storage, cloud content, Finder launch or OS preference changes are used. HFS+ coverage does not certify every APFS/external/provider behavior.

Artifacts: `attach.plist`, `mounted.json`, `unmounted.json`, and `lifecycle.json`. A zero exit status alone does **not** certify positive compression: inspect the `compression` field, and verify `detached` and `ownedRootRemoved`. Failed processes leave lifecycle diagnostics and fail the job. Runtime reports must be linked to their exact source/run before closing any qualification gate.

## Research and local validation

Apple's installed `/usr/share/man/man1/hdiutil.1` documents machine-readable `-plist`, exact `-mountpoint`, `-nobrowse`, `-noautoopen` and normal device detach. Apple's installed `/usr/share/man/man1/ditto.1` documents compression only when appropriate on supporting HFS+/APFS filesystems. Those manuals were read on macOS 27.0.1; their original bytes and SHA-256 hashes are retained in the external task notes. [Apple's published stat header](https://github.com/apple/darwin-xnu/blob/main/bsd/sys/stat.h) defines `UF_COMPRESSED` and the 512-byte `stat` block unit. Neither `st_blocks` nor allocation observations are exclusive reclaimable-byte claims.

Local Debug compilation with Xcode 27.1 passed, and the orchestrator's personal-host refusal was verified before any root/report directory or image could be created. No image creation, attachment, compression or detachment has run on the personal host. Hosted runtime qualification is pending; this implementation does not close #34's genuine-volume or compression gates by itself. Existing reference 512 GB hardware, cloud non-hydration and non-returning-provider gates remain open.

The first hosted attempt ([40002281606](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40002281606), source `c522750`) failed before image creation: blank image creation does not accept `-format UDRW` on Xcode 26.6/macOS 26.6.2. Its lifecycle report confirms the owned temporary root was removed and no attach occurred. The corrected command uses `-type UDIF`, Apple's documented blank read/write image type; `-format` is for images populated from a source folder/device. `hdiutil create -help` and the installed manual were checked without creating or attaching an image locally. This changes fixture provisioning only, with scanner assertions and device verification unchanged. The exact mounted `/dev/diskNs…` node returned by attach remains the normal detach target, as the manual accepts a device node or mountpoint and detaches its associated image through Disk Arbitration; its image association is revalidated immediately before detach.

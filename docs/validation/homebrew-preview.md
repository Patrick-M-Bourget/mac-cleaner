# Homebrew cache-only qualification — #22

## Current contract

The future-gated secondary page now inspects a real explicitly selected cache with a narrowly supported tool-source contract. It is no longer only an unexecuted-executable scaffold. No cleanup or full `brew cleanup` preview is qualified. The older synthetic vendor-output example remains clearly separate.

Support: official Homebrew **4.6.17**, immutable source commit **aa278895809b4c079e560fb4fb9bf17e48cf65f1**. Verify four complete source-file SHA-256 digests before cache traversal; only these verified bytes are privately staged. Apple `/bin/bash -p` invokes staged `brew.sh` with exactly `--prefix` and `--cache`. These shell fast paths source only pinned `help.sh` / `formula_path.sh` and exit before wrapper loading, Git or Ruby. Installed `bin/brew` is checked for provenance and never invoked. Installed sources may change after reading without changing the staged verified bytes.

The prefix derives from explicitly chosen `bin/brew` layout. Cache is explicitly chosen and passed as `HOMEBREW_CACHE`; the query confirms that override, not discovery of the user's configured cache. `HOME`, temporary paths and source library point to private staging. No `brew.env`, shell startup, formula/tap, package Ruby, install, update or network operation is used by the application. No global installation or personal package/cache was inspected during qualification.

| Official file | SHA-256 |
|---|---|
| `bin/brew` | `5486710858db51927d4ec84ae0a4952da3e132c55cc12bad76ae8f1c18c9fb00` |
| `Library/Homebrew/brew.sh` | `cdb88f545ad22a68862c28153c4f91b79d9d0778c03442c7bcdfe5ab3c2bd84c` |
| `Library/Homebrew/help.sh` | `1dd0d74bb55ca636bff19b74e0c54710c61c114791b22b9fce3280394a33e38e` |
| `Library/Homebrew/formula_path.sh` | `87c5c6c9e751769c5fa7a208fecb811c18405e52515d7ee7a893b95e0e815212` |

## Useful evidence and limits

Report observed regular/download-file counts, top-level incomplete-download names and logical/allocated totals. Hardlink identities deduplicate byte totals while directory entries remain counted separately. Cache links, dataless entries, cross-volume traversal, metadata errors, changing root identity/mtime, overflow or bounds produce partial coverage with unknown totals. Bounds: 100,000 entries, depth64, cooperative five-second enumeration; blocking OS calls must still return. Keep at most100 incomplete names and show20; incomplete count includes all observed entries. Names may belong to active downloads. Chosen folder ownership, nested-directory consistency, atomic snapshot semantics and exclusively reclaimable space are not established. No contents of cache files are read. No cleanup approval is produced.

## Genuine disposable installation

Qualification provisioning, outside application behavior, downloaded official tag4.6.17 and official portable Ruby3.4.5 arm64 bottle into an owned notes directory. The Ruby archive digest matched the upstream vendor pin `20fa657858e44a4b39171d6e4111f8a9716eb62a78ebbd1491d94f90bb7b830a`. The Git tag resolves to the immutable commit above. No `/opt/homebrew`, `/usr/local`, shell settings, services, elevation or personal package state was changed.

Actual vendor commands `--version`, `--prefix`, `--cache`, `cleanup --dry-run --prune=all` returned Homebrew4.6.17, owned configured roots and a27-byte `obsolete.incomplete` candidate. Its actual final line was “This operation would free approximately 27B of disk space.” The existing fixture-only `Would free:` parser is not a parser for this released vendor format.

A warm-source snapshot excluding `.git` showed no changes, which does **not** qualify unchanged installation state. A separate cold probe includes Git state and demonstrates that ordinary `--version` creates `.git/describe-cache` and a version file. Source inspection also shows cleanup loading mutable formula/cask code. Consequently production does not invoke those commands. Narrow staged shell fast paths need neither Ruby nor Git and cannot reach those branches with the exact allowlisted arguments. Full vendor preview/mutation #23 remains gated rather than pretending the warm probe established broad safety.

## Reproduction and test boundary

Provision the official source in an owned directory, then run:

```sh
STILL_HOMEBREW_PROBE_ROOT=/absolute/owned/brew-4.6.17 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/StillCore --filter Homebrew
```

The genuine public-boundary test creates a separate owned cache with independent27-byte incomplete and101-byte current-file sentinels. It verifies pinned source support, echoed cache override, two files/128 logical bytes, one27-byte incomplete observation, unknown reclaimable bytes and unchanged content. This test is explicitly disabled unless the owned source path is supplied; routine CI must not be described as having run genuine qualification when it skipped. Arbitrary executable-name/code rejection runs unconditionally and proves no execution marker appears. Existing fixture parser/timeout tests remain synthetic system-boundary checks, not real Homebrew qualification.

Red: missing public `inspectSelected` API failed compilation. Green: the genuine test exposed and fixed Foundation `/var` versus enumerator `/private/var` relative-path normalization before passing. No private source content or personal paths are in repository evidence.

Native test `StorageAlertsUITests/testSelectedHomebrewCacheInventoryIsReadOnlyAcrossThemesAndSizes` provisions four immutable official shell files in its own runner temporary scope with20-second request timeouts; the app never downloads sources. A Debug-only preload checks exact canonical temporary parent, UUID, owner and device/inode, then the actual Inspector verifies source hashes and runs the real staged-shell/cache pipeline after explicit Inspect. It captures selected and inventory states in both themes and initial/minimum sizes, with unchanged window and sentinels. Hosted results/captures require their own source-pinned root review before visual acceptance; local build is not a native runtime pass.

## Primary sources

- [Pinned brew entry point](https://github.com/Homebrew/brew/blob/aa278895809b4c079e560fb4fb9bf17e48cf65f1/bin/brew): environment-file/configuration behavior.
- [Pinned shell dispatch](https://github.com/Homebrew/brew/blob/aa278895809b4c079e560fb4fb9bf17e48cf65f1/Library/Homebrew/brew.sh): fast-path source dependencies, early returns and Git describe-cache writes.
- [Pinned cleanup implementation](https://github.com/Homebrew/brew/blob/aa278895809b4c079e560fb4fb9bf17e48cf65f1/Library/Homebrew/cleanup.rb): incomplete entries, formula/cask loading and dry-run output.
- [Pinned portable Ruby provenance](https://github.com/Homebrew/brew/blob/aa278895809b4c079e560fb4fb9bf17e48cf65f1/Library/Homebrew/vendor/portable-ruby-arm64-darwin): separately provisioned test runtime archive digest.

[Redacted genuine cold-probe evidence](homebrew-disposable-evidence.json) preserves actual command arguments, exit codes, output, source/runtime archive digests and changed relative paths. `$OWNED` replaces only the owned test root. The application uses neither the Ruby archive nor these vendor dry-run commands. Local qualification: eight focused Homebrew/system-boundary tests pass, including the explicitly enabled genuine source/cache case, hardlink byte deduplication and partial totals for a skipped symlink; native build-for-testing passes on Xcode27.1/macOS27 arm64. Hosted visual/runtime acceptance is recorded separately by the integration review.

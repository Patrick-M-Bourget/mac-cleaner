# Release archives #54 — bounded implementation evidence

Application source `62bcf8a`; contract [RELEASE-ARCHIVES](../RELEASE-ARCHIVES.md), Q1–Q7. Release archives is guidance-only inside existing M6-gated App-managed storage. Device backups remains the default; no archive picker, discovery, metadata read, traversal, cleanup target or estimate is available.

## Public behavior

- Core actual red: the existing public inventory did not contain Release archives. Final full Core run passes160 Swift Testing +5 XCTest; focused protected no-read sentinel and launcher checks pass2/2. Logs: `/tmp/archive54-core-red.log`, `/tmp/archive54-core-final.log`, `/tmp/archive54-core-archive-final.log`.
- Native actual red [40233632122](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40233632122) at test source `97533a5` fails at the missing Release archives button at both sizes.
- Live green [40233760437](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40233760437) at `e17a49e` passes two composed public journeys: initial and minimum, each in Light/Dark, explicit unavailable-Xcode action/status, no archive picker, existing Device backups inspection route, stable outer bounds and Back to Overview/re-entry. Production source is unchanged from `62bcf8a`.
- Final combined [40234083631](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40234083631) at test-only `2f2f735` passes2/2 composed journeys (59.155s/51.780s), adding the same shared inert Gallery component in both themes/sizes. No production source changed.
- Independent Spec and Standards source reviews report no actionable blockers; original reports are retained with visual evidence.

## Visual review

Root individually reviewed all8 live originals from40233760437, then all12 final originals from40234083631 (8 live +4 Gallery). At1024×640 and900×640, protection, unknown amount, instructions, retention copy, actions and inline failure are readable in Light/Dark. Dark guidance captures intentionally retain the preceding Light launch-failure status; they are not pristine no-error states. The upper category list/header is above the retained scroll position and is not visually certified by those images; source/public journey checks cover category/default behavior.

All12 final originals are accepted. [Per-image review](../visual/release-archives/REVIEW.md), full unmodified manifest and original PNG files are retained alongside both independent source review reports. The Gallery component is readable in both themes/sizes. No composite, resized substitute or offscreen content is claimed as visual evidence.

## Limits and review build

Launcher failure uses the existing DEBUG controlled system boundary; Core also checks requested Xcode bundle identity and outcome. This does not certify every installed Xcode version, genuine native opening, menu path on every supported OS, TCC or commercial distribution. Broader #31 owner-app/platform qualification remains open. M6 gating, #17 generated-data cleanup and M8 deferral remain unchanged.

Local Xcode27.1 build-for-testing and ad-hoc deep/strict signature pass. Review app: `/Users/bender/Library/Caches/Codex/mac-cleaner-implementation/artifacts/archives-62bcf8a/Still.app`, BUILD.md alongside; executable SHA256 `5047b04a46c0633ae339913b57ede07bbed022c8602e888201c89a073b08ab63`. Launch explicitly with `--future-milestones`, then Overview → More tools → Review app-managed storage → Release archives. Ordinary launch retains existing gates. This is an arm64 development build, not a notarized release.

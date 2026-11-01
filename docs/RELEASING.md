# Preparing a local release

Version preparation and release building are separate owner-run commands. Neither publishes anything.

```sh
scripts/release.sh --bump 0.10.0
git diff -- CacheDrop/CacheDrop.xcodeproj/project.pbxproj
# Review and commit the version/build edits, then build from the clean checkout.
```

Preparation requires a stable, increasing `x.y.z` version and increments the shared build number. It changes only the app's version/build settings. Commit or stash existing project-file edits first. Unrelated changes are preserved; the later release build requires the whole checkout to be clean and exports committed HEAD.

## Sparkle prerequisite setup

The app embeds **Sparkle 2.10.1**, pinned exactly in the Xcode project and Package.resolved. **Check for Updates…** in the app menu and Settings creates the shared updater when first used. Scheduled checks, automatic downloads and installations, permission prompts and system profiling are disabled. Approved installation waits for active cleanup and maintenance to finish, stops scans and awaits saved results; **Cancel update** restores availability before handoff. `CacheDrop/UpdateInfo.plist` contains the public EdDSA key, canonical feed URL, and disabled automatic-update/profiling defaults. Only the public key belongs in source. The matching private key stays in the owner's login Keychain, Sparkle account `ed25519`.

Use the tools from the matching official distribution:

```sh
mkdir -p .build/sparkle-tools
gh release download 2.10.1 --repo sparkle-project/Sparkle \
  --pattern Sparkle-2.10.1.tar.xz --dir .build/sparkle-tools
shasum -a 256 .build/sparkle-tools/Sparkle-2.10.1.tar.xz
# Expected SHA-256: 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
tar -xJf .build/sparkle-tools/Sparkle-2.10.1.tar.xz -C .build/sparkle-tools
.build/sparkle-tools/bin/generate_keys -p
```

`generate_keys -p` looks up only the existing public key. If setting up a new owner's installation without a key, run `generate_keys` once to generate one directly in Keychain, then review and commit its public key to `CacheDrop/UpdateInfo.plist`. Do not generate a replacement for an existing distribution key. Do not export the private key, pass it on a command line, or put it in an environment variable. Release tooling accepts a Keychain account only. A missing key or a public-key mismatch fails before building.

Signed builds also require a valid **Developer ID Application** identity for team **8F5K2ZRP5T**, and the `cachedrop-notary` notarytool Keychain profile. Bundle identity remains **com.patrickbourget.CacheDrop**.

## Build and verify

Write the version's notes as `docs/releases/x.y.z.html` (content only, in the shape Decision 122 sets; `docs/releases/notes.css` is the shared style), then build the file to sign with `scripts/release-notes.py x.y.z --out .build/release-notes/x.y.z.html` and pass that path as `--release-notes`. Supply a versioned, immutable HTTPS artifact directory explicitly. Production publication will use the public Supabase updates bucket; its actual URL must be configured by the owner. Do not use the private website download URL or GitHub Releases as the enclosure URL. For acceptance, supply a separate test bucket/path and retain the resulting local feed separately. No production upload, website update, feed promotion or deployment occurs here.

```sh
scripts/release.sh \
  --sparkle-tools "$PWD/.build/sparkle-tools/bin" \
  --artifact-base-url 'https://YOUR-TEST-HOST/isolated-updates/0.10.0/' \
  --release-notes /absolute/path/to/reviewed-0.10.0.html
```

The command exports HEAD, builds Release, signs every Sparkle helper (Installer, Downloader with its entitlements preserved, Autoupdate, Updater), then the framework and app. It verifies each nested Mach-O's signature, Hardened Runtime, Developer ID team, and absence of development entitlements. It notarizes/staples the app, creates/signs/notarizes/staples `CacheDrop-x.y.z.dmg`, and only then EdDSA-signs the final DMG. Sparkle's generator creates a local full-update-only appcast with embedded reviewed notes. A separate signature verification and metadata check must pass before metadata is saved. No subsequent step changes the signed DMG bytes.

Outputs in `build/release/`:

- `CacheDrop.app` and `CacheDrop-x.y.z.dmg`: the verified app and full update archive.
- `appcast.xml` and `CacheDrop-x.y.z.html`: the local feed and reviewed notes.
- `release-identity.json`: full source commit, bundle/team, marketing/build versions, exact DMG URL, size, SHA-256, public key, EdDSA signature and notes SHA-256 for later immutable staging.

Keep this output set together. Before staging, independently repeat verification (substitute the actual version and original reviewed notes path):

```sh
scripts/sign-release-app.sh --verify build/release/CacheDrop.app - 8F5K2ZRP5T
spctl -a -t exec -vv build/release/CacheDrop.app
spctl -a -t open --context context:primary-signature -vv build/release/CacheDrop-0.10.0.dmg
xcrun stapler validate build/release/CacheDrop.app
xcrun stapler validate build/release/CacheDrop-0.10.0.dmg
python3 scripts/sparkle-release.py verify \
  --app build/release/CacheDrop.app --dmg build/release/CacheDrop-0.10.0.dmg \
  --tools .build/sparkle-tools/bin \
  --artifact-base-url 'https://YOUR-TEST-HOST/isolated-updates/0.10.0/' \
  --release-notes /absolute/path/to/reviewed-0.10.0.html
```

Use `--keychain-account` on release.sh, or `--account` on sparkle-release.py, if the owner uses a nondefault Sparkle account. Never modify the DMG after signing; a rebuild is a new artifact requiring all checks again. `scripts/release.sh --adhoc` supports local build checks, produces `-adhoc.dmg`, and does not produce a distribution appcast. Automated fixtures and ad-hoc builds do not establish Developer ID/notarization correctness or a real signed A → B update.

Signing order and entitlement handling follow [Sparkle's custom-signing guidance](https://sparkle-project.org/documentation/sandboxing/#code-signing). Feed generation follows [Sparkle's publishing guidance](https://sparkle-project.org/documentation/publishing/).

## License keys

License keys are checked on the Mac against the public key built into the app, with no network call (Decisions 135 and 136; the format is [docs/reference/license-key-format.md](reference/license-key-format.md)). Two things ship in each release, both in `Packages/CacheDropCore/Sources/CacheDropCore/LicenseBuiltIns.swift`:

- **The production public key.** Until the owner supplies it (#593), `LicensePublicKey.productionBase64` holds a placeholder that rejects every key. To supply it, replace `placeholder` there with the 32-byte raw Ed25519 public key in base64 (`productionBase64 = "…"`), and keep the `placeholder` constant itself. Only the public key goes in source; the private key stays with the issuing function's secrets and never enters this repository. `scripts/check-release.sh` refuses a Release app that still has the placeholder once license gating is on (`LICENSE_GATING` in the app's Release Swift conditions, #595).
- **The revocation list.** Before building a release, add the license ID of every key refunded, charged back or leaked since the last one to `LicenseRevocations.ids`, one per line as `UUID(uuidString: "5f0c2a8e-3b1d-4c6f-9a7e-2d4b8c1e6f30")!,` with a comment giving the reason and date (no email or name), then commit. The ID is the lower-case UUID the issuing function recorded for the purchase. IDs are never removed. A revoked key keeps working on a Mac until it installs that release; there is no online check.

## Stage and promote separately

After building, keep the signed DMG, `release-identity.json`, generated `appcast.xml` and reviewed HTML notes together. In the sibling `cachedrop-website` repository, run `scripts/stage-release.sh <dev|prod> DMG release-identity.json` to verify and stage identical bytes in both download destinations. Staging does not advertise a release. Then run `scripts/promote-release.sh <dev|prod> ARTIFACT_DIRECTORY HTTPS_FEED_URL` to verify both destinations, advance website latest, and publish the appcast last. See that repository's `docs/RELEASING.md` for explicit target configuration and retry instructions. Production publication remains a separate owner action.

## Resume updater acceptance (#520)

Use `scripts/updater-acceptance.py` to keep the #510 checklist between sessions. It records operator observations; it does not run acceptance, validate signatures, build artifacts or publish anything. Commit the source under test first: a run pins this checkout's HEAD.

Prepare an ignored JSON file listing every artifact used in the run. Each entry has `identity` (a unique operator label), `path` (a file, relative to the JSON file or absolute), `sha256` (the expected lowercase SHA-256, from its release identity) and `mode` (`Release` or `fixture`). For example, replace the placeholders below with the real paths and hashes:

```json
[
  {"identity":"Release A","path":"A/CacheDrop-0.9.6.dmg","sha256":"<A hash>","mode":"Release"},
  {"identity":"Release B","path":"B/CacheDrop-0.9.7.dmg","sha256":"<B hash>","mode":"Release"}
]
```

```sh
python3 scripts/updater-acceptance.py init --run updater-check --artifacts .build/artifacts.json
python3 scripts/updater-acceptance.py status --run updater-check
# After observing a case; use --result fail for a failure, then record its retry later.
python3 scripts/updater-acceptance.py record --run updater-check --case saved-state \
  --artifact 'Release A' --artifact 'Release B' --result pass --note 'Observed preserved settings and History'
```

The ignored manifest lives at `.build/updater-acceptance/<run>/run.json`. Include fixture artifacts in the initial JSON when needed; each observation retains its selected artifact identities and modes. The required `relaunch` case checks that no cleanup selections or operations are restored. Keep secrets and personal data out of notes. `status` lists pending/failed cases and the next case, returning 1 until every case passes, then 0. Invalid input or a changed source commit/artifact hash returns 2 and refuses reuse: start a new named run. Existing artifact building, signing and distribution commands above remain separate.

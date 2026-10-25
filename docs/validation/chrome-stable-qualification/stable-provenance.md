# #18 Chrome Stable provenance — read-only research

October 25, 2026. No browser downloaded, installed, launched or personal profile inspected.

## Distribution and reproducibility

Google documents a moving **latest Stable** macOS PKG endpoint, not an immutable versioned installer: `https://dl.google.com/chrome/mac/stable/` plus its documented terms-acceptance suffix. The regular consumer installation uses `googlechrome.dmg`. Prefer the official explicitly Stable endpoint for channel provenance; a stable URL means a consistent locator, not fixed bytes. [Official current package instructions](https://support.google.com/chrome/a/answer/9915669?hl=en), [Mac installation instructions](https://support.google.com/chrome/answer/95346?hl=en).

Google explicitly explains that regular versioned Chrome downloads are intentionally unavailable, and presents Chrome for Testing (CfT) as a distinct flavor without auto-update. CfT supplies versioned binaries across channels; `chrome@stable` still selects **CfT**, not the regular consumer Stable application. Therefore existing CfT156.0.8078.47 cannot qualify installed Stable by matching numbers alone. No supported public immutable macOS consumer Stable URL was established in this research; do not invent one or use third-party archives. [CfT rationale](https://developer.chrome.com/docs/automation-and-testing/chrome-for-testing), [test-binary download semantics](https://developer.chrome.com/docs/automation-and-testing/download-test-binaries).

## Identity verification

Chromium's own macOS integrity-check implementation defines Google's Developer ID team **EQHXZ8M8AV**, Apple generic anchor, Developer ID intermediate/leaf certificate markers, and Chrome identifiers. For this probe require the exact regular Stable identifier **com.google.Chrome**, not its beta/dev/canary alternatives. Verify actual signature validity as well as displaying metadata; a printed team string or bundle name alone is insufficient. Retain verification output for application, executable and framework, plus observed certificate/CDHash. The source supports the signing expectation, not a lifetime certificate promise. [Official Chromium source](https://chromium.googlesource.com/chromium/src/+/d586be9fa9b8009487056edccf01555bb18dc3b2/chrome/browser/safe_browsing/incident_reporting/binary_integrity_analyzer_mac.cc).

## Bounded hosted qualification recommendation

On a fresh disposable hosted macOS runner only: fetch from the documented official Stable source, record UTC retrieval time, requested/effective HTTPS URL, response metadata, SHA-256 and artifact size; extract/copy into a temporary probe directory without installing updater services. Record Info.plist identifier/version, architecture, signature-verification output, macOS/build/runner image and explicit synthetic profile root. Fail closed for unexpected identity/signature/version, ambiguous extraction, pre-existing Chrome owner or provenance mismatch. Hash/version-check the tested executable before and after the experiment; preserve the installer or extracted artifact only according to repository artifact policy. A later download changing bytes is a new qualification candidate, never a transparent rerun of the old version.

At research time the [official ChromiumDash Mac Stable JSON](https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Mac&num=1) reported **156.0.8078.48**, previous156.0.8078.47. Save contemporaneous JSON and compare the *actual downloaded application's* version; do not hardcode this transient web observation as the expected future download or infer artifact checksum from it. Google also [directs developers to ChromiumDash for release/channel information](https://developer.chrome.com/docs/web-platform/chrome-release-channels/).

This establishes a provenance procedure only. Stable acquisition and signing cannot establish profile ownership, exclude concurrent owners or close #18's protected-data semantics gate. Those remain separate experimental obligations and the locked stop rule still applies.

Source-link review: the integrity-analyzer file above was fetched at the pinned revision and contains both the Google team requirement and Chrome identifier. This validates the cited source, not any installed binary.

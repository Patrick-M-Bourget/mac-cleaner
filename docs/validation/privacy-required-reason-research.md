# Required-reason privacy API applicability research

Checked October 23, 2026 against current Apple primary documentation; repository base `2aa325f`. Research only: no code, manifest, entitlement, storage location, signing or release qualification changes.

## Finding and superseded interpretation

The earlier [release qualification](release-qualification.md) document treats unresolved C617.1 eligibility for unsandboxed Application Support metadata as a blanket release gate. **This research supersedes that interpretation:** current Apple documentation does not establish required-reason declarations, or resolving C617.1, as a prerequisite for this native macOS app’s direct Developer ID distribution or notarization. Keep the purpose audit and recheck policy for the eventual candidate. This finding does not qualify the current development artifact for distribution or remove its other release gates.

## Documented facts

Apple’s [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) distinguishes two kinds of information: collected-data information applies on all platforms; required-reason API information applies to iOS, iPadOS, tvOS, visionOS and watchOS. macOS is absent from that second platform list. The current Apple-hosted Markdown was fetched to verify this wording independently of indexed search excerpts.

[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) repeats that narrower platform list and describes App Store Connect rejection for missing required-reason declarations beginning May 1, 2024. General statements later in the article must be read with its stated platform scope.

The [required-reason dictionary](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) restricts C617.1 to file metadata inside app, app-group or CloudKit containers. It does not identify arbitrary app-owned directories as containers. The same reference describes 3B52.1 for user-granted file or directory access. Schema availability on macOS is not itself a statement that the required-reason policy applies to every native macOS app.

Apple’s [Files and directories](https://developer.apple.com/documentation/technologyoverviews/files-and-directories) says macOS creates system container directories only for sandboxed apps. [applicationSupportDirectory](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory) separately distinguishes sandboxed container storage from unsandboxed `~/Library/Application Support` storage. These sources do not support claiming C617.1 solely because Still owns an Application Support subdirectory.

[Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) describes distribution outside the Mac App Store. [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) lists Developer ID signing, valid signatures, Hardened Runtime, secure timestamps, entitlement restrictions and SDK requirements; it does not list required-reason declarations among its notarization prerequisites.

[Adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) documents macOS bundle placement and App Store Connect validation. Manifest placement instructions establish how to bundle a manifest, not that every native macOS API use requires an approved reason. Collected-data, tracking and listed third-party SDK policies remain separate questions.

## Inference and practical consequence

For Still’s current native, unsandboxed, directly distributed Developer ID model, retain required-reason entries as an explicitly reviewed purpose inventory if desired, rather than describing them as a proven notarization requirement. Do not add C617.1 by analogy with app ownership. No storage migration is justified solely to satisfy the previously asserted blanket gate.

## Unknowns and limits

No reviewed Apple source explicitly confirms C617.1 eligibility for unsandboxed Application Support. No specific Apple DTS confirmation was located in this bounded search. No signed submission, notarization experiment or App Store Connect upload was performed. Documentation cannot guarantee future enforcement. Recheck the final candidate’s distribution channel, dependencies, data practices and current Apple policy before release; Mac App Store and third-party SDK requirements must be assessed separately.

# #54 Spec review

Reviewed `83d8239...e17a49e` (production `62bcf8a`) against docs/RELEASE-ARCHIVES.md Q1–Q7 and AGENTS/domain/design instructions.

No actionable source/spec findings.

- “Release archives first” and “Device backups stays initial selection”: enum order adds archives first; model still explicitly defaults to Device backups. Session model and Back route are unchanged.
- “Not inspected” / “cannot use the existing arbitrary selected-object measurement route”: UI omits inspection and model rejects its chooser; public inventory rejects releaseArchives before metadata access, returns no selected URL/time, and never produces cleanup authority or reclaimable bytes.
- “Open Xcode launches the app” / explicit guide: existing NSWorkspace lookup and launcher are only reached on button click; Xcode identifier is correct; instructions explicitly deny direct Organizer opening; Link uses the agreed official Apple debugging URL.
- “Unavailable/failure”: existing inline result retains category/content and reenables explicit launch retry. No permission, installer, traversal or fallback action added.
- Shared guidance uses existing StatusRow/SummarySurface; Gallery is inert. Other category branches, initial selection, and M6/future gate remain unchanged. No cleanup-plan/sidebar additions.

Qualification limits: focused native execution, Light/Dark initial/minimum capture review, and final evidence/doc status are still integration requirements. This read-only source review does not certify real Xcode lookup/opening or visual acceptance. Pending native/artifact evidence is not recorded as a missing-code defect.

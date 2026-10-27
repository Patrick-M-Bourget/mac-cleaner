# Cache Drop: research and proposed delivery tickets

Prepared October 26, 2026. Repository: `/Users/bender/Workspace/mac-cleaner` (formerly Still). Research baseline: commit `67ccadaead5dbaf4dc0b46b877f1aaa925239845`.

This document consolidates the research, source-code findings, recommendations, and implementation ticket drafts. Ticket IDs `CD-01` through `CD-18` are local planning IDs, not published GitHub issue numbers. No new product decisions are assumed approved. Recheck current code and existing GitHub issues before publishing or implementing; the checkout may have evolved since inspection.

The research is based on primary-source documentation and read-only source inspection. Competitor binaries, application cleanup workflows, and the installed product were not functionally tested. Default paths are discovery seeds, not deletion authorization.

## Document map

- [Proposed tickets](#proposed-tickets): priorities, dependencies, scope and acceptance criteria.
- [Research and product blueprint](#research-and-product-blueprint): vendor paths, recommended behavior, delivery sequence and decision questions.
- [Detailed competitor evidence](#detailed-competitor-evidence): documented workflows and limitations.
- [Detailed repository audit](#detailed-repository-audit): implementation evidence and fixture-test references.

## Planning conventions

- **P0:** correct a documented cleanup-method conflict before expanding the cleanup promise.
- **P1:** foundational coverage or first integrations.
- **P2:** deeper management or broader ecosystem support.
- **Policy:** proposed implementation follows existing no-admin, no-auto-cleanup, no-uninstaller boundaries unless explicitly identified as a decision ticket.
- **Proposed triage:** `needs-triage` until reconciled with current issues and approved scope. A dependency denotes implementation order, not permission to widen scope.
- **Definition of done:** relevant fixture tests plus local build for code changes; vendor integration claims additionally require disposable application/project validation. Never run destructive tests on personal files. Scanning remains read-only; selection/review precedes changes.

## Proposed tickets

| ID | Priority | Proposed ticket | Blocked by |
|---|---|---|---|
| [CD-01](#cd-01) | P0 | Use uv-native cache cleanup instead of deleting its cache directory | None |
| [CD-02](#cd-02) | P1 | Discover configured developer cache locations and tool installations | CD-01 establishes the first native-discovery example |
| [CD-03](#cd-03) | P1 | Define shared storage-item classification and ownership relationships | None; design before creator discovery implementation |
| [CD-04](#cd-04) | P1 | Define and approve creator-management boundaries | None |
| [CD-05](#cd-05) | P1 | Show scan coverage, inaccessible locations and offline dependencies | CD-03 |
| [CD-06](#cd-06) | P1 | Inventory Final Cut libraries and guide generated-media cleanup | CD-03, CD-04, CD-05 |
| [CD-07](#cd-07) | P1 | Discover Adobe media caches and provide app-specific management | CD-03, CD-04, CD-05 |
| [CD-08](#cd-08) | P1 | Inventory Lightroom Classic previews without exposing catalogs to cleanup | CD-03, CD-04, CD-05 |
| [CD-09](#cd-09) | P1 | Replace the audio-folder total with a per-product plug-in inventory | CD-03, CD-04 |
| [CD-10](#cd-10) | P1 | Show music sample libraries and shared content alongside plug-ins | CD-03, CD-04, CD-05, CD-09 |
| [CD-11](#cd-11) | P2 | Discover multiple Photos libraries and provide storage guidance | CD-03, CD-04, CD-05 |
| [CD-12](#cd-12) | P2 | Add project-aware developer build-artifact review | CD-02, CD-03, CD-04 |
| [CD-13](#cd-13) | P1 | Audit generic app-cache rules for valuable offline content and shared owners | CD-03 for richer ownership; initial audit can start independently |
| [CD-14](#cd-14) | P1 | Extend storage accounting across shared resources and integrations | CD-03 |
| [CD-15](#cd-15) | P1 | Establish per-integration validation and publish support levels | CD-04; fixture design can precede adapter implementation |
| [CD-16](#cd-16) | P2 | Promote validated creative caches from guidance to executable cleanup | CD-06/CD-07/CD-08 as applicable; CD-13, CD-14, CD-15; CD-04 approval of action scope |
| [CD-17](#cd-17) | P2 | Design guided media and sound-library archive/relocation | CD-04 explicit scope decision; CD-05, CD-06 or CD-10, CD-14 |
| [CD-18](#cd-18) | P2 | Research remaining creator ecosystems before adding rules | CD-04 selects priorities |

**Recommended first batch:** CD-01, CD-04 and CD-15; then CD-02/CD-03/CD-13/CD-14, followed by the selected creator integrations. Priorities are recommendations, not an approved schedule. Publish blockers before dependent issues and use native GitHub dependencies when these drafts become issues.

<a id="cd-01"></a>

### CD-01: Use uv-native cache cleanup instead of deleting its cache directory

**Priority:** P0  
**Proposed triage / scope:** needs-triage; bounded correction to an existing integration  
**Blocked by:** None

**Problem:** The `uv-cache` catalog rule permanently deletes `~/.cache/uv`, conflicting with Astral’s documented prohibition on direct cache mutation. Owner-process checks alone do not implement uv’s storage coordination.

**Scope:** Resolve the installed uv executable and active cache directory; replace folder deletion with a bounded native prune action. Expose full clean only as a distinct reviewed choice if approved. Update the current spec/reset exception and consequence text.

**Acceptance criteria**

- [ ] The executor never directly removes uv cache files, including leftover/retry paths.
- [ ] Unavailable uv or unresolved configuration produces an explicit unsupported/unknown state rather than falling back to deletion.
- [ ] Fixtures exercise native invocation, active/configured location, process/timeout/error cases, preview mode, and measured results.
- [ ] A disposable uv environment remains usable after cleanup and reconstructs artifacts as documented.

**Evidence / starting points:** `Packages/StillCore/Sources/StillCore/Catalog.swift:183`; [uv cache safety](https://docs.astral.sh/uv/concepts/cache/)

<a id="cd-02"></a>

### CD-02: Discover configured developer cache locations and tool installations

**Priority:** P1  
**Proposed triage / scope:** needs-triage; existing-feature coverage  
**Blocked by:** CD-01 establishes the first native-discovery example

**Problem:** Most developer rules scan default paths and use short executable lists. Environment/config overrides and version-manager installations can be missed. Existing browser layout overrides suppress a rule; they do not discover the replacement path.

**Scope:** Add tool-specific discovery for npm, pip, pnpm, uv and Homebrew. Record location provenance, tool identity and discovery errors. Account for GUI-versus-shell environment differences without executing arbitrary shell startup files.

**Acceptance criteria**

- [ ] Default and custom locations are found and shown with their owner/tool and provenance.
- [ ] External/symlink targets can be inventoried without weakening existing write containment checks.
- [ ] Unsupported or ambiguous installations are shown honestly; no arbitrary PATH executable is trusted without validation.
- [ ] Tool lookup is bounded/cancellable and fixtures cover missing tools, malformed output, multiple interpreters and custom roots.

**Evidence / starting points:** `Catalog.swift:162`; `LayoutOverride.swift:3`; developer location sources in the research blueprint

<a id="cd-03"></a>

### CD-03: Define shared storage-item classification and ownership relationships

**Priority:** P1  
**Proposed triage / scope:** needs-triage; foundational design  
**Blocked by:** None; design before creator discovery implementation

**Problem:** The existing candidate/rule model supports cleanup, but does not connect products, projects, shared resources and volumes. A large folder can contain multiple data purposes or serve multiple apps.

**Scope:** Extend the current model with read-only storage inventory items, data purpose, owner products, project/library references, volume/location, evidence/confidence and supported actions. Keep inventory items distinct from executable cleanup candidates.

**Acceptance criteria**

- [ ] Model represents rebuildable artifacts, downloaded installed content, original work, backups and unknown data.
- [ ] An item can have multiple owners and unresolved references without being classified as unused.
- [ ] Guidance/inventory-only items cannot enter the executor.
- [ ] Existing simple cache rules continue to work without requiring a universal dependency parser.

**Evidence / starting points:** `Catalog.swift`; `CatalogGuidance.swift`; `GuidanceCatalog.swift`; blueprint Engineering sections 1–2

<a id="cd-04"></a>

### CD-04: Define and approve creator-management boundaries

**Priority:** P1  
**Proposed triage / scope:** needs-triage; product decision required  
**Blocked by:** None

**Problem:** Existing decisions exclude admin helpers, uninstallers and automatic cleanup. “Music management” and “large media cleanup” can otherwise imply unsupported removal or relocation.

**Scope:** Record which integration levels count as supported: inventory, native-app guidance, verified cleanup and relocation. Decide treatment of offline originals, shared/system content and plug-in uninstalling. Choose the first creator ecosystems and audience.

**Acceptance criteria**

- [ ] Approved wording separates cache clearing, large-media review and installed-content management.
- [ ] Default decision preserves no-admin and no automatic cleanup unless the user explicitly changes it.
- [ ] Shared content can be inventoried without implying write permission.
- [ ] Any accepted scope expansion is recorded in current authoritative decisions rather than inferred from this research.

**Evidence / starting points:** `docs/RESET.md` Decisions; `docs/SPEC.md:135`; blueprint Decisions to grill

<a id="cd-05"></a>

### CD-05: Show scan coverage, inaccessible locations and offline dependencies

**Priority:** P1  
**Proposed triage / scope:** needs-triage; extend existing uncertainty reporting  
**Blocked by:** CD-03

**Problem:** A credible storage promise needs visibility into what was not scanned. Creator assets frequently live on external drives or custom paths; unknown is not zero.

**Scope:** Add per-integration coverage summaries: inspected defaults/configured roots, missing or offline volumes, permission failures, unsupported layouts and partial sizes. Reuse existing access/size states.

**Acceptance criteria**

- [ ] Coverage distinguishes absent, inaccessible, offline, unsupported and partially measured locations.
- [ ] User-picked roots persist through the existing access architecture; access loss is handled.
- [ ] Metadata scans do not hydrate cloud placeholders.
- [ ] No finding labels a file unused merely because its project or source volume is offline.

**Evidence / starting points:** `CatalogDiscovery.swift`; `KnownLocationSizer.swift`; `CatalogCleanupModel+Guidance.swift`; Apple sandbox guidance in blueprint

<a id="cd-06"></a>

### CD-06: Inventory Final Cut libraries and guide generated-media cleanup

**Priority:** P1  
**Proposed triage / scope:** needs-triage; inventory/guidance first  
**Blocked by:** CD-03, CD-04, CD-05

**Problem:** No dedicated Final Cut integration exists; the generic explorer does not descend into library packages or attribute external media/cache.

**Scope:** Discover `.fcpbundle` libraries in selected roots, show library/volume identity and confirmed storage categories, and guide File → Delete Generated Library Files. Resolve custom storage only through supported or separately validated methods.

**Acceptance criteria**

- [ ] Multiple/renamed/external libraries are represented; unsupported internal formats remain unknown.
- [ ] Originals, database backups, render files, optimized media and proxies have distinct explanations.
- [ ] Missing/offline originals produce a warning about regeneration prerequisites.
- [ ] Opening guidance is never reported as completed cleanup; no library internals are modified in this ticket.

**Evidence / starting points:** [Apple storage locations](https://support.apple.com/it-it/guide/final-cut-pro/ver7db6ffe77/mac); [generated media cleanup](https://support.apple.com/en-au/119610)

<a id="cd-07"></a>

### CD-07: Discover Adobe media caches and provide app-specific management

**Priority:** P1  
**Proposed triage / scope:** needs-triage; inventory/guidance first  
**Blocked by:** CD-03, CD-04, CD-05

**Problem:** Generic cache detection does not cover Adobe Common media cache or project-specific previews; shared and versioned caches need separate ownership.

**Scope:** Add Premiere, Media Encoder and After Effects inventory for confirmed cache locations and versions. Separate common media cache, persistent disk cache, project previews, originals and Auto Save. Provide exact native cleanup steps.

**Acceptance criteria**

- [ ] Default and configured cache locations are covered where resolvable; uncertain paths are not guessed.
- [ ] Shared Adobe cache is counted once and names all confirmed owners.
- [ ] Project scratch folders are not treated as disposable as a whole.
- [ ] Fixtures cover multiple versions/custom locations/offline sources; a disposable project verifies each advertised native workflow.

**Evidence / starting points:** [Adobe cache location](https://helpx.adobe.com/uk/premiere/desktop/troubleshooting/playback-issues/choppy-playback-and-poor-performance-issue.html); [AE storage](https://helpx.adobe.com/after-effects/desktop/memory-storage-performance/memory-and-storage/memory-storage1.html)

<a id="cd-08"></a>

### CD-08: Inventory Lightroom Classic previews without exposing catalogs to cleanup

**Priority:** P1  
**Proposed triage / scope:** needs-triage; inventory/guidance first  
**Blocked by:** CD-03, CD-04, CD-05

**Problem:** Lightroom stores normal previews beside catalogs, while Smart Previews support offline editing. Treating both as ordinary cache would conceal meaningful consequences.

**Scope:** Discover selected catalog locations and classify normal previews, Smart Previews, Camera Raw cache and protected catalog data. Guide supported purge/retention actions. Treat cloud Lightroom as a separate unsupported integration until researched.

**Acceptance criteria**

- [ ] Catalog and related database/metadata files are protected.
- [ ] Normal and Smart Previews appear separately, with offline-editing consequences.
- [ ] Camera Raw configured cache is distinguished from presets/settings.
- [ ] No direct catalog/package mutation occurs; fixture and disposable-catalog checks verify classification.

**Evidence / starting points:** [Adobe preview cache](https://helpx.adobe.com/lightroom-classic/desktop/kb/lightroom-gives-error-preview-cache.html); [Smart Previews](https://helpx.adobe.com/ro/lightroom-classic/help/lightroom-smart-previews.html)

<a id="cd-09"></a>

### CD-09: Replace the audio-folder total with a per-product plug-in inventory

**Priority:** P1  
**Proposed triage / scope:** needs-triage; read-only music MVP  
**Blocked by:** CD-03, CD-04

**Problem:** Current audio guidance sums two Audio/Plug-Ins roots, omitting AAX’s separate root and app-based AUv3 discovery. It does not expose publisher, version, format or architecture.

**Scope:** Inventory AUv2, VST2, VST3, AAX and AUv3; group formats under confirmed product identities. Show publisher, version, architecture, path, volume, Finder reveal and export. Inspect binaries/metadata without loading plug-in code.

**Acceptance criteria**

- [ ] System and user roots plus approved custom locations are supported, with partial coverage disclosed.
- [ ] AAX and AUv3 are represented; Apple built-ins are not assumed to be removable binaries.
- [ ] Multiple formats/versions remain individually visible and are not called duplicates or unused automatically.
- [ ] Inventory and export work without admin rights, uninstallation or license modification.

**Evidence / starting points:** `GuidanceCatalog.swift:35`; [Apple AU](https://support.apple.com/en-sg/102239); [Ableton formats](https://help.ableton.com/hc/en-us/articles/209068929-Using-AU-and-VST-plug-ins-on-macOS); [Avid AAX](https://kb.avid.com/pkb/articles/en_US/Knowledge/pro-tools-plugins-folder-location)

<a id="cd-10"></a>

### CD-10: Show music sample libraries and shared content alongside plug-ins

**Priority:** P1  
**Proposed triage / scope:** needs-triage; split by vendor when publishing  
**Blocked by:** CD-03, CD-04, CD-05, CD-09

**Problem:** Plug-in binaries often account for much less storage than samples/resources. Current guidance misses Logic/Ableton/NI/Arturia/Waves content and external library targets.

**Scope:** Create separate vendor adapters, beginning with the selected launch ecosystem. Inventory Logic/MainStage versioned layouts, Ableton Packs/User Library, NI product libraries, Arturia resources and Waves samples. Use manager settings and validated aliases where available.

**Acceptance criteria**

- [ ] Installed libraries and user presets/samples are classified separately from disposable downloads/cache.
- [ ] Shared content appears once with all confirmed owners; ownership uncertainty is visible.
- [ ] External/offline targets retain their identity and are not marked abandoned.
- [ ] Vendor-manager/reveal guidance is provided; no automated move/delete/uninstall is introduced.

**Evidence / starting points:** Music vendor storage matrix and vendor citations in the research blueprint

<a id="cd-11"></a>

### CD-11: Discover multiple Photos libraries and provide storage guidance

**Priority:** P2  
**Proposed triage / scope:** needs-triage; expand existing guidance  
**Blocked by:** CD-03, CD-04, CD-05

**Problem:** Photos guidance recognizes only `~/Pictures/Photos Library.photoslibrary`, missing renamed, additional and external libraries.

**Scope:** Discover library packages in approved locations; show total size/volume and guidance for Optimize Mac Storage or supported whole-library relocation. Keep Photos database and media internals protected.

**Acceptance criteria**

- [ ] Multiple/default/custom/external libraries are discoverable without reading original media contents.
- [ ] Library deletion is never offered as cache clearing.
- [ ] Guidance explains that iCloud photo deletion synchronizes across devices.
- [ ] No automatic library move, duplicate removal or Photos database modification is added.

**Evidence / starting points:** [Apple relocation](https://support.apple.com/en-au/108345); [iCloud deletion semantics](https://support.apple.com/en-nz/guide/icloud/mm8b32f3ae27/icloud)

<a id="cd-12"></a>

### CD-12: Add project-aware developer build-artifact review

**Priority:** P2  
**Proposed triage / scope:** needs-triage; publish one ecosystem per issue  
**Blocked by:** CD-02, CD-03, CD-04

**Problem:** Global caches are covered, but node_modules, Rust target, virtual environments and other project output are not. The generic explorer intentionally protects Git projects.

**Scope:** Add explicitly selected project roots and recognized manifests/configuration. Start with one ecosystem and understand its output path and reconstruction prerequisites. Preserve source, tracked caches, credentials and user-added content.

**Acceptance criteria**

- [ ] The project and generating tool are identified before artifacts are offered.
- [ ] Global Git protection remains intact; a narrow artifact action does not enable arbitrary project deletion.
- [ ] Custom build paths and offline/private dependency constraints are handled or reported unsupported.
- [ ] Fixtures include nested repositories, user additions and committed caches; a disposable project rebuilds after reviewed cleanup.

**Evidence / starting points:** `UserFiles.swift:28`; [Cargo clean](https://doc.rust-lang.org/cargo/commands/cargo-clean.html); developer-storage matrix

<a id="cd-13"></a>

### CD-13: Audit generic app-cache rules for valuable offline content and shared owners

**Priority:** P1  
**Proposed triage / scope:** needs-triage; safety/accuracy work  
**Blocked by:** CD-03 for richer ownership; initial audit can start independently

**Problem:** An installed app’s bundle-ID cache folder is not proof that every child is disposable. Competitor documentation explicitly identifies offline music inside cache locations; creator apps also share assets.

**Scope:** Audit current broad cache rules and document app-specific exclusions or narrower targets for supported apps. Identify content with offline/recovery value and all relevant helpers/owners. Preserve the current unknown-owner refusal.

**Acceptance criteria**

- [ ] Supported exceptions have evidence and fixture coverage, not just folder-name heuristics.
- [ ] Offline purchased/downloaded content is not silently described as regenerable transient cache.
- [ ] Shared/active owners block only their relevant candidates and explain why.
- [ ] Unsupported layouts remain inventory/guidance-only rather than widening delete permissions.

**Evidence / starting points:** `AppCaches.swift:61`; `CandidateCheck.swift`; [MacPaw Safety Database](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/safety-database)

<a id="cd-14"></a>

### CD-14: Extend storage accounting across shared resources and integrations

**Priority:** P1  
**Proposed triage / scope:** needs-triage; preserve existing measured outcomes  
**Blocked by:** CD-03

**Problem:** Creator inventory can count a library, its children, alias targets and shared assets more than once. Allocated sizes are observations, not exact reclaim guarantees.

**Scope:** Extend stable item/volume identity accounting across integration totals; separate inventory totals, candidate estimates, Trash bytes, native-tool estimates and measured free-space change. Retain partial-size and delayed-reclaim qualifications.

**Acceptance criteria**

- [ ] Parent/child and cross-integration references do not inflate displayed totals.
- [ ] Hard links, aliases and APFS clones have documented accounting behavior and uncertainty.
- [ ] Guidance-only items and cloud-only/offline data never count as reclaimed bytes.
- [ ] Whole-run measurement remains distinct from tool output and is checked with fixtures plus disposable-volume scenarios.

**Evidence / starting points:** `SpaceKey.swift`; `KnownLocationSizer.swift`; `CleanupExecutor.swift`; [Apple resource keys](https://developer.apple.com/documentation/foundation/urlresourcekey?language=objc)

<a id="cd-15"></a>

### CD-15: Establish per-integration validation and publish support levels

**Priority:** P1  
**Proposed triage / scope:** needs-triage; acceptance framework  
**Blocked by:** CD-04; fixture design can precede adapter implementation

**Problem:** Existing fixtures verify internal behavior, but do not prove every vendor app reopens or regenerates content correctly after cleanup.

**Scope:** Define a small reproducible test corpus and support matrix for inventory/guidance/verified-cleanup levels. Cover actual supported app versions and default/custom/external layouts. Record limitations without reviving obsolete exact-build gates.

**Acceptance criteria**

- [ ] Validation includes missing originals, offline volumes, shared content, active helpers, partial scans and interrupted actions.
- [ ] Disposable projects reopen, load required instruments/media, and rebuild as promised.
- [ ] Coverage and classification failures are visible; no promised GB is inferred from marketing or documentation.
- [ ] Support claims name tested integration levels and limitations; personal projects are never destructive test fixtures.

**Evidence / starting points:** Blueprint Delivery sequence and proof of value; existing DeveloperCacheTests/UserFilesTests/GuidanceTests

<a id="cd-16"></a>

### CD-16: Promote validated creative caches from guidance to executable cleanup

**Priority:** P2  
**Proposed triage / scope:** needs-triage; separate issue per app/artifact  
**Blocked by:** CD-06/CD-07/CD-08 as applicable; CD-13, CD-14, CD-15; CD-04 approval of action scope

**Problem:** Read-only discovery and native guidance provide initial value, but do not execute cleanup. Each executable artifact action needs its own evidence and safe mechanism.

**Scope:** Choose one documented generated-data category at a time. Prefer supported native commands/APIs; direct file cleanup requires validated layout, shared-owner checks, source prerequisites and narrow package access. Do not automate unsupported UI interactions silently.

**Acceptance criteria**

- [ ] Preflight identifies exact artifact/owner and verifies all required originals or rebuild inputs.
- [ ] Protected catalog/source/backup files cannot enter the action.
- [ ] Preview explains rebuild/render cost and irreversibility; errors/cancel/partial results are accurate.
- [ ] Vendor-level disposable-project validation passes before the support matrix labels the action verified cleanup.

**Evidence / starting points:** Final Cut/Adobe matrix; existing CandidateCheck/CleanupExecutor; CD-15 validation requirements

<a id="cd-17"></a>

### CD-17: Design guided media and sound-library archive/relocation

**Priority:** P2  
**Proposed triage / scope:** needs-triage; design and guidance before automation  
**Blocked by:** CD-04 explicit scope decision; CD-05, CD-06 or CD-10, CD-14

**Problem:** Large originals and sound libraries are valuable content. Moving them can save internal space but break references, managers and offline workflows.

**Scope:** Start with precise vendor-native relocation guidance. If automated copying is approved later, verify destination capacity/content, supported filesystem, manager relinking and app/project usability before offering source removal.

**Acceptance criteria**

- [ ] Every action distinguishes copy, move, archive, relink and source removal.
- [ ] Copying alone is never reported as internal-space recovery.
- [ ] Interruption/offline destination cannot trigger source deletion.
- [ ] Any automated version requires explicit source removal review and successful supported relinking validation; no blanket symlink workaround.

**Evidence / starting points:** Apple Logic/Photos, NI, Arturia and Waves relocation sources in blueprint

<a id="cd-18"></a>

### CD-18: Research remaining creator ecosystems before adding rules

**Priority:** P2  
**Proposed triage / scope:** needs-triage; research backlog  
**Blocked by:** CD-04 selects priorities

**Problem:** Current research provides starting coverage, not a universal vendor path registry. Additional popular vendors and cloud workflows need independent investigation.

**Scope:** Prioritize Steinberg/VST Sound, Spitfire, Toontrack, UVI, EastWest, IK Multimedia, Splice, additional DAWs, cloud Lightroom, DaVinci Resolve and Capture One. Produce primary-source paths, configuration discovery, ownership, native actions and validation requirements per selected ecosystem.

**Acceptance criteria**

- [ ] Every path/action claim cites current vendor documentation or first-party implementation evidence.
- [ ] Default/custom/version-specific layouts and user-created versus installed content are distinguished.
- [ ] Undocumented parsers and unverified historical paths are labeled explicitly.
- [ ] Output recommends an inventory/guidance/cleanup level and a bounded follow-on issue rather than enabling speculative deletion.

**Evidence / starting points:** Research blueprint follow-up vendor coverage; Spectrasonics historical-manual caveat

## Research and product blueprint

## Cache Drop: developer and creator storage blueprint

Research date: October 26, 2026. Product called Drop Cache in the initial request, Cache Drop in the follow-up, and Still in the source tree. Canonical checkout inspected: `/Users/bender/Workspace/mac-cleaner`.

This is a source-code review and primary-source documentation study. No cleanup was run, no personal media was inspected, and competitor binaries were not tested. “Implemented” means present and wired in the inspected checkout, not independently verified in a shipped build. Priorities and proposed product behavior are recommendations; vendor storage facts have citations. Defaults are discovery seeds, never sufficient authorization to delete.

### Recommendation

Build on the existing cleanup catalog. Expand it into an application-aware inventory that answers: **what owns this space, what kind of content is it, what depends on it, and which action will reclaim local storage?**

The strongest potential advantage is the connection between cleanup and creator workflows: explain a Final Cut library's generated media; distinguish Adobe cache from originals and catalogs; show a music product's plug-ins, sample libraries, shared resources, and vendor management options together. Research establishes an opportunity, not an exclusive capability absent from every competitor.

Use three separate promises:

1. **Clean rebuildable files:** development caches/build output and verified creative caches, with the rebuild cost explained.
2. **Review large media:** locate libraries, projects, recordings, exports, and originals; preview and guide archive/move decisions. Size and age do not establish that content is trash.
3. **Understand music storage:** inventory installed instruments/effects and their content, explain sharing, and offer vendor-supported management.

Cache clearing usually trades storage for future download/build/render work. Do not make general performance-improvement or permanent-savings claims.

### Current product versus expansion

The reset plan's introductory account of Downloads-only cleanup is historical. The current code includes a shared catalog/executor and broader UI wiring. See the code audit appendix for exact evidence.

| Area | Present in the checkout | Expansion that would add value |
|---|---|---|
| Developer storage | npm, Yarn, pnpm, uv, pip, Cargo, Gradle, CocoaPods, Homebrew; Xcode DerivedData/device support/unavailable simulators; Docker object-category actions | Discover configured locations; fix vendor-method exceptions; group artifacts by project; add selected project build-output support |
| General cleanup | Browsers, app/updater caches, logs, Downloads; user-selected large/old-file explorer | More precise app-specific exceptions and file-purpose labels |
| Supporting infrastructure | Discovery, exclusion/protection checks, owner/process checks, dry-run preview, cleanup journal/history/recovery, allocated/logical estimates and measured free-space change | Add relationships between an app/product, shared resources, projects, and volumes |
| Final Cut / Adobe | No dedicated rules identified | Discover libraries/catalogs/cache settings; distinguish cache/render/proxy/original/project/backup; offer exact native management workflows |
| Photos | Guidance for one default `Photos Library.photoslibrary` path | Discover multiple/renamed/external libraries; explain optimization and library relocation |
| Music | Guidance summarizing system and user `Audio/Plug-Ins` directories | Per-product/format inventory, sample libraries, sound packs, shared content, architecture/version, vendor-manager links |

Existing decisions matter: no admin helper, user-owned cleanup only, no automatic cleanup, no app uninstaller, no duplicate finder, no treemap. Music inventory and vendor guidance fit those decisions. Automatic plug-in removal, broad shared-library deletion, or automatic relocation would change scope and need a product decision. Read-only inventory can include accessible shared folders without making their contents cleanup candidates.

### Competitor lessons

These are documented capabilities, not hands-on comparisons. Repository main branches and beta documentation can describe behavior ahead of stable releases.

| Competitor | How it addresses the problem | Implication |
|---|---|---|
| CleanMyMac | App-grouped caches; Xcode junk categories; large-file filtering and manual review; app-specific safety exceptions. Its documentation acknowledges that cache folders can contain offline music. | App association and cache exceptions are baseline requirements. [Cleanup](https://macpaw.com/support/cleanmymac/knowledgebase/system-junk), [Safety Database](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/safety-database) |
| CleanMyMac CLI, public beta | Shared-cache cleanup plus project-artifact purge; broad package-manager/Xcode/Docker coverage, project grouping, ignores, review. | Developer cleanup alone is already directly contested by an incumbent. [Official repository](https://github.com/MacPaw/cleanmymac-cli) |
| DaisyDisk | Disk visualization and manual collection; separate purgeable/hidden reporting; advises using owning apps to remove library-managed content. | Ownership and honest space accounting complement file discovery. [Library guidance](https://web.daisydiskapp.com/guide/4/en/LocatingSpaceWasters), [purgeable space](https://daisydiskapp.com/guide/4/en/PurgeableSpace/) |
| DevCleaner | Xcode-focused generated-data and archive inspection; documents dependence on internal Xcode layouts. | Deep app knowledge is useful, but parsers need ongoing maintenance. [Repository](https://github.com/vashpan/xcode-dev-cleaner) |
| Mole | Developer artifact cleanup with dry runs, ignores, protection for Git/shared data, and incomplete-scan disclosure. | Transparent protections and uncertainty already exist in open-source alternatives. [Repository](https://github.com/tw93/Mole) |
| PlugInfo | Audio plug-in inventory: publisher, format, CPU architecture, Finder reveal, export, refresh. | Music visibility can deliver value independently of deletion. [Developer listing](https://apps.apple.com/us/app/pluginfo/id1626412949?mt=12) |
| Audio Plugin Uninstaller | Uses installer receipts, protects shared files, and falls back to individual plug-in binaries/formats when receipts are unavailable. | Receipts and shared ownership are useful evidence; they do not establish every post-install content dependency. [Vendor](https://www.widebluesound.com/audio-plugin-uninstaller/) |

CleanMyMac also documents Photos-aware duplicate removal; it would be inaccurate to characterize all competitors as generic filesystem scanners. Its large-file feature offers kind/size/access-date filtering, Quick Look, and Finder reveal. Those pages do not establish project-reference analysis for arbitrary creative media. [Large files](https://macpaw.com/support/cleanmymac/knowledgebase/large-and-old), [duplicates](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/duplicate-files)

### Developer storage: discovery and cleanup map

`~` means the selected user's home. Paths below are defaults or documented seeds. Ask installed tools for their active paths and account for environment/configuration overrides; a GUI process's environment can differ from the developer's shell.

| Source | Location / discovery | Recommended treatment |
|---|---|---|
| Xcode build output | `~/Library/Developer/Xcode/DerivedData`; custom or workspace-relative locations possible | Show per project, clean when idle, explain reindex/rebuild cost. Apple describes it as reconstructible from source. [Apple locations](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html) |
| Xcode Archives | `~/Library/Developer/Xcode/Archives` | Keep separate from build cache; use Organizer guidance for review. Existing product protection should remain. [Apple locations](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html) |
| Simulators | Discover through Xcode/`simctl`; distinguish OS runtimes from individual simulated devices | Native management. Removing a runtime and discarding a device's apps/test state have different consequences. [Apple management](https://developer.apple.com/documentation/safari-developer-tools/adding-additional-simulators) |
| npm | Default cache `~/.npm`, package data in `_cacache`; configuration can override | Query active cache. `npm cache verify` performs integrity/garbage collection; optional `clean --force` reclaims cache. Do not describe routine cache clearing as necessary repair. [npm](https://docs.npmjs.com/cli/cache/) |
| pnpm | `pnpm store path` | Use `pnpm store prune`, preserve linked/shared store semantics; occasional pruning can require later downloads. Existing native prune is the right direction. [pnpm](https://pnpm.io/cli/store) |
| pip | `python -m pip cache dir`; default `~/Library/Caches/pip`, overrides possible | Prefer matching interpreter's cache commands. `cache purge` clears HTTP and wheel caches. Internal structure is explicitly unstable. [pip](https://pip.pypa.io/en/stable/topics/caching/) |
| uv | `uv cache dir`; default `~/.cache/uv` or XDG override | **Use `uv cache prune`/`clean`, never direct folder mutation.** uv explicitly requires its own methods and coordinates locks/processes. This conflicts with the current rule and reset decision. [uv cache](https://docs.astral.sh/uv/concepts/cache/), [storage](https://docs.astral.sh/uv/reference/storage/) |
| Homebrew | `brew --cache`; default `~/Library/Caches/Homebrew` | Native cleanup with dry-run preview; honor overrides. Explain which downloads/old versions will be removed. [Homebrew](https://docs.brew.sh/Manpage) |
| Cargo | `CARGO_HOME` or `~/.cargo`; workspace `target` can be overridden | Separate global registry/Git caches from project output, installed tools, config and credentials. `cargo clean --dry-run` previews generated artifacts. Never delete all Cargo home. [Cargo home](https://doc.rust-lang.org/beta/cargo/guide/cargo-home.html), [clean](https://doc.rust-lang.org/cargo/commands/cargo-clean.html) |
| Gradle | `GRADLE_USER_HOME` or `~/.gradle`; project `.gradle` | Separate cache categories from config/init scripts/toolchains. Gradle already has retention and automatic cleanup; avoid implying every old folder is abandoned. [Gradle](https://docs.gradle.org/current/userguide/directory_layout.html) |
| Docker Desktop | `docker system df -v`; disk-image location in Desktop settings, commonly under `~/Library/Containers/com.docker.docker/Data/vms/0/data/` | Inventory and native object actions; preserve volumes. Stopped-container writable layers can contain unique data. Never delete `Docker.raw` as cache. Logical disk capacity is not allocated host storage. [Docker Mac FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/), [pruning](https://docs.docker.com/engine/manage-resources/pruning/) |

Project-level cleanup is a separate expansion from global caches. Candidate families include `node_modules`, Rust build output, Python virtual environments, and framework build directories. Require a recognized project, understood tool/configuration, preservation of source and user additions, and explicit user review. A directory name or old modification date is insufficient proof. Do not delete repository caches used for offline/zero-install workflows just because they resemble generated files.

### Video and photography: vendor storage map

| App / files | Where to discover | Product action and consequence |
|---|---|---|
| Final Cut libraries and media | Search user-approved Movies/project folders and external drives for `.fcpbundle`; inspect Library Properties. Media/cache default inside the library but can live externally. Motion templates and database backups default under Movies. | Inventory library totals and their locations. Do not infer contents from bundle size alone. [Apple storage settings](https://support.apple.com/it-it/guide/final-cut-pro/ver7db6ffe77/mac) |
| Final Cut render / optimized / proxy media | Library Properties and generated-media categories | Guide to File → Delete Generated Library Files. Render files regenerate during work; optimized/proxy media require manual regeneration. Verify originals are accessible before recommending removal of working proxies. [Apple move/cleanup](https://support.apple.com/en-au/119610), [render management](https://support.apple.com/en-mide/guide/final-cut-pro/ver68a8c250/mac) |
| Premiere / Adobe common media cache | Default `~/Library/Application Support/Adobe/Common`; actual Media Cache settings can point elsewhere | Identify actual cache subfolders, not the entire Adobe/Common tree. Use native delete-unused/all-cache workflow initially. Shared Adobe ownership must be represented. Cache regenerates. [Adobe location](https://helpx.adobe.com/uk/premiere/desktop/troubleshooting/playback-issues/choppy-playback-and-poor-performance-issue.html), [cleanup](https://helpx.adobe.com/au/premiere/desktop/troubleshooting/media-issues/clear-media-cache-using-preferences.html) |
| Premiere audio/video previews | Project Settings → Scratch Disks; configurable per project | Treat separately from originals, Auto Save, and captured media. Native Sequence → Delete Render Files is documented. Playback/export may slow until rebuilt. [Adobe previews](https://helpx.adobe.com/ca/premiere/desktop/troubleshooting/playback-issues/timeline-doesnt-show-video-preview.html), [render behavior](https://helpx.adobe.com/premiere/desktop/render-and-export/render-sequences-for-playback/use-preview-files-when-rendering.html) |
| After Effects persistent disk / media cache | Disk settings expose the chosen folder; media-cache database is shared with other Adobe apps | Native Empty Disk Cache / Purge workflow. Discover caches per installed version; clearing one version need not clear another. Offline source drives can make useful cache appear unused. [Adobe storage](https://helpx.adobe.com/after-effects/desktop/memory-storage-performance/memory-and-storage/memory-storage1.html) |
| Lightroom Classic catalog / normal previews | Catalog folder, commonly `~/Pictures/Lightroom`; `[Catalog] Previews.lrdata` sits beside catalog | Protect catalogs. Normal previews can be rebuilt; present performance cost and prefer app-managed preview retention. [Adobe preview files](https://helpx.adobe.com/lightroom-classic/desktop/kb/lightroom-gives-error-preview-cache.html) |
| Lightroom Smart Previews | `[Catalog] Smart Previews.lrdata` beside the catalog | Separate review category: enables editing while originals are disconnected. Do not classify together with normal preview cache. [Adobe Smart Previews](https://helpx.adobe.com/ro/lightroom-classic/help/lightroom-smart-previews.html) |
| Lightroom Camera Raw cache | Preferences → File Handling → Camera Raw Cache Settings; customizable | Native purge/size/location guidance; reducing it can slow Develop processing. Presets/settings in Application Support are a different category. [Adobe optimization](https://helpx.adobe.com/lightroom-classic/desktop/technical-support/performance-guidelines/optimize-performance-lightroom.html) |
| Photoshop scratch | Photoshop Settings → Scratch Disks; one or more configured volumes | Show pressure and guide settings changes. No universal stale-temp-file deletion rule is established by this research; active scratch/recovery data is not a general cleanup target. [Adobe scratch disks](https://helpx.adobe.com/photoshop/desktop/troubleshoot/troubleshoot-tools-resources/set-up-and-manage-scratch-disks.html) |
| Apple Photos | Default Pictures library plus renamed/external `.photoslibrary` packages | Keep package contents managed by Photos. Offer optimization or supported whole-library relocation guidance. iCloud deletion synchronizes across devices. [Move library](https://support.apple.com/en-au/108345), [iCloud behavior](https://support.apple.com/en-nz/guide/icloud/mm8b32f3ae27/icloud) |
| Loose originals / exports / recordings | User-approved project folders, Movies/Pictures/Downloads and external volumes | Preview, reveal, label reference status as known or unknown, optionally Trash with explicit selection. An export may be the user's final deliverable. Hash equality alone does not resolve project dependencies. |

Do not promise “unused media” until reference analysis can substantiate it. A missing/offline project or drive means incomplete knowledge. An old export, proxy with unavailable originals, or project backup can still be essential.

Cloud Lightroom differs from Lightroom Classic. Its local/cloud storage semantics require a separate integration; the Classic rules above must not be applied to it by name similarity. Resolve additionally requested creative apps, such as DaVinci Resolve/Capture One, in later vendor-specific research rather than reusing Adobe rules.

### Music production: inventory map

Music requires two connected inventories: executable plug-in formats and large content/resources. A product installed as AU, VST3 and AAX has multiple host integrations; they are not automatically redundant files.

| Source | Verified location / discovery | Recommended treatment |
|---|---|---|
| AUv2 | `/Library/Audio/Plug-Ins/Components` and `~/Library/Audio/Plug-Ins/Components` | Read bundle metadata, show publisher/version/architecture and paths. Built-in Apple instruments are not necessarily removable components. [Apple](https://support.apple.com/en-sg/102239) |
| AUv3 | Application-based extensions, rather than just Components folders | Include app extension discovery in inventory design. [Apple AU extensions](https://support.apple.com/en-by/guide/logicpro/lgcp22a0dab0/12.3/mac/15.6) |
| VST2 / VST3 | `/Library/Audio/Plug-Ins/VST`, `/Library/Audio/Plug-Ins/VST3` and corresponding user Library paths; host-configured custom locations possible | Group formats under a product; show host compatibility. Binary inspection without executing plug-in code is the initial design recommendation. [Ableton](https://help.ableton.com/hc/en-us/articles/209068929-Using-AU-and-VST-plug-ins-on-macOS) |
| AAX / Pro Tools | `/Library/Application Support/Avid/Audio/Plug-Ins` | This important inventory path is outside the current generic Audio/Plug-Ins summary. Use vendor management; do not assume installed means actively used. [Avid](https://kb.avid.com/pkb/articles/en_US/Knowledge/pro-tools-plugins-folder-location) |
| Logic Pro / MainStage, newer layout | `~/Music/Logic Pro Library.bundle` by default for Logic 12 / MainStage 4 and later; relocatable | Recognize bundle and version; guide official relocation/selection workflow. Logic and MainStage can share a library. [Apple relocation](https://support.apple.com/en-nz/111094) |
| Legacy Apple music content | `/Library/Application Support/Logic`, `/Library/Audio/Apple Loops/Apple`, `/Library/Audio/Impulse Responses/Apple` | Shared installed content, not junk. Show once with relevant owners. Do not apply the legacy layout as the sole modern detector. [Apple legacy guide](https://support.apple.com/en-by/guide/logicpro/lgcpf77e757d/10.7/mac/11.0) |
| Ableton Packs / User Library | Defaults `~/Music/Ableton/Factory Packs` and `~/Music/Ableton/User Library`; both configurable | Packs are installed content; User Library includes custom presets/samples and must be protected. Resolve actual settings. [Ableton browser](https://help.ableton.com/hc/en-us/articles/209774665-The-Live-Browser), [User Library](https://help.ableton.com/hc/en-us/articles/209774085-The-User-Library) |
| Ableton download / decoding cache | `~/Library/Caches/Ableton/PackDownloads`; default decoding cache `~/Library/Caches/Ableton/Cache` | Differentiate downloads/cache from installed Packs. Establish idle-state and source-availability rules before offering cleanup. [Ableton downloads](https://help.ableton.com/hc/en-us/articles/209774665-The-Live-Browser), [decoding cache](https://help.ableton.com/hc/en-us/articles/209774325--The-file-could-not-be-read-It-may-be-corrupt-or-not-licensed) |
| Native Instruments | Standalone apps `/Applications/Native Instruments`; content defaults under `/Users/Shared`, can be external; installers default Downloads | Discover each product's content path, not just a folder named Native Instruments. Changing install defaults only affects future installations. Native Access ordinarily removes completed installers. [NI locations](https://support.native-instruments.com/support/solutions/articles/69000879242-native-access-changing-install-locations) |
| NI content relocation | Existing sample libraries / Expansions may be moved then repaired/located in Native Access | Guide the supported move/repair procedure with DAWs closed. Do not relocate Mac plug-in binaries as a space-saving shortcut. [NI relocation](https://support.native-instruments.com/support/solutions/articles/69000879376-moving-a-native-instruments-product-to-another-location-on-your-computer) |
| Arturia | Resources default `/Library/Arturia`; configured path via ASC, including external storage | Resources include presets/samples and other required files; binaries live separately. Use ASC Move/locate, not blind deletion. [Arturia](https://support.arturia.com/hc/en-us/articles/4405741448850-Arturia-Software-Center-ASC-Customise-your-resource-folder-location) |
| Waves | Samples default `/Applications/Waves/Data/Instrument Data/Waves Sample Libraries`; versioned products under `/Applications/Waves/Plug-Ins V…` | Use Waves Central location settings and documented sample relinking. Represent shell/shared product relationships. [Samples](https://www.waves.com/support/how-to-move-pre-installed-instrument-samples-to-a-different-location), [plug-ins](https://www.waves.com/support/locate-the-waves-plug-ins-folder) |
| Spectrasonics | STEAM content or alias under documented Spectrasonics Application Support locations; external target possible | Treat as valuable content; resolve alias targets for inventory without enabling generic symlink-following cleanup. The reviewed relocation manual is old, so validate modern product/version paths before shipping a rule. [Vendor manual](https://support.spectrasonics.net/manual/Omnisphere/get_started/page04.html) |

Follow-up vendor coverage: Steinberg Library Manager/VST Sound, Spitfire, Toontrack, UVI, EastWest, IK Multimedia, Splice, and additional DAWs. This is a prioritized research backlog, not a verified path/deletion registry.

Suggested music product card: product/publisher → installed formats and versions → shared resources/sample libraries → locations/volumes → allocated size and completeness → vendor manager → reveal/export. “Used by project” should appear only when a supported parser or host integration has established it. “No references found in scanned projects” must not become “unused everywhere.” Never infer license entitlement or re-download availability solely from the presence of a product folder.

### Engineering blueprint

These recommendations extend the existing catalog rather than replacing it.

#### 1. Add discovery and relationships

Retain declarative path rules for simple caches. Add small app/tool adapters for configured paths, library/project metadata and native inventory. Model `StorageItem → owner product(s) → project/library → volume`, with shared-resource relationships and confidence/provenance. A root folder may have multiple owners.

A discovery result needs purpose, owner(s), configured/default origin, logical and allocated size, completeness, cloud residency, open/in-use state, supported action, regeneration prerequisites, and unresolved references. Some values will be unknown. Keep unknown visible.

Do not build a universal undocumented-database parser in the first release. Start with vendor-guided management where no supported API exists; a button opening an app is useful guidance but must not claim Drop Cache executed or verified the cleanup.

#### 2. Broaden the action vocabulary carefully

- **Clear rebuildable cache:** known artifact, idle owner(s), clear consequence.
- **Run native cleanup:** tools whose storage has lock/index/reference semantics, especially uv, pnpm, Docker and Homebrew.
- **Review generated media:** render/proxy/optimized media with originals/rebuild prerequisites.
- **Manage installed content:** vendor-manager workflow for sound packs and sample libraries.
- **Archive/move:** guided initially; future automated copy must verify content and relinking before offering source removal.
- **Review originals/exports:** preview and explicit Trash selection; no automatic junk classification.

The current whole-folder cleanup rule is not appropriate for every cache. Make documented tool requirements explicit exceptions in the spec and rule model. Avoid global protection weakening to accommodate creator packages: grant narrowly scoped read-only discovery or a specific validated action.

#### 3. Make coverage honest

Show which default/configured locations and volumes were inspected; inaccessible locations; offline volumes; recognized but unsupported apps; and unknown-size or partially sized results. Full Disk Access does not grant admin ownership or prove an app can modify every shared content folder. The no-admin decision can coexist with strong inventory plus vendor guidance.

If distribution uses App Sandbox, user-selected folders and security-scoped bookmarks are relevant; Apple also restricts execution of external tools from a sandbox. Verify the actual distribution/access architecture before promising seamless tool-driven cleanup. [Apple sandbox access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?changes=_4)

#### 4. Keep estimates and outcomes separate

Do not sum an app bundle, its child items, linked aliases, and shared libraries twice. Track filesystem identities and volume identity. Logical size, allocated bytes, reclaim estimate, moved-to-Trash bytes and measured volume-free-space change are different values. Allocated size alone does not resolve APFS shared blocks. [Apple file resource keys](https://developer.apple.com/documentation/foundation/urlresourcekey?language=objc)

The existing measured-space work is a strength. Retain qualifications around background disk activity and delayed Docker reclaim. Moving personal files to same-volume Trash does not immediately reclaim their storage. Do not count vendor guidance, offline/cloud-only data, or identified-but-unselected content as space recovered.

### Delivery sequence and proof of value

| Order | Deliverable | Evidence required |
|---|---|---|
| 1 | Repair/extend developer discovery and vendor cleanup semantics | uv uses native cleanup; configured npm/pip/pnpm/Homebrew paths found; source/config/credentials protected; owner activity and partial failures reported |
| 2 | Creative storage visibility and exact vendor guidance | Multiple FCP libraries and custom/external caches found; Adobe shared cache counted once; catalogs/originals/backups distinguished from generated files |
| 3 | Music inventory MVP | AU/VST/AAX/AUv3 represented; NI/Logic/Ableton/Arturia/Waves content visible; shared assets counted once; vendor action links work |
| 4 | Validated creator-cache cleanup | For each supported version/layout: clean selected artifacts, reopen app/project, rebuild/relink as promised, confirm no loss of originals or custom content |
| 5 | Project artifacts and guided archive/relocation | Recognized project boundaries; protected user additions; verified copy and destination usability; explicit source removal; offline dependencies retained as unknown |

Suggested acceptance matrix: default/custom path, multiple versions, renamed library, external drive online/offline, non-writable shared folder, missing originals, two owners sharing content, app/helper running, nested Git work, cloud placeholder, hard link/clone, interrupted cleanup, and partial scan. Fixtures test classification/protection; dedicated disposable projects/libraries test actual vendor behavior. No destructive tests against personal work.

For each shipped integration measure:

1. **Discovery coverage:** independently known supported artifacts found, with omissions explained.
2. **Classification accuracy:** no valuable originals/catalogs/presets/licenses admitted to cache cleanup in the reference corpus.
3. **Task success:** project opens, required instruments load, and promised rebuild/re-download behavior works after cleanup.
4. **Storage outcome:** candidate estimate versus measured volume change, with Trash and delayed reclaim separate.
5. **User comprehension:** user can explain what will disappear and how it returns before confirming.

Do not advertise universal app support, universal safety, or a fixed number of recoverable GB from documentation research alone. Publish an explicit integration list with the level supported: inventory, guidance, or verified cleanup.

### Decisions to grill next

1. Is the primary customer a developer, a video/photo creator, or a music producer? Shared infrastructure does not eliminate three different onboarding and workflow needs.
2. Is “visibility plus precise native guidance” sufficient to claim an integration, or must Cache Drop execute the action itself?
3. Should the no-admin boundary remain, accepting read-only visibility for many shared music installations?
4. Should generated creative media enter cleanup only when originals are online, or remain a manual advanced choice otherwise?
5. Do we keep plug-in uninstallation out of scope and differentiate through inventory/content management?
6. Which first two creator ecosystems deserve the cost of maintaining parsers and validating releases?
7. What observable outcome would make the user trust the promise: clearer ownership, more correctly identified reclaimable storage, or fewer steps to complete cleanup?

Recommendation for that discussion: stabilize existing developer semantics first, add FCP/Adobe visibility next, and ship music inventory before any automated music-content removal.

### Appendix: current-code evidence

Inspected HEAD: `67ccadaead5dbaf4dc0b46b877f1aaa925239845`. The checkout was inspected read-only; its existing untracked `app.log` was left untouched. Tests below were inspected, not executed.

| Finding | Source |
|---|---|
| App instantiates the built-in catalog and invokes discovery/guidance during scan | [CatalogCleanup.swift](/Users/bender/Workspace/mac-cleaner/Still/App/CatalogCleanup.swift:159) |
| Global developer-cache paths and actions, including uv direct deletion | [Catalog.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:162), [uv rule](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:183) |
| Native pnpm store prune and short hardcoded executable search list | [pnpm rule](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:172) |
| Per-project Xcode DerivedData, retained DeviceSupport versions, unavailable simulator cleanup | [Xcode rules](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:214) |
| Docker image/build-cache/stopped-container categories | [DockerCatalog.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/DockerCatalog.swift:4) |
| Generic cache matching depends on a bundle-ID folder mapping to an installed app; it does not discover arbitrary Adobe/Common or sample-library paths | [AppCaches.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/AppCaches.swift:61) |
| Audio guidance is an aggregate of system and user Audio/Plug-Ins roots; Photos uses one exact default library path | [audio guidance](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/GuidanceCatalog.swift:35), [Photos guidance](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/GuidanceCatalog.swift:23) |
| Guidance appears as App-managed storage with size, explanation and Open action | [GuidanceSection.swift](/Users/bender/Workspace/mac-cleaner/Still/App/GuidanceSection.swift:4) |
| Large/old-file candidate generation: regular files, >=500 MB OR unused for 90 days, up to 500; protects Library and Git trees | [UserFiles.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/UserFiles.swift:9), [protection](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/UserFiles.swift:28) |
| Generic scanner skips package descendants and has 100,000-entry / 30-second caps | [FolderScanner.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/FolderScanner.swift:120) |
| Existing layout overrides detect/suppress unsupported relocated browser layouts; they do not discover the new path | [LayoutOverride.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/LayoutOverride.swift:3) |
| Global protection includes Photos/Music/Logic/GarageBand packages and app/archive bundles | [Protection.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Protection.swift:7) |
| Candidate preflight checks owners, identity, scope, symlinks, exclusions, permissions and protected paths | [CandidateCheck.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/CandidateCheck.swift:89) |
| Shared journaled executor, preview/cancel, per-item outcomes and measured-space reporting | [CleanupExecutor.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/CleanupExecutor.swift:17) |
| Known-location sizer can read package contents; this is distinct from generic explorer behavior | [KnownLocationSizer.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/KnownLocationSizer.swift:12) |
| Guidance is sized separately and never becomes executable candidates | [CatalogGuidance.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/CatalogGuidance.swift:8) |
| Existing fixture tests cover developer cleanup, file selection/protection and guidance refusal | [DeveloperCacheTests.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Tests/StillCoreTests/DeveloperCacheTests.swift:17), [UserFilesTests.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Tests/StillCoreTests/UserFilesTests.swift:33), [GuidanceTests.swift](/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Tests/StillCoreTests/GuidanceTests.swift:17) |
| Current product boundaries and latest decisions | [SPEC.md](/Users/bender/Workspace/mac-cleaner/docs/SPEC.md:135), [RESET decisions](/Users/bender/Workspace/mac-cleaner/docs/RESET.md:115) |

No dedicated Final Cut, Adobe, DAW or sample-library integration was identified in the inspected app/core source. This is a source-search finding, not proof about unpublished branches or other copies of the product.

## Detailed competitor evidence

## Drop Cache: competitor research

Research date: 2026-10-26. Official product documentation, repositories, and developer App Store descriptions only. These are documented capabilities and claims, not hands-on test results. Implementation inference is explicitly marked.

### Competitive findings

| Competitor | Documented workflow | Practical lesson for Drop Cache |
|---|---|---|
| CleanMyMac | Scan Cleanup, review by junk category, adjust preselection, clean, inspect log. User caches grouped by app; Xcode groups include DerivedData, modules, device support, logs, archives, simulators. Module caches and archives are not preselected; Gradle cache also excluded from automatic selection. | Ownership, explanations, and cautious default selections are already baseline. Do not treat archives as disposable caches. |
| CleanMyMac CLI (public beta) | Separate shared-cache `clean` and project-artifact `purge`; project grouping, 7-day artifact preselection, user review/confirmation, ignore paths, disk explorer. | Developer cleanup is already directly contested by a mainstream incumbent. |
| DaisyDisk | Disk visualization and manual file collector; separate hidden/purgeable reporting; warns users to manage library-based content in its owning application. | A clear storage map with honest accounting matters as much as one-click cleanup. |
| DevCleaner | Xcode-specific inspection of generated data and archives, including device symbols, DerivedData, docs, old simulator/device logs. | Narrow app-specific understanding beats blanket folder deletion; rules need version maintenance. |
| Mole | Dry runs, known-target cleanup, project artifact review, safety protections, ignore list, activity log. | Open-source alternatives already expose sophisticated protection rules. |
| Sensei | Advertises cache/log/large-download/installer cleanup, app leftovers removal, macOS disk scanner. | Broad cleaner + uninstaller + storage visibility is common. Reviewed public page does not document creator-project dependency analysis. |
| PlugInfo | Read-only audio-plugin inventory with architectures, publisher, format filters, Finder reveal, paths/details export, live refresh. | Music users value compatibility and inventory, independently of deletion. |
| Audio Plugin Uninstaller | Receipt-based complete plugin removal with shared-file protection; per-plugin/per-format fallback. | Receipt provenance and shared-asset ownership are valuable foundations for audio management. |
| AppCleaner | Drag an app into its window, discover related files, delete selected result. | Basic app-associated cleanup is a mature commodity feature. |

CleanMyMac cleanup workflow and automatic selection rules: [System junk](https://macpaw.com/support/cleanmymac/knowledgebase/system-junk), [group descriptions](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/system-junk-cleanup-list).

### CleanMyMac: useful detail and limits

Its My Clutter large-file workflow scans internal or external locations, shows files at least 50 MB, groups by kind/size/access date, supports Quick Look and Finder reveal, and requires manual selection. Removal bypasses Trash. This is generic file discovery; these documents do not establish that it knows whether a video is an original, proxy, render, or required project dependency. [Large and old files](https://macpaw.com/support/cleanmymac/knowledgebase/large-and-old)

Duplicate results start above 100 KB, require user selection, and delete permanently; Photos assets instead enter Recently Deleted. Accordingly, avoid claiming that competitors only do filesystem scanning: at least this workflow integrates with the Photos library. [Duplicate files](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/duplicate-files)

The vendor describes its Safety Database as app-specific rules and exceptions, including sensitive data stored inside cache locations, running-app handling, and unusual uninstallation paths. It explicitly notes that Spotify keeps offline music among cache files. This is a warning against assuming everything in `Caches` is disposable. Marketing safety claims remain unverified here. [Safety Database](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/safety-database)

Current uninstaller docs say it removes related components outside Applications; the App Store edition cannot delete core binaries of App Store apps. Distinguish current CleanMyMac from old CleanMyMac X docs: older X edition guidance omits some features in App Store builds. [Current uninstaller](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/uninstaller)

The official CLI repository says public beta and potentially changing behavior. It documents Homebrew, npm/Yarn/pnpm, pip/Poetry/uv, Cargo/Go, CocoaPods, Docker, IDE, Maven/Gradle, Bun/Deno/mise, Xcode, and AI tool cleanup. Project purging covers dependencies, build output, virtual environments, and indexes; grouped results and age selection provide context but age does not prove disposability. Its documented feature breadth means a strategy built only around finding `node_modules` and DerivedData is weak differentiation. [Official CLI README](https://github.com/MacPaw/cleanmymac-cli)

### DaisyDisk: visibility, accounting, and library ownership

DaisyDisk distinguishes immediately free storage from macOS purgeable storage, and places purgeable in the available gauge consistently with Finder. Its guide says APFS purgeable space lies outside scannable areas and is exposed at macro level; forcing reclaim is not in its App Store edition. This is vendor documentation, not an independently validated statement of every macOS purgeable behavior. Drop Cache should avoid adding purgeable and ordinary candidate files into one inflated savings number. [Purgeable space](https://daisydiskapp.com/guide/4/en/PurgeableSpace/)

Its guide advises using iTunes to remove library items and Steam to remove games, because direct deletion can break library links. It warns about files under Application Support. The comparable opportunity for Drop Cache is to explain ownership and offer the correct vendor action, rather than implying every large file is trash. [Locating space wasters](https://web.daisydiskapp.com/guide/4/en/LocatingSpaceWasters)

Its cloud scan documentation describes scanning supported cloud providers without building a local file cache. Its FAQ says no iCloud scan API is available. Cloud inventory, local residency, and local storage savings are different concepts. [Cloud scans](https://daisydiskapp.com/guide/4/en/CloudScan/), [FAQ](https://web.daisydiskapp.com/support/faq)

### Developer specialists

DevCleaner's README explains that archives contain builds and debugging information used for crash symbolication; DerivedData is rebuildable; device symbols support debugging. It explicitly depends on internal/undocumented Xcode structures and may break with newer Xcode versions. Its README and releases disagree about default selection: release 2.5 says nothing is selected automatically. Treat release notes as evidence of changed behavior and test the shipping binary before competitive claims. [Repository](https://github.com/vashpan/xcode-dev-cleaner), [releases](https://github.com/vashpan/xcode-dev-cleaner/releases)

Mole's current README documents project-aware purge, protecting nested Git repositories, Git-tracked files, and deployment keypairs. Recent or unverifiable activity stays unselected. It identifies incomplete scans and estimated savings. Uninstall/analyze normally use Trash; clean/purge/installer remove permanently. Uninstall keeps settings/plugins by default and guards shared data used by other installed copies. These are strong baseline safety ideas, not evidence of correctness on arbitrary creator libraries. Main-branch documentation may describe unreleased behavior. [Mole README](https://github.com/tw93/Mole)

### Music-production specialists

PlugInfo's developer description documents CPU architectures (including legacy code), publisher links, sortable/filterable metadata, Finder selection, copy-paths and full-details exports, and automatic refresh. Version notes add TSV export. It is an inventory/maintenance entry point; the developer description does not claim full library uninstall or project dependency mapping. Avoid relying on user-review assertions about specific unsupported vendors. [Developer App Store listing](https://apps.apple.com/us/app/pluginfo/id1626412949?mt=12)

Wide Blue Sound's Audio Plugin Uninstaller has two modes. Uninstaller mode reads original installation receipts and reverses installation while preserving files used by other plugins. Plugins lacking normal receipts require All Plugins mode, which shows individual binaries and allows format filters and Finder reveal. It supports VST3/VST2/AU/AAX/CLAP/RTAS. It advertises inspection of package files for presets/preferences; it does not establish reliable removal of files created after installation, custom sample locations, cloud licenses, or every vendor library dependency. [Official product page](https://www.widebluesound.com/audio-plugin-uninstaller/)

Sensei's official page supplies broad cleanup/uninstaller claims but few operational details; absence of detailed creator workflows from that page is not proof those features do not exist. [Sensei](https://cindori.com/sensei)

AppCleaner documents the simple app-drop/related-files/delete workflow; no reviewed vendor documentation establishes sample-library or creator-project dependency management. [AppCleaner](https://freemacsoft.net/appcleaner/)

### Product implications (research inference)

1. Compete on explainable ownership: show app/project/product, artifact purpose, regeneration/download cost, custom location, dependent projects, last verified rule version, and why the proposed action is valid.
2. Separate regenerable artifacts, replaceable downloaded content, and irreplaceable original work. Unused format binaries are a manual choice, not automatic music trash.
3. Make native app/vendor-manager actions first-class: clean renders, manage sound packs, uninstall product, relocate library, reveal in Finder. Discovery can provide value before deletion is supported.
4. Build a tested rule registry with app versions and exceptions. Folder-name heuristics and age alone are insufficient.
5. Report scanned/missed/unavailable locations, estimated versus actual reclaimed bytes, and shared/cloud/purgeable accounting. Do not claim savings from online-only files.
6. Benchmark on fixed fixtures and installed-app versions before claiming superior cleanup or safety; this research is a documented-capability comparison only.

## Detailed repository audit

## Cache Drop repository audit

Read-only source inspection on 2026-10-26. Canonical checkout `/Users/bender/Workspace/mac-cleaner`, HEAD `67ccadaead5dbaf4dc0b46b877f1aaa925239845`. No builds, cleanup actions, user-data scans, or tests run. Findings describe implementation and fixture tests present, not verified runtime outcomes. Paths below are absolute to allow precise tracing.

### What currently exists and is wired

- The SwiftUI app instantiates `Catalog(rules: BuiltInCatalog.rules)`; scanning calls catalog discovery and then guidance, collects running owners and access issues, and records growth. This is current app integration, not just dormant types. `/Users/bender/Workspace/mac-cleaner/Still/App/CatalogCleanup.swift:9`, `:159`, `:173`, `:179`, `:187`, `:190`.
- Shared model supports delete, Trash, tool, iCloud eviction, and guidance; each rule carries owner, consequence, protected patterns, location, optional custom-layout guards and item adapters. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:5`, `:84`, `:95`, `:106`, `:128`.
- Developer rules: npm `~/.npm/_cacache`; Yarn `~/Library/Caches/Yarn` and `~/.yarn/berry/cache`; pnpm `~/Library/pnpm/store` via `pnpm store prune`, metadata `~/Library/Caches/pnpm` deleted; uv `~/.cache/uv`; pip `~/Library/Caches/pip`; Cargo `~/.cargo/registry` and `~/.cargo/git`; Gradle `~/.gradle/caches`; CocoaPods `~/Library/Caches/CocoaPods`; Homebrew `brew cleanup -s` then cache-directory deletion. All except pnpm store/Homebrew are permanent folder deletion. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:162`–`:213`.
- Xcode per-project DerivedData is deleted; DeviceSupport keeps two newest versions per platform; unavailable simulators use native simctl. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:214`–`:233`.
- Docker has separately selectable prune kinds: images, build cache, stopped containers; never volumes. Sizes come from daemon reclaimable estimates. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/DockerCatalog.swift:4`, `:16`, `:46`.
- Other catalog sources include browser-specific caches, leaked Chrome code-sign clones, updater downloads, app caches, logs/crash reports, Downloads installers and old large files, Hugging Face/Ollama, narrowly scoped Claude VM unpacked-image rule, and iCloud. Catalog assembly: `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:160`; model specifics `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/ModelCatalog.swift:7`, `:19`, `:30`.
- Generic app caches only target visible `~/Library/Caches/*` folders that look like bundle IDs and map to installed non-Apple apps. Unknown owners and all com.apple.* folders are omitted. This will not automatically find an `Adobe/Common/Media Cache` folder or most content in Application Support. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/AppCaches.swift:13`, `:20`, `:28`, `:61`.
- Large/old file explorer is implemented and wired into cleanup planning. User picks a folder; finished scanner observations produce up to 500 regular-file candidates, largest first: >=500 MB OR not used in 90 days. No preselection, Trash action. UI supports ordering by size or last use. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/UserFiles.swift:4`, `:9`, `:21`; `/Users/bender/Workspace/mac-cleaner/Still/App/CatalogCleanup.swift:199`; `/Users/bender/Workspace/mac-cleaner/Still/App/StorageExplorer.swift:301`, `:306`.
- Guidance is visible on Overview as App-managed storage rows with size, description, Open button and access status. Current rows: device backups, Mail/Messages attachments, one default Photos library, Time Machine snapshots, Xcode archives, audio plug-ins. `/Users/bender/Workspace/mac-cleaner/Still/App/GuidanceSection.swift:4`; `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/GuidanceCatalog.swift:10`.

### Creative-media and music gaps

1. No dedicated Final Cut, Premiere, After Effects, Lightroom, Photoshop, Logic, Ableton, Native Instruments, Kontakt, or sample-library code/rules found in current core/app source. Generic large-file explorer can surface exported movies/raw photos chosen by the user, but cannot attribute them to projects or distinguish originals from reproducible previews, proxies, renders or media caches.
2. The entire music offering is one guidance total for `/Library/Audio/Plug-Ins` and `~/Library/Audio/Plug-Ins`, with generic vendor-uninstaller advice and a Finder-open destination. No individual plugin inventory, format/version/vendor, app ownership, duplicate architecture, installer/library relationships, sample packs, presets, sound libraries, custom library volumes or vendor-manager integration. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/GuidanceCatalog.swift:35`.
3. Photos guidance covers only `~/Pictures/Photos Library.photoslibrary`; custom names, multiple libraries and external libraries require expansion. It opens Photos and makes no changes. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/GuidanceCatalog.swift:23`.
4. `FolderScanner` does not descend into packages; large-file candidates accept only `.file` observations. Thus packages such as Final Cut libraries, Logic projects or Photos libraries do not gain useful internal accounting through the generic explorer. Scanner also has hard 100,000-entry and 30-second caps; external media trees can exceed those. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/FolderScanner.swift:120`, `:204`, `:232`, `:295`; `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/UserFiles.swift:32`.
5. Generic explorer protects everything inside the user's Library and anything in a Git working tree, including a deliberately picked build folder in a project. This is a sensible existing boundary but means it cannot serve as a developer project-artifact cleaner or Adobe cache cleaner just by asking users to choose a folder. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/UserFiles.swift:28`, `:38`, `:51`.
6. Existing global protection explicitly covers `.band`, `.logicx`, `.musiclibrary`, Photos libraries, application/framework/bundle packages and archives. DAW/media formats need a deliberate inventory/protection matrix before adding app-aware actions; project references cannot be inferred from file size/age. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Protection.swift:7`.

### Developer coverage and safety gaps to resolve

- Fixed defaults are not full coverage: no current project discovery/classification for node_modules, Python virtualenvs, Rust target, Gradle project build folders, Swift .build, frontend build output, Android SDK/emulators, Maven, NuGet, Go, Ruby/gems or SDK managers. Avoid interpreting broad developer-cache marketing as coverage of all development trash.
- `LayoutOverride` detects plist/JSON key or text and suppresses a rule; it does not return or scan the relocated directory. Only browser rule definitions currently use it. Developer configured cache paths/environment changes are not resolved. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/LayoutOverride.swift:3`, `:12`, `:38`; `/Users/bender/Workspace/mac-cleaner/Still/App/CatalogCleanup.swift:378`.
- uv is explicitly direct `.cache/uv` deletion; verify current Astral safety guidance before treating this as interchangeable with tool-mediated cleanup. Source fact: `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:183`–`:187`. This report does not assert a verified real-world corruption outcome.
- Installed-command discovery uses short hardcoded executable lists, e.g. pnpm Homebrew or ~/Library/pnpm paths; nonstandard/version-manager installations can be missed. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/Catalog.swift:175`–`:177`.
- 'Known cache path' is still not proof of complete disposability. Existing protections are valuable but finite-depth: git-checkout detection and explicit protected-name scans, not project/media dependency analysis. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/CandidateCheck.swift:56`.

### Foundations worth reusing

- No preselection; preview-only defaults true. `/Users/bender/Workspace/mac-cleaner/Still/App/CatalogCleanup.swift:30`, `:51`, `:60`.
- Candidate check rejects guidance, unknown/running owners, changed identity, scope/symlink changes, protected ancestors, excluded paths, cloud items, non-owned files and unavailable permissions; regular files also require unchanged size/mtime. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/CandidateCheck.swift:89`–`:136`.
- Shared executor journals frozen plans, rejects replay, handles cancellation and preview, reports per-item measured free-space change separately from bytes moved to Trash, and uses descriptor-rooted rename/identity checks before deleting. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/CleanupExecutor.swift:17`, `:58`, `:72`, `:108`, `:188`.
- Metadata-only known-location sizing supports package contents without generic scanner's entry cap; 60-second default per location, hardlink dedup within that tree, incomplete totals lower bounds. Guidance uses 10-second budgets and labels uncertainty. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/KnownLocationSizer.swift:12`; `/Users/bender/Workspace/mac-cleaner/Still/App/CatalogCleanupModel+Guidance.swift:7`.
- Guidance never becomes executable candidates; can read system-root locations without expanding write scope. Its model already separates unknown/inaccessible/lower-bound sizes and supports native app/settings/Finder targets. `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Sources/StillCore/CatalogGuidance.swift:8`, `:19`, `:32`, `:40`.

### Existing verification and product constraints

- Fixture tests cover developer cache discovery/process recognition, permanent-delete actions, protected ccache and pnpm prune: `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Tests/StillCoreTests/DeveloperCacheTests.swift:17`, `:40`, `:63`, `:200`.
- Generic movie selection/Trash, non-selection safety, preview, library and Git protection tests: `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Tests/StillCoreTests/UserFilesTests.swift:33`, `:51`, `:93`, `:111`, `:137`.
- Guidance tests establish sizing-only behavior and executor refusal, access unknowns, plugin lower bounds: `/Users/bender/Workspace/mac-cleaner/Packages/StillCore/Tests/StillCoreTests/GuidanceTests.swift:17`, `:35`, `:58`, `:73`.
- Source has evolved beyond RESET's historical introductory complaint that only Downloads works; do not repeat that as current truth. Docker/guidance/explorer and What grew are integrated in source despite docs' 'After M1' sequencing. Cannot claim completion or measured field outcomes without local functional verification.
- Current out-of-scope decisions exclude uninstaller, duplicates, automatic cleanup, changing Photos libraries, admin helpers, blanket Application Support cleanup; product expansion into music 'management' should distinguish inventory/native-manager handoff (fits current direction) from uninstall/relocation (scope decision). `/Users/bender/Workspace/mac-cleaner/docs/SPEC.md:135`.
- RESET decisions require user-owned write scope, native app close checks and permanent deletion for regenerable data; pnpm is an explicit later exception. `/Users/bender/Workspace/mac-cleaner/docs/RESET.md:115`, `:116`, `:132`, `:133`, `:135`. A uv native-command exception or creative-app purge workflow should become an explicit decision if adopted.

### Suggested blueprint direction (inference)

Keep shared action/execution safety layer; add an application/content discovery layer capable of resolving preferences and picked external roots, then classifying originals/projects, regenerable generated media, downloadable purchased content, and unknown data separately. Each application view should explain bytes by subtype, actual location, consequence/recovery mechanism and native manager. Start with read-only inventories and native cleanup guidance for Final Cut/Adobe/DAWs, then promote only vendor-validated generated-data actions. Expand developer cleanup through explicitly selected project roots and ecosystem-aware artifact rules; do not remove Git protection globally. Define coverage tests against real vendor versions and configuration variants in addition to current synthetic fixtures.

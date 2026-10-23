# macOS storage cleanup: research and product recommendations

Research date: October 22, 2026. Scope: primary-source research for a personal macOS cleaner, with particular attention to a 512 GB Mac using iCloud. No inspection of this Mac or deletion of its files was performed. Priorities below are product judgments, not measurements of prevalence or promised savings. Actual reclaimable space requires a local scan.

## Main finding

A useful cleaner should explain who owns disk usage and offer the correct action for each kind of data. “Old,” “large,” “hidden,” and “System Data” do not establish that a file is junk. Apple describes System Data as a catch-all including caches, logs, VM files, application support, plug-ins, and other runtime resources. It is not a directory that can be safely emptied. [Apple: Storage settings](https://support.apple.com/en-ie/guide/mac-help/mchl3d437fbc/27/mac/27)

Use four distinct actions: delete unwanted personal files; evict downloaded cloud copies; rebuild generated artifacts later; delegate management to the owning application or macOS. The classification and prioritization are recommendations derived from the mechanisms documented below.

## Why iCloud does not solve all local storage pressure

1. iCloud Drive optimization is demand-driven. Recently used content can remain local; Keep Downloaded explicitly retains selected files or folders. Finder’s Remove Download removes the local downloaded copy. [Apple: iCloud Drive files](https://support.apple.com/en-ie/guide/mac-help/mchl1a02d711/27/mac/27)
2. Photos has a separate setting. Photos > Settings > iCloud > Optimize Mac Storage retains smaller local versions when space is limited; Download Originals retains full-resolution originals locally as well as in iCloud. Optimization therefore still needs local space. [Apple: Photos storage](https://support.apple.com/en-ie/guide/photos/phta9b4673b4/12.0/mac/27) [Apple: Photos settings](https://support.apple.com/guide/photos/photos-settings-pht5156cc968/12.0/mac/27)
3. Cloud capacity can itself be exhausted. Apple says full iCloud storage stops new photo uploads and prevents Drive and other apps from staying current. A cleaner must not assume a file is safely uploaded just because it sits in a cloud folder. [Apple: iCloud storage](https://support.apple.com/en-us/108922)
4. Deletion and eviction have different consequences. Messages deletion propagates to other devices using Messages in iCloud. Foundation’s iCloud eviction method removes only the local copy; ordinary removal can delete the cloud copy too. [Apple: Messages deletion](https://support.apple.com/guide/messages/delete-messages-and-conversations-icht1035/mac) [Apple: iCloud eviction API](https://developer.apple.com/documentation/foundation/filemanager/evictubiquitousitem(at:))

Product implication: show local bytes separately from cloud file sizes, clearly label local-only eviction, respect pinned downloads, and check upload status. Do not traverse cloud storage by reading every file’s contents: that can require downloads. Treat support for third-party cloud providers as separate integrations; the iCloud API is not proof that arbitrary providers support the same operation.

## What to look for

### 1. Downloaded cloud files and photo originals

**Why useful:** local copies may be removable without discarding the user’s underlying content. For Drive, offer Finder’s Remove Download or a validated API integration. For Photos, direct users to its optimization setting; do not manipulate the library internals. Apple’s developer guidance demonstrates checking `ubiquitousItemIsUploaded` before eviction. Prototype this against the target macOS versions and access model before promising whole-Drive automation. [Apple: reducing disk usage](https://developer.apple.com/documentation/xcode/reducing-your-app-s-disk-usage)

**Regrowth:** opening a file can download it again; pinned content is intentionally local. Offline availability is lost after eviction. This is a storage policy feature, not junk deletion.

### 2. iPhone and iPad backups

**Detection:** `~/Library/Application Support/MobileSync/Backup/`. Group by complete backup, device, and date where reliably identifiable. Apple supports Finder > connected device > General > Manage Backups > Delete or Archive. Never remove random files inside an individual backup. These are recovery assets, so mark them for explicit review. [Apple: backup locations and management](https://support.apple.com/en-ae/108809)

### 3. Downloads, installers, archives, exports, and Trash

**Detection:** start with Downloads and user-selected document folders; highlight large disk images, installers, compressed archives, recordings, and exports for review. File extensions and age are candidate signals, not permission to delete. Apple recommends reviewing Downloads and unused media, and notes that moving an item to Trash does not release its storage until Trash is emptied. [Apple: freeing storage](https://support.apple.com/en-us/102624)

**Product design:** preview files, reveal them in Finder, and use Trash for ordinary files. Report “moved to Trash” separately from “space recovered.” A same-volume quarantine directory also retains the data, so it cannot honestly count as recovered space.

### 4. Downloaded entertainment and sound libraries

TV, Music, Books, and Podcasts include purchases that can be removed locally and downloaded again; use each app’s own controls. Music Creation is a separate storage category. [Apple: category definitions](https://support.apple.com/en-ie/guide/mac-help/mchl3d437fbc/27/mac/27)

Logic and MainStage provide library relocation workflows. Current Logic also provides sound-pack deletion controls. Versions matter: newer releases use a consolidated `Logic Pro Library.bundle`, while older releases store assets in several locations. Do not treat all samples or loops as expendable—projects may depend on them. [Apple: relocate sound library](https://support.apple.com/en-ie/111094) [Apple: manage sound packs](https://support.apple.com/nl-nl/guide/logicpro/lgcp8b3abc1c/12.3/mac/15.6)

### 5. Creative application generated media

Final Cut Pro accumulates render files, optimized media, and proxies. Its Delete Generated Files commands preserve original media, and the generated files can be recreated from originals. Prefer those commands to deleting inside a library package. Warn about rebuild time and confirm originals remain accessible. Similar integrations for other creative apps need their own vendor documentation. [Apple: render files](https://support.apple.com/en-ie/guide/final-cut-pro/ver68a8c250/mac) [Apple: optimized and proxy files](https://support.apple.com/lt-lt/guide/final-cut-pro/verb8e5f6fd/mac)

### 6. Browser and application caches

Foundation distinguishes caches, which should be recreatable, from Application Support, which holds required support data. Typical non-sandboxed locations are `~/Library/Caches` and `~/Library/Application Support`; sandboxed apps use their containers. A folder’s name is not enough to validate every app’s behavior. [Apple: file-system use](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)

Browser caches are distinct from cookies, history, passwords, and website databases. Chrome’s cached images/files can be cleared separately; deleting website data can erase offline application data, while cookies affect logins. Deleting Chrome download history does not delete downloaded files. [Google: browsing data](https://support.google.com/chrome/answer/2392709) [Google: cookies](https://support.google.com/chrome/answer/95647)

**Recommended policy:** only known cache rules, owner app closed, preview and exclusions. Show likely regrowth and performance cost. Cache clearing is often temporary relief; do not promise that caches are inherently harmful or that clearing them makes the Mac faster. Google explicitly notes that subsequent page loads can slow because assets must reload. [Google: cache behavior](https://support.google.com/accounts/answer/32050)

### 7. Mail and Messages attachments

These are personal records, not a generic cache. Apple supports reviewing/deleting Messages attachments and configurable retention; deletions synchronize when Messages in iCloud is enabled. Prefer supported interfaces and explain the synchronization effect. Never remove database records or attachment files behind the app’s back. [Apple: Messages](https://support.apple.com/guide/messages/delete-messages-and-conversations-icht1035/mac)

Mail provides deletion and mailbox retention controls. Cleanup should use the application’s semantics, with explicit attention to account/server effects rather than assuming everything is a disposable local download. [Apple: Mail storage](https://support.apple.com/guide/mail/delete-emails-and-manage-storage-mlhlp1001/16.0/mac/27)

### 8. Unused applications and suspected leftovers

Apple recommends a vendor uninstaller when available because it can remove login items, extensions, and data stored elsewhere. Removing an app does not remove documents created with it. [Apple: uninstall applications](https://support.apple.com/en-us/102610)

**Recommendation:** associate suspected leftovers with bundle identifiers and explicit vendor rules, but label uncertain ownership. Absence of an app at one expected path does not prove its support data is abandoned: applications can be moved, temporarily absent, or share resources. Do not automatically erase Application Support, Containers, Group Containers, preferences, saves, or license data.

### 9. Local AI model downloads

For Ollama, inventory models through `ollama ls` and remove selected models through `ollama rm <model>`. Treat these as user-selected downloadable assets, not arbitrary blob files to delete. Other model tools require separate adapters. [Ollama: CLI](https://docs.ollama.com/cli)

Apple Intelligence also downloads on-device models. Apple documents a 7 GB storage requirement and says turning the feature off removes its models; this is a requirement, not a guaranteed amount your cleaner will reclaim. Offer a settings explanation if relevant, not direct deletion of protected assets. [Apple: Apple Intelligence](https://support.apple.com/en-in/121115)

### 10. Other users and migrated accounts

Apple recommends checking unused user accounts and undeleted data from removed accounts, including shared files. Report these separately and leave account removal to the supported system workflow. User ownership and access boundaries matter. [Apple: freeing storage](https://support.apple.com/en-us/102624)

### 11. Logs and temporary files

Surface unusually large app-owned logs or persistent growth as a diagnosis opportunity. Use documented retention rules and avoid active files. Apple includes logs and temporary files in System Data, and describes temporary storage as nonpersistent with no guaranteed purge schedule. File age alone does not prove a file is inactive or safe to remove. [Apple: category definitions](https://support.apple.com/en-ie/guide/mac-help/mchl3d437fbc/27/mac/27) [Apple: temporary storage](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)

## Developer storage: detailed cleanup matrix

These rules apply only when the corresponding tools are installed. Query each tool for configured paths; defaults can change.

| Category | What it contains / identification | Cleanup and cost | Cleaner design |
|---|---|---|---|
| Xcode DerivedData | Default `~/Library/Developer/Xcode/DerivedData`; indexes, build logs, build products and intermediates. Can be configured elsewhere. | Apple explicitly says it is often large and can be recreated from source. Rebuild/reindex cost. | Strong candidate when Xcode is idle; identify per-project directories and custom locations, retain recent projects by default. [Apple](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html) |
| Simulator runtimes and devices | Shared runtime OS packages versus individual simulated devices containing test applications/data. | Apple documents removing runtimes via Xcode Settings > Components and devices via Devices and Simulators. User loses ability to test that runtime until reinstall; deleting devices discards their test state. | Route to Xcode-supported management. Avoid hardcoded deletion of runtime asset/volume folders. Runtime and device state need separate UI. [Apple](https://developer.apple.com/documentation/safari-developer-tools/adding-additional-simulators) |
| Xcode Archives | Default `~/Library/Developer/Xcode/Archives`; contains archived binaries and matching dSYMs. | Do not classify as expendable cache. Apple says retain every distributed build archive, because crash diagnosis needs its specific symbols. Rebuilding identical source does not guarantee matching UUID. | Explicit review or move to external storage, with release/version labels. Never bulk auto-delete by age. [Locations](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html), [symbols](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information), [missing symbols](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file) |
| Docker objects | Stopped containers, dangling/unused images, build cache, networks and persistent volumes inside Docker Desktop VM disk. | `docker system df -v` inventories objects. Default `docker system prune` removes stopped containers, unused networks, dangling images and unused build cache. Persistent volume deletion is separate and can destroy databases. | Use Docker API/CLI, show precise object list, distinguish stopped container writable data from reproducible images/cache, exclude volumes from default cleanup. [Pruning](https://docs.docker.com/engine/manage-resources/pruning), [Mac FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) |
| Docker disk image | A sparse VM image has logical maximum size different from actual host allocation. | Docker says deleting objects may take time to release host bytes; files removed inside running containers do not necessarily free host disk automatically. Reducing disk maximum deletes current disk and loses containers/images. | Never report logical image capacity as reclaimable. Never resize as a cleanup shortcut. Measure host allocated bytes before/after supported pruning. [Mac FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) |
| Homebrew cache/old versions | Default `~/Library/Caches/Homebrew`, configurable; outdated downloads, old installed formula versions and stale lock files. | `brew cleanup -n` previews; `brew cleanup` removes these and downloads older than configured age (default 120 days). `brew autoremove --dry-run` previews no-longer-needed dependencies. | Use native preview and cleanup; distinguish uninstalling unused dependencies from expiring downloads. Homebrew already performs periodic cleanup. [Manpage](https://docs.brew.sh/Manpage), [FAQ](https://docs.brew.sh/FAQ) |
| npm package cache | Configured cache, default `~/.npm` on POSIX; package download data plus separate npx entries. | `npm cache verify` garbage collects unneeded data and verifies integrity. `npm cache clean --force` is space reclamation, not routinely necessary repair; cache is self healing and grows as new packages install. | Query configuration; expose verify and optional purge, preserve installed packages/source. npx cache supports inventory/removal in modern npm. [npm](https://docs.npmjs.com/cli/v11/commands/npm-cache/) |
| pip cache | HTTP responses and built wheels, default macOS `~/Library/Caches/pip`, configuration can change. | `python -m pip cache info/dir` inventories; `pip cache purge` removes HTTP and wheel caches. Subsequent installs redownload/rebuild. Internal cache structure is not stable. | Use matching environment's supported CLI; do not parse undocumented cache tree. Keep caching enabled normally. [Cache command](https://pip.pypa.io/en/stable/cli/pip_cache/), [caching](https://pip.pypa.io/en/stable/topics/caching/) |
| pnpm store | Content-addressed shared store; `pnpm store path` discovers it. | `pnpm store prune` removes unreferenced packages; later installs may redownload, including on branch switches. | Use native prune and version-aware output, do not recursively remove arbitrary linked stores. [pnpm](https://pnpm.io/cli/store) |
| Yarn caches | Yarn version and project settings matter: Classic global cache versus modern local/global archives. | `yarn cache clean` and modern `--mirror`/`--all` have different scope. | Never assume `.yarn/cache` is junk: Yarn supports zero-install repos which deliberately commit cache alongside `.pnp.cjs`. [Modern clean](https://yarnpkg.com/cli/cache/clean), [Classic](https://classic.yarnpkg.com/lang/en/docs/cli/cache/), [zero installs](https://yarnpkg.com/cli/install) |
| Local iPhone/iPad backups | `~/Library/Application Support/MobileSync/Backup/`. iCloud use does not establish whether local backups exist. | Finder > selected device > General > Manage Backups supplies Delete/Archive/Show in Finder. Apple says deleted backups cannot be recovered. | Treat as user data and display device/date; delete whole backups through management, never individual contents. Archive protects against replacement by later backups but does not move data off disk or free space. [Apple](https://support.apple.com/108809) |


## Storage that should not be marketed as junk

- **Time Machine local snapshots:** Apple counts their storage as available and automatically ages or removes snapshots when needed. Show them as system-managed recovery storage, separate from ordinary cleanup candidates. Apple documents temporarily disabling automatic backups as a manual deletion route; making that routine sacrifices useful recovery history. [Apple: local snapshots](https://support.apple.com/en-ie/102154)
- **Swap, runtime system files, protected OS resources:** classify and explain rather than delete. System Data includes VM and runtime resources; inaccessible files are not evidence of waste. [Apple: storage categories](https://support.apple.com/en-ie/guide/mac-help/mchl3d437fbc/27/mac/27)
- **Photo duplicates:** use Photos’ Duplicates merge feature. It retains one original and sends removed duplicates to Recently Deleted. A filesystem-level duplicate detector does not understand the Photos catalog. [Apple: photo duplicates](https://support.apple.com/en-ie/guide/photos/-pht5a3157c1d/mac)
- **Application support and shared containers:** may contain databases, configuration, downloaded assets, or valuable app data. No blanket cleanup rule. [Apple: file organization](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)

## Getting storage accounting right

1. **Logical size is not recovered space.** APFS clones share unchanged blocks; deleting one copy may release much less than its apparent size. APFS also supports snapshots, sparse files, and space sharing. Duplicate content is therefore not sufficient evidence for a savings claim. [Apple: APFS](https://developer.apple.com/documentation/foundation/about-apple-file-system)
2. **Allocated size is a better observation, not a guarantee.** `totalFileAllocatedSizeKey` exposes allocated bytes including metadata. Do not describe summed per-file allocations as exclusively owned blocks or an exact reclaim estimate. [Apple: allocated size](https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey)
3. **Available and free are different.** Apple says available includes free storage and purgeable caches; storage can be reported as both used and available. Do not add purgeable capacity twice. [Apple: file/storage accounting](https://support.apple.com/en-mt/guide/mac-help/syspf5a64aa6/27/mac/27)
4. **Use volume APIs too.** Foundation exposes total, available, and important/opportunistic-use capacities. Relevant disk-space APIs carry required-reason privacy declarations; check the current requirements during implementation. [Apple: important-use capacity](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey)
5. **Measure outcomes with qualifications.** Compare volume availability before and after completed cleanup; background writes, snapshots, open file handles, and regeneration can affect observations. Present candidate estimates and measured change as different fields. This is an engineering recommendation, not a claim that a before/after reading isolates causality perfectly.

## Suggested first release

Build a native inventory and guided cleanup application with a small set of well-supported actions:

1. A read-only size explorer grouped by owner and purpose, starting with user folders and known storage producers.
2. Large Downloads/installers review, app inventory, local device backup inventory, and cloud-download explanation.
3. Optional developer and creative-app integrations with their supported cleanup mechanisms.
4. Selected ordinary files moved to Trash; cloud eviction as a clearly separate action; app-native cleanup where appropriate.
5. Before/after reporting, an action log, exclusions, scan cancellation, and visible inaccessible areas.

Every finding should include: owner, location, allocated and apparent size, reason it was flagged, confidence, action, local-versus-synchronized effect, regeneration cost, and reversibility. Distinguish “recoverable without losing content,” “rebuildable,” and “unwanted only if you decide.” These are recommended product semantics.

For scanning, avoid following directory symlinks recursively; deduplicate hard-linked file identities; avoid crossing volumes without an explicit scope; treat library packages as units unless an integration understands them; skip cloud-only file contents; and revalidate file identity and modification state before acting. These are implementation safeguards against counting and deletion errors, not platform guarantees.

## Permissions and feasibility

Apple documents user-selected folder access and security-scoped bookmarks for sandboxed apps. Full Disk Access cannot be granted automatically by code, and other layers—including POSIX permissions, container protections, and System Integrity Protection—can still deny operations. Report incomplete coverage rather than claiming a complete scan. Mac App Store distribution requires App Sandbox; decide distribution and scan scope early. [Apple: filesystem access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) [Apple: sandbox configuration](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)

For a personal prototype, a directly run native utility can simplify experimentation, but it still needs to handle macOS privacy controls. Validate API behavior on the actual target macOS release. Do not require disabling platform protections.

## What remains unknown about this Mac

No evidence yet establishes whether the main issue is cloud copies, Photos originals, device backups, developer artifacts, downloaded media, or app data. The next useful step is a read-only inventory that records volume free/available space and ranks actual local allocations. No universal “typical GB saved” estimate is supported by the reviewed documentation.

# Glossary

The names CacheDrop shows, what they mean, and where they live in code. Copy follows Decision 92 in [docs/RESET.md](docs/RESET.md): use these names, one per thing. Where the code name differs, the Polish milestone renames it; stored keys and accessibility identifiers keep their old names.

## Screens

| Name | What it is | In code |
|---|---|---|
| Design gallery (Debug only) | Synthetic examples of shared components, opened from the Debug menu | `DesignGallery` |
| Overview | Free space, what can be cleaned by category, and the scanned locations | `Destination.overview`, `CacheDropApp.swift` |
| Smart clean | The recommended items, ready to clean in one go | `SmartCleanView`, `RecommendedPlan` |
| Cleanup plan | Every category and item, to tick what to clean | `CleanupPlan`, `CatalogCleanupModel` |
| Applications | Apps, plug-ins and files from deleted apps | `ApplicationsView`, `ApplicationsInventory` |
| Storage trends | What grew or shrank between two scans | `StorageTrends*` (`StorageTrendsHistoryView`, `StorageTrendsHistoryStore`) |
| History | Past cleanups and scans | `CleanupHistoryView`, `ScanActivityHistory` |
| Locations | Scanned locations, Protected items, Saved data | `CacheDropApp.swift`, `RememberedLocations` |
| System access | Optional Full Disk Access status and guidance | `SystemAccessView`, `FullDiskAccessGuide` |
| Explore storage | Browse a scanned folder by size | `StorageExplorer`, `ExploreStorage` |
| Protected items | Paths CacheDrop never offers | `ProtectedItems*` (`ProtectedItemsView`, `ProtectedItemsPolicy`) |
| Saved data | What CacheDrop keeps on this Mac, and Reset | `SavedData*` (`SavedDataView`) |
| App-managed storage | Space only its app can clear; CacheDrop shows where | `AppManagedStorageView`, `CatalogCleanupModel.appManaged` |
| Review sheet | Lists exactly what Clean up will do, grouped by consequence | `CatalogConfirmationSection` |
| Results | What a cleanup did, outcomes first | `CatalogResultsSection` |
| Review interrupted cleanup | Where each item of a cleanup that stopped is now | `CleanupRecoveryView`, `CleanupRecovery` |
| Bottom bar | The same bar on every screen: actions, background work | `ActionStrip` |

## Things

| Name | What it is | In code |
|---|---|---|
| category | A group on Overview and the plan (Developer caches, Downloads, …) | `CatalogCategory` |
| rule | One kind of thing CacheDrop can clean, with its action and consequence | `CleanupRule` |
| item | One thing a rule found on disk | `Candidate` |
| recommended | Items Smart clean ticks by default | `RecommendedPlan` |
| ticked / selection | What will be cleaned; shared by Smart clean, the plan and Applications | `CleanupSelections` |
| scanned location | A folder CacheDrop scans; Downloads is **Built in** | `ScannedLocation`, `RememberedLocations` |
| deletion remnant | A file or folder renamed aside for deletion that remains after cleanup stops | `Candidate.isDeletionRemnant`, `Catalog.deletionRemnants` |
| Files from deleted apps | Settings and data apps left behind (never "leftovers" on screen) | `RemovedAppLeftovers`, category `leftovers` |
| Possibly related | Named like an app but not tied to it; ticked one by one | `AppUninstall.possiblyRelatedRuleID` |
| plug-in product, vendor content | A plug-in and its formats; content shared by a vendor's products | `PlugInInventory`, `PlugInUninstall` |
| local copies | iCloud files kept on this Mac; removing them keeps them in iCloud | `ICloudCopies`, action `evict` |
| "X is open" | An app or tool is using an item, so it's skipped; **Quit X** may free it | `CandidateHold` |
| skipped | Left alone at the click, with a reason | `CandidateCheck` |
| license | What a purchase gives: up to 3 Macs, honour-based, checked on the Mac only (Decision 135) | `License`, `LicenseState` |
| license key | The one copy-pasteable string a license comes as, starting `CD1-` | `LicenseKey`, `LicenseVerifier` |
| trial | Clean up and uninstall, free until they have freed 2 GB on this Mac (Decision 135, #595) | — |
| setup progress | The setup events CacheDrop sends only when the user opts in (Decision 127) | — |

## Actions and outcomes

| Name | Means | In code |
|---|---|---|
| Clean up (verb), cleanup (noun) | Run what's ticked; one cleanup is one run | `CatalogApproval`, `CleanupExecutor`, `CleanupRecord` |
| Delete permanently → Deleted | Removed for good (deletes and cleanup commands) | actions `delete`, `tool` |
| Move to Trash → Put back | Goes to the Trash and can come back | action `trash`, `TrashPutBack` |
| Empty from Trash → Deleted from the Trash | Deletes only what CacheDrop moved to the Trash | `TrashEmptying` |
| Remove local copies | Frees iCloud files' space on this Mac | action `evict` |
| Check for Updates… | A requested update check through standard Sparkle dialogs | `ManualUpdater` |
| Cancel update | Stop waiting for installation while current cleanup and maintenance keep running | `UpdateInstallation.cancel` |
| Move to Applications | Copy CacheDrop opened from a disk image into Applications, open that copy and quit; **Not now** keeps it where it is for this launch | `MoveToApplicationsModel`, `ApplicationsMove`, `AppBundleLocation` |
| Request access… | Request the existing basic access before initial preparation | `WelcomeModel.requestAccess` |
| Scan with current access | Begin preparation without the explicit basic-access setup request | `WelcomeModel.begin` |
| View results | Open Overview after initial preparation is ready | `WelcomeModel` |
| Close (onboarding) | Dismiss the guide while preparation continues | `WelcomeModel.finish` |
| Scan again | Any action that scans | `CatalogCleanupModel`, `ExploreStorage` |
| Dry run | Runs the whole flow; nothing changes | `dryRun` |
| Measured freed space, Freed | Free space measured around each item, not the estimate; History rows note it **Freed** | `MeasuredFreedSpace`, `CleanupHistoryRun.headline` |
| Up to, About | A size that's an upper bound or an estimate | `SizeEstimate` |
| Unknown | A size CacheDrop couldn't read, never shown as zero or empty | `SizeEstimate.unknown`, `SizeFormatter` |
| Needs Full Disk Access | Something macOS keeps from CacheDrop without Full Disk Access | `GuidanceSize.notAccessible`, `CatalogOverview.Row.needsAccess` |
| Rebuildable | Deleted, and its app or tool makes it again (an Overview row's note) | `CleanupAction.delete` |
| Can be cleaned, Other you can clean | The storage bar's found space, and its fold of smaller categories | `StorageMeter`, `StorageBreakdown` |
| Guidance only | Shown with its size and where to manage it; CacheDrop never changes it | action `guidance` |
| free | Disk space you can use | `CapacitySample`, `SidebarCapacityText` |
| Reveal in Finder, Reveal in Trash | Shows the item where it is | — |
| Activate → Licensed | Checks a pasted license key on this Mac and keeps it in the Keychain; Settings then reads **Licensed, up to 3 Macs** | `LicenseController.activate` |
| Remove from this Mac | Forgets the license key on this Mac; the license itself is unchanged | `LicenseController.remove` |
| Share setup progress | The opt-in toggle on Welcome and in Settings that sends setup progress | — |

## Not shown to users

deletion remnant, observed, coverage, baseline, known locations, journal, approval, records, resource identity, metadata, directory, leftovers, available (for free space), Potential space released, Show in Finder, Rescan, Recheck, telemetry, install ID, Storage overview, Cleanup results, Permanently removed, Scan now, Couldn’t be measured, Not accessible, reclaimable, bundle ID, Rules version, File ID.

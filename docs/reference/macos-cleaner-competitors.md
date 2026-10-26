> Historical revision 0.8 reference: keep for feature detail. Scope and decisions now live in [RESET.md](../RESET.md). Codex-era docs are at tag [`archive/codex-era`](https://github.com/Patrick-M-Bourget/mac-cleaner/tree/archive/codex-era/docs).

# macOS cleaner competitors and a practical product strategy

Researched October 22, 2026. Official product pages, documentation, repositories and release notes were reviewed. This is desk research, not a hands-on comparative benchmark. Features below are documented capabilities, not independently verified safety/performance claims. Prices are displayed US-facing prices unless stated otherwise; taxes, promotions, plan entitlements, renewal terms, geography and purchase channel can change them.

## Recommendation

Build around this job: **“Explain why my Mac keeps filling up, then help me recover enough local space with consequences I understand.”**

A generic cache cleaner, disk map or uninstaller would enter a crowded market with strong free and inexpensive options. iCloud support, developer cleanup, AI model cleanup, privacy, dry runs and APFS-aware sizing are already present in competing products. Our opportunity is a better integrated decision workflow and sustained results. This is a product hypothesis to validate, not a claim of unique capability.

## Competitive landscape

| Product | Documented strengths | Displayed pricing / model | Implication for us |
|---|---|---|---|
| CleanMyMac | Broad suite: cleanup, application management, large/old files, duplicates/similar images, Space Lens map, protection/performance tools; Cloud Cleanup separates cloud deletion from local unsync. | Store renders $39.95/year, $9.95/month or $119.95 one-time for one Mac. Check entitlements at checkout. | Closest broad competitor. Cloud offloading alone is parity, not differentiation. |
| DaisyDisk | Sunburst map, preview, admin scanning, physically used storage accounting, clone/hard-link handling, purgeable/snapshot management, selected remote cloud services. | $9.99 one-time; minor updates included. | A polished map has a low price ceiling. Compete on guidance and context. |
| MacCleaner Pro | Bundle containing cleanup, App Cleaner & Uninstaller, Duplicate File Finder, Disk Space Analyzer, Memory Cleaner and Funter. | Store lists $39.95/year for one Mac; one-time options also offered. | Broad feature count is already well served. |
| GrandPerspective | Treemap, extensive filters, Quick Look, saved/exported scans, multiple views and before/after comparison. | Free download; $2.99 App Store listing for the same app. | Saved scans and comparison are not unexplored ideas. |
| OmniDiskSweeper | Largest-first file/folder browser with opening and Trash actions. | Free. | Basic size inspection needs to be excellent and accessible. |
| AppCleaner | Focused drag-and-drop app removal with related-file discovery. | Free download/donation. | Uninstalling alone is a weak paid proposition. |
| Pearcleaner | App removal, orphan search, developer environments, Homebrew and other managers, CLI/automation, configurable searches. | Free, source-available/fair-code. Maintainer currently says development is on hold. | Developer cleanup and automation are established; maintenance quality matters. |
| Mole | Free CLI plus separate paid native app; cleanup, uninstall, disk analysis, maintenance and monitoring. Native app also documents AI-tool/session/model cleanup. | CLI free; native Mac app $19 one-time. | Important low-cost competitor, especially for technical users. |
| Hyperspace | Finds identical contents and consolidates storage using independent APFS clones while retaining the files. | Paid App Store product; exact current price not verified here. | Duplicate deletion is not the only storage-saving approach; cloning deserves separate research. |
| Sensei | Cleanup/uninstall plus monitoring, drive health, thermals and hardware tools. | Paid; exact current price not verified here. | Adjacent suite; hardware dashboards would dilute our storage-first scope. |

Sources: [CleanMyMac features](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/missing-features), [store](https://macpaw.com/store/cleanmymac), [DaisyDisk](https://daisydiskapp.com/), [MacCleaner Pro](https://nektony.com/mac-cleaner-pro), [Nektony store](https://nektony.com/store), [GrandPerspective](https://grandperspectiv.sourceforge.net/), [OmniDiskSweeper](https://www.omnigroup.com/more), [Omni free utilities](https://legacy.store.omnigroup.com/), [AppCleaner](https://freemacsoft.net/appcleaner/), [Pearcleaner](https://github.com/alienator88/Pearcleaner), [Mole CLI](https://github.com/tw93/Mole), [Mole app](https://mole.fit/), [Hyperspace](https://hypercritical.co/hyperspace/), [Sensei](https://cindori.com/sensei).

## Findings that change the proposed strategy

### Cloud cleanup already exists

CleanMyMac supports iCloud Drive, Google Drive, OneDrive and Dropbox, including removing local copies while retaining online originals. Its results distinguish local copies and large local copies, and provide separate remove/unsync review actions. Its iCloud connection relies on Drive already configured on the Mac. [Cloud Cleanup](https://macpaw.com/support/cleanmymac/knowledgebase/cloud-cleanup), [results](https://macpaw.com/support/cleanmymac/knowledgebase/cloud-cleanup-scan-summary), [iCloud connection](https://macpaw.com/support/cleanmymac/knowledgebase/cloud-cleanup-icloud)

DaisyDisk explicitly lists Dropbox, Google Drive, OneDrive and Box for remote scans. Its FAQ says iCloud Drive can instead be selected as a local scan source, covering its local cache rather than all iCloud services. It also explicitly says it does not detect duplicates. These are documented scope boundaries, not inferred omissions. [DaisyDisk specifications](https://web.daisydiskapp.com/specs/), [FAQ](https://web.daisydiskapp.com/support/faq)

**Opportunity:** make the entire local-space explanation coherent: downloaded Drive content, pinned items, Photos optimization, local device backups, app data and system-managed space. Distinguish what can be measured from what can only be guided through Settings. Do not promise an API that inventories every service inside an Apple account.

### Developer and AI cleanup are crowded too

Mole documents developer artifact cleanup, dry runs, exclusions and history. Its native app documents AI-tool caches, old sessions/worktrees and selected Ollama model removal, with personal memories/plans/skills excluded. CleanMyMac's current AI Clutter documentation also lists AI-tool caches and Ollama/LM Studio models. Pearcleaner lists developer-environment management and automation. [Mole CLI](https://github.com/tw93/Mole), [Mole native app documentation](https://github.com/tw93/Mole-App), [CleanMyMac AI Clutter](https://cms-static.macpaw.com/support/cleanmymac/knowledgebase/ai-clutter), [Pearcleaner](https://github.com/alienator88/Pearcleaner)

**Opportunity:** understand project state and consequences more deeply: release archives versus build caches, Docker build cache versus databases, active versus dormant projects, redownload size and rebuild cost. Correctness and tested adapters are the work; identifying popular cache paths is easy to imitate.

### Safety, privacy and accurate sizing are baseline expectations

DaisyDisk markets local processing, user-selected deletion, protected system files and physically used sizing that excludes redundant clones/hard links. Mole documents review, skip reasons, Trash versus permanent cleanup and local processing. Hyperspace documents metadata preservation, just-in-time validation and optional Trash preservation. [DaisyDisk](https://daisydiskapp.com/), [Mole app documentation](https://github.com/tw93/Mole-App), [Hyperspace FAQ](https://hypercritical.co/hyperspace/)

**Opportunity:** make safety inspectable: show the matched rule, ownership evidence, deletion scope, reversibility and uncertainty. Do not advertise simply “safe,” “private” or “APFS-aware” as unique.

### History and explanation are already partially served

GrandPerspective saves scans and supports before/after views. CleanMyMac's release notes document My Activity cleanup progress and Smart Insights explanations, and its monitor reports low space. Mole CLI provides action history. Therefore generic history, explanations and low-space notifications are also parity features. [GrandPerspective](https://grandperspectiv.sourceforge.net/), [CleanMyMac release notes](https://macpaw.com/cleanmymac/whats-new), [storage monitor](https://macpaw.com/support/cleanmymac/knowledgebase/available-disk-space), [Mole CLI](https://github.com/tw93/Mole)

**Opportunity to validate:** attribute growth to categories/apps across time and show whether a cleanup's benefits persisted. Public documentation reviewed here does not establish an integrated recurrence-diagnosis workflow; that does not prove competitors lack one.

## What we should match

| Capability | Minimum implementation | Priority |
|---|---|---|
| Fast inspection | Progressive largest-first list, folder drill-down, search and cancellation; add a map after core scanning works. | P0 |
| Review context | Quick Look, Reveal in Finder, paths, owner, size, exclusions, permission gaps. | P0 |
| Honest sizing | Apparent versus allocated size; shared/purgeable caveats; observed availability after actions. | P0 |
| Cleanup plan | Explicit selections; no automatic assumption that old means unwanted; revalidate before acting. | P0 |
| Useful actions | Trash ordinary files; evict cloud copies; route app-managed cleanup through supported tools. | P0 |
| Targeted rules | A small, documented set of app/developer cache integrations selected from actual local findings. | P0/P1 |
| History | Record action, rule, affected item, result and reversibility; opt-in scan snapshots. | P1 |
| App uninstall | Vendor uninstaller first; careful ownership matching and shared-data exclusions. | P1 |
| Duplicate review | Content validation and clone-aware savings estimates; exclude managed libraries by default. | P2 |
| Broad suite tools | Antivirus, RAM cleanup, fans, network tuning, inbox management. | Outside initial scope |

These priorities are recommendations, not competitor facts. Match the storage job well without copying every unrelated feature of a suite.

## The best gaps to pursue

### 1. “What changed since last week?”

Show observed growth by app, project and storage class, with examples such as “Docker data grew 18 GB” or “Drive downloaded another 24 GB.” These numbers are illustrative, not measured. A scan difference establishes growth under a location; exact attribution to a process or cause needs stronger evidence. Use wording such as “growth observed here” when causality is unknown.

Track whether cleaned caches refill and show durable benefit after a week. Avoid treating cumulative deleted bytes as lasting capacity gained.

**Validation:** use competitor trials on the same synthetic growth workload; check whether they identify the growing owner and recurrence, rather than just a low-space alert or cleanup total.

### 2. A goal-based cleanup plan

Let the user request “recover 30 GB while keeping original documents and photos.” Rank available actions by confidence, content-loss risk, offline requirements, regeneration cost and likely durability. Offer alternatives: evict downloaded media, remove rebuildable artifacts, relocate a library, or review old backups.

Show confidence ranges where savings depend on shared blocks or asynchronous system work. If the goal cannot be achieved under the user's constraints, explain that directly.

**Validation:** ask users to achieve a fixed storage target using competing tools and our prototype; compare time, comprehension and unwanted consequences. This is a hypothesized workflow advantage, not an established exclusive feature.

### 3. Evidence for every recommendation

An item should explain: “Owned by Xcode; generated build products; recreatable from source; next build takes longer; this rule excludes release archives.” Uncertain orphan matches should remain uncertain. Deterministic rules should authorize the operation; optional AI explanation should never convert an uncertain file into an automatically safe target.

**Validation:** test whether users can correctly predict what will disappear, what will return and whether other devices are affected. CleanMyMac already offers explanations, so our advantage must be measured in clarity and correctness.

### 4. A single local/cloud storage account

For someone with a 512 GB Mac and iCloud, explain what is local-only, downloaded from cloud, pinned, optimized, backed up locally, or managed by macOS. Keep “free local space” and “reduce cloud storage” as distinct goals. Offer direct actions only where supported; use guided app/settings workflows for the rest.

**Validation:** reproduce pinned downloads, cloud-only placeholders, pending uploads and optimized Photos. Verify no scan hydrates an entire cloud library and no local eviction becomes synchronized deletion.

## Hyperspace: an interesting later capability

Hyperspace uses APFS clones to share identical file contents while retaining independent files. Reclamation is limited to the same APFS volume. Cloud providers may undo the storage sharing during synchronization; it is not a universal cloud-space reduction mechanism. [Hyperspace documentation](https://hypercritical.co/hyperspace/)

This is meaningful differentiation from ordinary duplicate deletion, but already has a specialist competitor and a substantial correctness burden. Investigate separately after basic scanning and cleanup are reliable; do not add it as a quick duplicate-finder extension.

## Pricing and positioning

If this remains a personal tool, optimize for solving the actual storage problem on this Mac; commercial parity is unnecessary. If commercialized, a basic paid disk map must justify itself against free tools and DaisyDisk's $9.99 license. A broader technical cleaner meets Mole's $19 one-time app and free CLI. [DaisyDisk pricing](https://daisydiskapp.com/), [Mole pricing](https://mole.fit/)

A reasonable pricing hypothesis is free inspection and a one-time paid cleanup/diagnosis upgrade, with clearly stated update terms. A subscription would need continuing value such as maintained adapters and useful longitudinal diagnosis. No price recommendation here is validated willingness-to-pay research.

Maintenance matters: paths and app formats change. Pearcleaner's maintainer explicitly marks active development on hold. Treat this as evidence of the sustaining effort required, not evidence the released app is unsafe. Before reusing any project's code, inspect its actual license; source visibility is not equivalent to unrestricted commercial reuse. [Pearcleaner status/license](https://github.com/alienator88/Pearcleaner)

## Concrete next step

Build a read-only prototype with four screens: **Overview, What Grew, Cleanup Plan, History**. Use app/category cards and a simple file list first. Include a separate local/cloud explanation. Seed it with synthetic scenarios before scanning real files.

Evaluate against CleanMyMac, DaisyDisk and Mole, using identical disposable test data: cloud placeholders/pins, clones/hard links, active caches, release archives, Docker volumes, protected paths, changing files, symlinks and Trash. Measure scan coverage, time to first useful result, size accuracy, user understanding, actual capacity recovered and recurrence. Do not run competing cleaners destructively on the user's main account to benchmark them.

The product claim worth earning is: **“Know what grew. Understand what you can remove. See how much space stayed free.”**

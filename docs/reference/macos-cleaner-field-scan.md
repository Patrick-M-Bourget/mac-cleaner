> Field notes, not accepted scope. This records one manual cleanup of a real Mac. It is evidence for scan policies and recommendation design. [SPEC](../SPEC.md), [design handoff](../DESIGN-HANDOFF.md) and [milestones](../MILESTONES.md) decide what ships.

# Field scan: how 53 GB was found on a full disk

Date: October 24, 2026. Machine: the maintainer's Mac, 228 GB APFS Data volume, macOS 27. An agent (Claude Code) did the scan from a shell, and the owner approved each deletion. The [research](macos-cleaner-research.md) did its work without inspecting a Mac; this is the local scan it calls for.

## Outcome

| Step | Free space after |
|---|---|
| Start: a build failed with "No space left on device" | 119 MB |
| Agent's own build folders removed | 3.5 GB |
| Stale Chrome code-sign clones removed (macOS also released purgeable space during this step) | 12 GB |
| Updater downloads, npm, uv and Homebrew caches | 17 GB |
| Rack Extensions (audio plug-ins) and a Hugging Face model | 41 GB |
| Claude desktop's VM bundle | 53 GB |

## The method

Work top-down by allocated size, then decide every large item on three questions: **who owns it, can it be regenerated, and is anything using it now**. Size and location only nominate candidates; the three answers make the decision.

### 1. Read the volume, not the folders

```sh
df -h / /System/Volumes/Data
```

On APFS, the Data volume holds the user's usage. The `/` line shows the sealed system volume. Here `df` reported 199 GB used, but home folders summed to about 73 GB, so most of the usage was outside the obvious places.

### 2. Size the top level of each root

```sh
du -sh ~/.[!.]* ~/* | sort -h | tail -25
du -sh ~/Library/* ~/.cache/* | sort -h | tail -20
du -sh /Applications /Library /private/var/folders /private/var/vm /private/tmp /opt/homebrew /Users/* | sort -h
```

Then descend only into the largest entries, one level at a time. `~/Library/Caches/*` and `~/Library/Application Support/*` each needed a second pass.

### 3. Always size `/private/var/folders`

This was the biggest single finding. `/private/var/folders/<xx>/<id>/` holds the per-user `T` (temp, `$TMPDIR`), `C` (cache) and `X` folders. Its `X` folder showed **52 GB**, all in `com.google.Chrome.code_sign_clone`: 25 copies of `Google Chrome.app` that Chrome makes for code-sign checks and never removes. Neither `~/Library` nor the Storage settings categories point at it.

### 4. Treat apparent size as an upper bound

Deleting 23 of those 25 Chrome clones freed about **2 GB, not 50 GB**: they are APFS clones sharing blocks with each other and with the app. This confirms the research's "logical size is not recovered space" with a real measurement. Free space also jumped by several GB between steps as macOS released purgeable space once the disk was no longer full. That jump isn't a result of any deletion, so a before/after `df` overstates what one action freed. Report reclaimed space per action, measured right around it.

### 5. Check what is in use before deleting

- **Running apps:** `pgrep -lf "<App>.app"`. Reason and Claude desktop were confirmed closed before deleting their data.
- **Open files:** `lsof -p <pid> | grep -o '<pattern>'` showed which Chrome clone the running browser had open. That clone and the newest one were kept.
- **Active work in "cache" folders:** `~/Library/Caches/Codex/mac-cleaner-implementation` (3.4 GB) is a coding agent's live checkout of this repository, with a commit minutes old. A path under `Caches` doesn't prove a folder is disposable.
- **Repositories:** before suggesting a repo for removal, check `git status` and `git log --branches --not --remotes` for unpushed work.

### 6. Classify by how the data comes back

| Class | Found here | How it comes back | Decision |
|---|---|---|---|
| Self-rebuilding cache | `~/.npm`, `~/.cache/uv`, Homebrew cache (`brew cleanup -s`, then `rm -rf "$(brew --cache)"`) | The next install downloads again | Deleted |
| Updater downloads | `~/Library/Caches/<app>/org.sparkle-project.Sparkle` (1.8 GB), `~/Library/Caches/nativeaccess2-updater` | Downloaded again by the next update | Deleted |
| Leaked app copies | Chrome `code_sign_clone` folders | Never needed again | Deleted, except the in-use and newest copies |
| Unpacked image beside its compressed source | `~/Library/Application Support/Claude/vm_bundles/claudevm.bundle`: `rootfs.img` 10 GB next to `rootfs.img.zst` 1.1 GB | The app unpacks again, or downloads again | Owner deleted the whole bundle |
| Large downloaded models | `~/.cache/huggingface/hub/models--*` (7.7 GB, for a project already removed from disk) | Downloaded again when used | Deleted once the project that used it was confirmed gone |
| Purchased or installed content | `~/Library/Application Support/Propellerhead Software/RackExtensions` and `Optional REs` (17 GB) | Reinstalled through the vendor's app or account | Owner's call; deleted |
| Agent and build scratch | Our own build folders; dated build folders in `/private/tmp` | Rebuilt; `/private/tmp` clears on reboot | Own folders deleted; another session's recent ones left alone |
| Load-bearing caches | `~/Library/Caches/ccache` (2.8 GB) | Slow rebuilds until refilled | Kept |
| User files and apps | `~/Pictures`, `/Applications` (28 GB), `/Library` (34 GB, mostly audio content) | Not regenerable | Listed for the owner, not touched |

### 7. Present the shortlist with consequences, and let the owner choose

Each item went to the owner with its size, its owner, how it comes back and its cost (re-download, reinstall, slower builds). The owner chose item by item ("kill rack extensions, inspect the vm_bundles"). An item marked "inspect" got a listing of its contents first. That is how the 10 GB unpacked disk image beside its 1.1 GB compressed copy was found.

## Implications for Still

Candidate inputs to scan policies, adapters and recommendations, none of them accepted scope:

- **Scan locations:** include `/private/var/folders/*/*/{T,C,X}` for the current user. A browser's code-sign clone folder is a strong, recognisable rule, with an in-use check against the running browser.
- **Size display:** never present a clone folder's logical size as savings. This scan is a fixture-worthy example: 52 GB apparent, about 2 GB freed.
- **Classification signal:** a `foo.img` next to a `foo.img.zst` (or `.dmg`/`.tar` source) suggests an unpacked copy that can be regenerated. Treat it as a hint, never as proof.
- **Recognised app data:** updater payload folders (Sparkle) and ML model caches (`~/.cache/huggingface`) are clear categories with clear consequences.
- **Owner-managed content:** audio plug-in content and app VMs should say "reinstall through <vendor>", not "safe to delete".
- **Liveness signals:** use running apps, open files and recent git activity, not location. A folder under `Caches` can hold live work.
- **Measurement:** measure free space immediately around each action. Purgeable release on a nearly full disk makes before/after totals misleading.

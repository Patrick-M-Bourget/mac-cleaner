# Chrome owned-profile qualification progress (#18)

The genuine disposable experiment **passed** on macOS 26.6.2 arm64, Node
22.23.3 and Python 3.15.0. [Hosted run 40004053915](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40004053915)
ran source **169a255e8b8c01738335e5b5d29c607cebfe53d8**. This advances #18 beyond
synthetic directory fixtures. It does **not** qualify production cleanup or
complete #18's entire acceptance matrix; #19 remains without mutation authority.
No application screen, executable cleanup capability or version allowlist changed.

## Reproducibility and ownership

[The hosted-only probe](../../Validation/ChromeProbe/README.md) provisions exact
Chrome for Testing **156.0.8078.47** from Google's official HTTPS archive into an
ephemeral runner-owned directory. Its independently observed archive pin is
**194,932,023 bytes**, SHA-256
`ad7f2b49a4dc679af286b1b1b386670d93ca7868079f69012d21ba0ac8293df3`.
This pin is not a Google-published checksum. The received archive must match
before extraction or execution. Entry traversal, escaping links and files beneath
archive links are refused; download, time, extraction and free-space bounds apply.
Both provisioner and runtime reject personal machines and self-hosted runners.

The actual executable hash was
`34fbfdb52aacee492bbada9972bf323eba663f8d8a069f86e2652e5158d6c580`.
The direct browser version and browser-owned CDP product both reported
156.0.8078.47, Chromium revision
`1d17a2e2ee147bb7d6ae2ab6abdb3a2510c17775`.

A newly created canonical UUID root holds a custom configured user-data root,
with native `Default` and `Profile 1` profiles launched sequentially. Each profile
initially has no earlier profile's cookie/local-storage value. Cache ownership
comes from this explicit launch configuration and actual generated groups, not
inference from arbitrary directory basenames. No personal browser is inspected,
launched, imported or stopped. No default-browser, login, updater, permission or
OS-policy changes occur. Shutdown uses Browser.close and, if necessary, only the
fresh process group the experiment launched.

The archive is a development artifact with **no CodeResources**. Strict native
bundle/executable verification reports missing sealed resources, and signature
display reports ad-hoc linker signing with no TeamIdentifier. The first attempt
[40003124836](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40003124836)
stopped before launch on that observation. The successful experiment preserves
and prominently reports it, uses exact untouched official bytes accepted by the
OS, and performs no re-signing, quarantine removal or Gatekeeper bypass. It does
not establish a sealed vendor bundle or production distribution trust. Its initial
framework diagnostic used ordinary Chrome branding and reported a missing path;
that raw error is preserved, and the future diagnostic now uses the actual
`Google Chrome for Testing Framework.framework` path. No framework verification
success is claimed from this run.

## Native observations

| Boundary | Result in each of two genuine profiles |
|---|---|
| Real cache generation | Local HTTP server supplies a 512 KiB asset; actual `Cache/Cache_Data` contains seven generated regular leaves |
| Persistence before cleanup | Warm genuine relaunch fetches the asset without another fixture-server request |
| Active/reopened browser | Experiment refuses its removal operation in both observed active lifetimes; browser-owned CDP exposes browser, renderer, GPU, network and storage process types |
| Exact synthetic cache removal | Once its owned browser group has exited, seven manifest leaves totaling 667,668 logical bytes are removed through directory descriptors without following links; no recursive target-directory removal |
| Protected native files | Cookies, History, Login Data, Web Data and Preferences hashes match immediately before/after closed-cache removal |
| Protected site semantics | Generated persistent cookie, localStorage, IndexedDB key and CacheStorage offline response retain their expected values after actual relaunch |
| Regrowth | The asset is requested from the local fixture server again, and seven native cache leaves regenerate |

Removed logical bytes are not exclusive reclaimed bytes or observed capacity.
Protected file hashes are from owned synthetic browser data and are not a
personal-data collection feature. Empty credential/autofill databases do not
prove authenticated-account or autofill preservation. Browser user-agent text
mentioning Intel does not qualify Intel runtime; the actual host is arm64.

[Raw report](chrome-owned-profiles/report.json),
[provisioning observations](chrome-owned-profiles/provision.json) and
[SHA-256 manifest](chrome-owned-profiles/manifest.json) are unmodified artifacts
from the successful run. They contain synthetic relative profile names, public
browser identity and runner-temporary provisioning paths. No generated profile,
cookie value, website content, browsing history or downloaded browser is in Git.

## Remaining gates

- The activity/refusal check relies on exclusive ownership of freshly launched
  test processes. It is not a native detector for arbitrary installed browser
  helpers or proof against external browser reopen, concurrent writes or final
  leaf substitution. Descriptor-relative access and identity checks reduce scope;
  they do not close the production check/use race.
- Actual access denial, enterprise policy overrides, shared cache ownership,
  installed-channel discovery, unsupported real layouts and additional OS/CPU
  combinations remain unqualified. The existing Swift fixture suite covers
  conservative guidance for injected uncertainty, rather than these native cases.
- Credentials/authenticated sessions, autofill, downloads, history semantics,
  session/tab restoration and complete offline applications need dedicated
  disposable semantic fixtures. A simple CacheStorage response is limited proof.
- Background-network mitigation flags are not a network trace. Only the fixture
  HTTP server is bound to loopback; no absence-of-all-outbound-traffic claim is made.
- The production positive allowlist remains empty. No Chrome version is eligible
  for app cleanup; the application's existing unsupported guidance remains true.

Local, browser-free checks passed: four existing Swift fixture/capability tests,
two public exact-leaf helper tests, Node syntax and Python compilation. The helper
was first red when absent, then green. The two Python tests check a protected
sibling, a symlink, a changed leaf identity and an escaping manifest. Their scope
is disposable helper behavior, not actual Chrome inactivity qualification.

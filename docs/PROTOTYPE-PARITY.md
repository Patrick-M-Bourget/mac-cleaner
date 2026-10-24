# Prototype-to-implementation parity audit

Audited October 23, 2026. Native baseline: `f9e854f57d14bfb40f304ca06024faa75afc25a9`. Tracking: [#45](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/45). **Audit complete; connected Q1–Q30 and b96bb97 designs are approved. See the current acceptance overlay for delivered repairs, unresolved decisions and exact proof limits.**

## Baseline and evidence boundary

The approved reference is [revision 0.9 source](visual/preview-source.html), including its final JavaScript amendments, **M1 Personal build and Future milestones modes**, all secondary panels and the 18 exceptional scenarios. Its SHA-256 is `3990218fb4ebf5e7edad4e8d0ac55e1d7f136159cd98deeecdc1bf019f82d88c`, identical to the user's original `storage-companion-milestones.html`. The [exported preview](visual/preview.html) and [reference captures](visual/README.md) remain unchanged. Earlier prototype iterations are history, not additional requirements.

This is a complete source/contract/evidence audit, not a new native test run or pixel certification of every state. Native source, existing validation reports and source-pinned captures were compared with every reference destination, action family and state. “Covered” means a native implementation and relevant recorded evidence exist, not universal OS qualification. Source-only gaps are identified as such; uncaptured/manual/platform cases remain with #35 and the owning feature ticket. Screenshots comparing unscanned native data with useful sample data do not prove a missing selector by themselves.

Authority remains SPEC + DESIGN-HANDOFF + MILESTONES. The prototype establishes product intent and hierarchy, not fake data, literal web metrics or permission to bypass feasibility gates. Proposed fixes in issues are **not** newly approved product decisions. A contract can preserve an intended feature while acknowledging it is missing in the current app.

## Connected Downloads implementation checkpoint

The original tables below record the audit baseline. The user-approved b96bb97 proposal is integrated at5a9d588 on `integration/still-spec` under #55 → #56 → #57: remembered explicit scope configuration, contextual Downloads prerequisite, macro/inline membership, observed-only folder Explorer, exact confirmation/results and return routes. This advances S01–S05/S09, F01–F05 and the corresponding plan/navigation gaps; it does not certify every original repair criterion. See [source-bound native qualification](validation/connected-downloads.md). Original parent issues #44/#46/#47/#48/#50 and #45 remain open until their complete acceptance is proven. Future capabilities and platform gates below remain unchanged.


## Mixed-location and inspector checkpoint — #58/#59

Qualified application source9264d7a extends the connected journey with mixed current/unscanned/unavailable scopes, explicit overlap, adaptive recovery labels, current access guidance, conditional Forget and independently supported exact hardlink choices. Structured inspector evidence now separates location/scope/time, sizes, why listed, action/consequence and existing protection reasons. [Final native qualification](validation/connected-next.md) advances S01–S05/N08/FL05/FL06/FL09 and F05/F06 without expanding cleanup authority. Initial/minimum mixed jobs pass1+1; inspector2/2 and existing Downloads13/13 pass, with final affected recovery1+1. All24 final mixed Light/Dark originals were reviewed; historical audit tables below remain the baseline, not a claim that these delivered child flows are still absent. #44/#46/#47/#48/#50/#45 stay open for their complete acceptance, and provider/OS/manual accessibility/future milestones retain their gates.

## Current acceptance overlay — October 24

The tables below Classification retain the original audit baseline. This current overlay prevents historical gaps from being mistaken for still-missing implementation. D/M/R are integrated; L is integrated at `03779f5` after native context/diagnostics/History, original-image review, source reviews and affected regressions. Existing decisions and all future gates remain preserved.

### Evidence keys

- **D — Downloads:** [connected-downloads](validation/connected-downloads.md), application 824328f; both real complete journeys, scope/config-only relaunch, Explorer/plan/confirmation/Results/new plan. Strengthened refresh 40052574336; unavailable recovery 40052410048; exact anchors 40050359141. Combined focused runs, not one full-suite green.
- **M — mixed/inspector:** [connected-next](validation/connected-next.md), application 9264d7a; Downloads 13/13 at f233d10 (40056609812), inspector 2/2 (40056586166), final initial/minimum mixed 40059063609/40059065114 at c640bb9; 76 original native captures.
- **R — recovery/Results/access:** [recovery-results](validation/recovery-results.md), final app changes through 664f6ce; recovery initial/minimum 40063307935/40063307903 and 8/8 affected regression 40063307890 at 7c28b7f; terminal 5/5 40063066782 at 9ab8aea; access 40062699173; History 2/2 40063851203; 78 originals. Native unknown/all-failed terminal reproduction is expressly unqualified.
- **L — local records:** [local-records](validation/local-records.md), final app dadc0c1; final context40068265478/40068265529, diagnostics40068265439/40068265594, History3/3 40068265641, regressions7/7 40068265638 atf8a0c86; Gallery2/2 40068435072 at test-onlyf754b83. 67 final originals individually reviewed. Both origins, live choices, retained caller/management/diagnostics viewport, fresh Reset guard and recovery return; direct root diagnostics Back.

### Current bounded acceptance

| IDs | Current status replacing a misleading bare baseline G | Exact acceptance boundary / remaining scope |
|---|---|---|
| P01–P03, P06, P08 | Qualified M1 | D stable category/prerequisite, contextual same-screen scan, initially collapsed refinement, shared exact macro/individual membership, refresh pending blocker and explicit retry exit; M full Downloads regression |
| P05, P07 | Qualified M1 | D real confirmation Cancel/focus, original membership, process lifetime versus Quit/config-only relaunch; bounded exact Trash approval, no consumed authority restoration |
| F01–F03,F07,N04 | Qualified M1 | D observed roots/descent/breadcrumbs/scoped descendant search/no matches/clear, contextual plan return, saved query/inspector/viewport; no filesystem discovery while browsing |
| F05 | Qualified M1; provider limits | M structured location/time, logical/on-disk values, why listed, action/consequence and canonical policy reasons; synthetic unknown/provider presentation is not genuine cloud certification |
| S01–S05,S09 | Qualified bounded M1 | D+M configured scopes, no-locations/manual scan, persistent Stop/origin, independent valid locations, missing/unknown/pending, explicit recovery/omit/reinclude, conditional Forget and overlap. Real OS revocation/disconnected-volume/provider behavior remains separate |
| S06 | Qualified education | R optional FDA disclosure, manual settings instructions, expansion preserved across route return, no prompt/status detector/authority expansion |
| N01,N02,P09 | Qualified specified origins; partial overall | D Explorer/plan; R manual History/Overview recovery, startup Overview, observed viewport/disclosure/process-window context. L adds both Local records origins and gated diagnostics direct-root return with exact viewport/reopen proof |
| N03,L01 | Qualified bounded M1 | L shared History/Locations Local records, existing Clear/Reset policy, actual Clear/Cancel, fresh protected-journal guard, recovery return and final visual/regression/source review |
| L02 | Partial / M6-gated | L qualifies frozen redacted preview, Save Cancel, caller return and process viewport/reopen; existing Save success/failure retains its earlier proof boundary. No ordinary-launch promotion |
| R02,R05 | Qualified bounded presentation/normal terminal routes; partial native exceptional proof | D explicit History/new plan, R actual native partial/retry and all-skipped plus shared eight-branch synthetic Gallery and public Core failure/unknown/replay fixtures. Do not label native unknown/all-failed terminal flow qualified |
| H04 | Partial; decision/future parts retained | R per-run expanded recorded facts; L shared local records. See what grew/History activity relationship remains #51/M4; never restore old approval for latest results |
| O02,O06,X02 | Implemented bounded #49; final visual review accepted | User-locked CAPACITY-REFRESH.md now has process-owned lifecycle/manual/terminal refresh, 30-second foreground rule, coalesced trailing demand, 10-second expiry, stale/unavailable/partial states and shared native controls. Combined six policy tests/Core142, 10 new UI journeys and 17 existing checks pass; final presentation source8869b38, final 71-original capture review accepted. This overlay supersedes the historical once-at-window-creation/absent-retry findings below; no full-suite or universal platform claim |
| H01,H03 | Decision pending #51 | Cleanup-only versus aggregate scan History and retention wording; existing protected history mechanisms retained |
| N05–N07,A04 | Covered within bounded #53 qualification | [SHELL-APPEARANCE](SHELL-APPEARANCE.md) Q1–Q13 is implemented at `c5886e8`; [native/source evidence](validation/shell-appearance.md) records normal-click, theme, size and affected-flow acceptance and limits |
| S07,P10,C01–C02 and other adapters | Future gated | Recognized discovery, cloud/developer/browser actions retain their original M2/M3 tickets; never required to close M1 feature implementation |
| G01–G04 | Future M4 + unresolved #52 | Existing comparison mechanisms do not complete first-use/review-options routing or approved visual hierarchy |
| M01–M02 | Future M6 + unresolved #54 | Existing managed guidance retained; release-archive information architecture still outstanding, no deletion |
| N08–N10 | Bounded qualified + M7 limits | Original native theme/size/fixed footer/keyboard/anchor evidence exists; no comprehensive VoiceOver/localization/OS/CPU certification |

#44/#46/#47/#48 bounded M1 feature repairs are accepted and closed against D/M/R/L evidence. #50 retains exceptional native proof and #45 retains unresolved decisions. Unaffected already-covered/departure/simulation rows retain their status; this overlay is not permission to erase any roadmap row or claim all 79 rows implemented.


## Classification

| Code | Meaning |
|---|---|
| C | Covered in native source with relevant existing evidence; remaining qualification limits still apply |
| G | Current feature/flow gap or incomplete presentation; explicit issue owns repair/design decision |
| F | Preserved future capability or qualification gate; source/probe presence does not mean ordinary-launch availability |
| D | Deliberate native/safety adaptation justified by current accepted contracts |
| T | Prototype-only sample, simulation or review tool; not a production feature |

Mixed rows identify separately implemented mechanisms and missing product flows. An open issue is not proof of missing code: much integration work remains open until draft PR #36 merges. Conversely, a green filesystem test or shared component does not establish end-to-end product parity.

## Navigation, shell and visual contract

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| N01 | One labelled Back, correct caller and sidebar parent | Recovery candidate #60 restores manual History/Overview caller; startup remains Overview. Other secondary origins and Local records remain separate | C/G [#48](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/48) |
| N02 | New destinations top; return restores their scroll | Existing explorer/plan context is extended by #60 retained History/Overview viewports and #63 Locations context; broader qualification pending in validation/recovery-results.md; checkbox anchoring is separate | C/G #48; [anchor evidence](validation/checkbox-content-anchor.md) retained |
| N03 | Local data/exclusions/diagnostics reachable from Locations and History | Clear/Reset work in History; exclusions in future Locations; diagnostics in future Overview. Shared management entry/origin flow missing | G #48; mechanisms #13/#30/#32 preserved |
| N04 | Folder/query/inspector context and selections survive review round trips | Shared selection survives; view-local query/inspector and originating route are not explicitly restored | C/G #7 and #48 |
| N05 | Cleanup plan nav badge reflects live selected categories | No badge; count meaning must be specified before copying prototype | G [#53](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/53) |
| N06 | Footer indicates on-demand versus effective alerts | Sidebar always says On-demand scanning even with future monitoring effective; menu-bar status exists separately | G #53; M5 qualification #27–#29 |
| N07 | Automatic/Light/Dark; explicit preference persistence contract | Theme switch exists; native override is window-local State. Persisting it is a decision, not inferred from web wrapper persistence | C/G #53 |
| N08 | Stable window, fixed actions, bounded sheet, readable paths | Native window contract, sibling footer, disclosure gutter and anchor fixes recorded | C #37/#38; [layout](reference/macos-cleaner-layout-contract.md); platform/localization gates #35 |
| N09 | White Light sidebar, white/near-black content, subtle glass and category accents | Shared semantic components/gallery and native captures exist; web pixel metrics not required | C/D #37; [design system](DESIGN-SYSTEM.md) |
| N10 | Keyboard, focus, VoiceOver, contrast, reduced motion/transparency | Native controls/focus bridge and partial keyboard evidence; comprehensive manual/platform coverage is not complete | C/F [#35](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/35), #34 |
| N11 | State/milestone selectors, simulated OS controls, sample disk values | Excluded from ordinary product; Debug fixture/gallery flags only | T/D #2/#37 |

## Overview and measurement

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| O01 | Capacity → scanned locations → four recommendations | Restored with shared grouped rows, active-only chevrons, plain consequences and real/Unknown/Not inspected states | C #41–#43; [36-capture evidence](validation/overview-restoration.md) |
| O02 | Capacity reflects a fresh observed volume reading | Workspace snapshot reads once at creation; result model samples independently. Scan/activation/cleanup can leave sidebar/Overview stale | G [#49](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/49) |
| O03 | Four category opportunities with real sizes | Downloads real; focused cloud inventory real/unknown; Xcode/browser unavailable. Future actionable findings not built | C/F #5/#15/#17/#19/#21; no invented GB totals |
| O04 | Recommendation opens relevant review, never selects or executes | Downloads opens exact backing scan; cloud expands read-only evidence; unavailable developer/browser have no dead action | C/D #42; richer explorer #47 and future adapters remain open |
| O05 | Scope bytes separate from disk and release estimates | Native current-scope logical/allocated evidence; Downloads resource dedup; Trash not immediate release; no naïve overlap sum | C/D #3/#41/#42; future mixed-action summary #15/#17/#19/#21 |
| O06 | Capacity unknown, historical last reading and retry | Unknown meter supported; dedicated refresh/last-known recovery action absent | C/G #49 |
| O07 | Explore selected storage without claiming whole disk | Current focus only for cloud/scope amounts, known-location count and exact Downloads findings; narrower aggregation is explicitly labelled | D SPEC Overview contract; navigation depth G #47 |
| O08 | App-managed guidance remains reachable below findings | Future More tools route exists; intentionally secondary; release-archive row missing | C/F #31; G #54 |
| O09 | First launch/no eligible findings are useful and honest | Choose folder/Downloads and scoped empty/partial findings exist; no global “Mac is clean” claim | C/D #42/#43; fuller scope setup G #46 |
| O10 | Scan again known scopes; progress/Stop; incomplete results not executable | Sequential known roots, cancellation/generation protection and selection preservation implemented | C #41/#43; scope configuration G #46 |
| O11 | Disk total/category chart conveys observed capacity | Neutral volume meter replaces unmeasured synthetic category segments; no whole-disk category taxonomy fabricated | D #37/#42, measurement rules in SPEC |

## Locations, access and scan setup

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| S01 | Manage all selected locations in Settings | Only focused path shown; known scope reports live in inspection | G [#46](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/46) |
| S02 | Add folder, include/omit/remove before manual scan | Single native chooser and retained roots exist; editable batch inclusion set absent | C/G #46 |
| S03 | No-locations state and explicit Scan selected locations | Overview chooser works; Settings selection/scan workflow absent | G #46 |
| S04 | Named revoked/denied scope and choose-again recovery | Scanner partial/unknown and native rechoose work; per-location status/recovery management missing | C/G #4/#46; real OS qualification #35 |
| S05 | Disconnected location can reconnect/recheck or omit | Scanner missing-volume evidence exists; Settings reconnect/remove/omit workflow absent | C/G #4/#46; mounted fixture evidence #34 |
| S06 | Full Disk Access optional, limited operation useful | No broad admission permission; #63 candidate adds optional contextual education without inferred status or automatic settings launch; native qualification pending | C/G #46; do not claim a reliable global FDA status detector |
| S07 | Optional recognized developer/browser discovery scopes | Arbitrary explicit folder scanning exists; no validated recognized cache/build discovery integrated | F #16–#21, #46 scope design; adding scope never grants access |
| S08 | Exclusions separate from plan deselection | Explicit preview/save/remove, path/volume semantics, invalidation and reset implemented, future gated | C/F #30; [exclusions](EXCLUSIONS.md); no inspector exclusion |
| S09 | Progress describes current scan, not setup invitation | Fixed Stop exists; during queued new root, temporary Choose a folder guidance appears beside rechecking progress | G #46 (copy/state refinement, not new scanner) |

## Explore storage and inspector

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| F01 | Selected-folders root and folder descent/return | Flat recursive list, report switch buttons; directory click inspects rather than navigates | G [#47](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/47) |
| F02 | Folder sizes and file on-disk evidence with scope | File logical/allocated details exist; folder row gives kind, not an honest computed subtree subtotal | C/G #47; no invented folder allocations |
| F03 | Scoped search, no matches, clear query, no stale inspector | Filtering exists; no explicit no-matches state/clear action and previous inspector can remain | G #47; FILES-01 |
| F04 | Names inspect, checkboxes select same live plan | Native independent actions/shared exact membership, hidden-search selection and browse-only protections | C #7/#8/#10; resource identity, not basename |
| F05 | Inspector: location, apparent/allocated size, why listed, action and reason blocked | Paths/sizes/kind and explicit preview present; specific ordinary-file eligibility/protection/action explanations incomplete | C/G #47 |
| F06 | Explicit Quick Look/Reveal; cloud-only never hydrated for preview | Locality gate and explicit native requests implemented; no automatic previews | C #3/#5; genuine provider qualification #6/#35 |
| F07 | View cleanup plan and Back preserve context | CTA selects nothing; origin/viewport/filter context incomplete | C/G #7/#48 |

## Cleanup plan, confirmation and recovery

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| P01 | Plan is a category selection workspace, including useful scan with zero selections | Populated native category exists; separate no-scan fallback plus global chooser changes task/hierarchy | G [#44](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/44); no sample categories/bytes to fake evidence |
| P02 | Scan/access prerequisites unambiguous and return predictably | Choose Downloads means folder choice, starts inspection and routes away; repeated banner above useful plan | G #44; scope workflow #46 and routing #48 |
| P03 | Macro checkbox all/mixed/none; inline item refinement | Downloads exact eligible IDs, nested files and mixed selection implemented; inline list initially expanded vs prototype collapsed | C/G #8 and #44 (choose default disclosure/compact hierarchy in grilling) |
| P04 | Summary count/size and consequence before approval | Selected for Trash exists; no fake released estimate. Roadmap needs separate per-action accounting | C/F #8; #15/#17/#19/#21 own multi-action integration |
| P05 | No automatic selection; Back/Cancel preserve; Quit ends unexecuted plan | Process-owned session selection and window-close retention implemented | C #7; deliberate replacement of obsolete staged drafts |
| P06 | Refresh suspends execution, pending visible, survivors retained, new files unchecked | Native refresh/recheck, Stop, pending notices and validation implemented | C #10/#41; Settings editing absent #46 |
| P07 | Bounded exact confirmation, explicit consequence, Cancel/focus return | Native Downloads sheet and Move to Trash; exact paths/scope, no permanent fallback | C #8/#9; mixed permanent/cloud actions F #15/#17/#19/#21 |
| P08 | Retry rechecks unfinished only; broad scan is explicit new boundary | Native restricted retry, per-target exclusions and explicit Overview broad scan implemented | C #11/#42; plan prerequisite redesign must retain this (#44) |
| P09 | Crash recovery shows durable facts and unknowns; never auto-repeats | Native read-only recovery/journal; no saved draft authority | C #12; caller routing G #48; real platform limits remain recorded |
| P10 | Cloud/developer/browser plan categories and profile refinement | Absent in M1 by approved milestone split; mutation probes do not implement product categories | F #15/#17/#19/#21 (must deliver category, refinement, confirmation, result and states) |

## Running and completed results

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| R01 | Running progress, cancel remaining without rollback | Exact-target progress, stop-after-current and durable outcomes implemented | C #9/#11 |
| R02 | Success/partial/all-skipped/all-failed/unknown clearly distinguished | Per-file counts/states exist; outcome-level hierarchy/next action incomplete | C/G [#50](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/50) |
| R03 | Planned, Trash-held and independently observed capacity separate | Native result measurements/time/volume checks; never claims exact released allocation | C #9; displayed Overview freshness G #49 |
| R04 | Reveal actual Trash successes, explain recovery limitations | Actual returned locations and native Reveal; no automatic restore or universal Undo | C #9/#13 |
| R05 | View history and deliberate new-plan/scan path after consumption | No direct View history/primary next step on all-success/nonretryable terminal results; revisit plan can reopen results | G #50; no silent reset/reexecution |

## History, growth and local management

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| H01 | Empty History explains completed scans and cleanup activity | Native History is completed cleanup-only; aggregate observations in future What grew | G decision [#51](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/51) |
| H02 | Activity dates, actual per-action outcomes, observed capacity | Native completed runs, per-file disclosure, estimates vs capacity and recorded Reveal exist | C #13; roadmap action types F #15/#17/#19/#21 |
| H03 | History after clear/reset/retention remains honest | Native protected journal, guarded reset, growth clear and retention implemented; clarify domain retention wording with scan-history decision | C/G #13/#26/#51; unresolved recovery exempt |
| H04 | History → what grew / local records / latest results | Per-file results inline, but no See what grew or common local-record route; exact latest-result replay may be replaced by recorded inline detail | C/G #48/#51; no old approval restored |
| G01 | What grew net change, scope, interval and groups | Folder/category compatible comparisons implemented, future gated; compact reference comparison/relative-magnitude hierarchy not reproduced by native text rows | C/G/F #26/#52; real values only, no writer attribution/exclusive-space claim |
| G02 | First/cleared/missing/incompatible/partial baseline next actions | State messages exist once comparison set; completely empty nil state lacks explicit first-use explanation | C/G [#52](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/52) |
| G03 | Review options from useful comparison | No comparison-to-findings/plan CTA | G #52; never auto-select findings |
| G04 | Scan for baseline returns meaningfully to What grew | Generic Inspect a folder footer sends to inspection; no review-oriented return flow | G #52/#48; no continuous background monitoring |
| L01 | Local-record management reachable from Locations/History | Mechanisms exist in History; Settings route/origin missing | G #48; preserve #13 mechanisms |
| L02 | Diagnostics review then explicit local Save, return to caller | Exact redacted frozen preview/Save/Cancel/failure implemented; only future Overview entry and Back there | C/F #32; route G #48 |
| L03 | Exclusion rules, fixed protections, remove and recheck | Explicit native volume/path rules and preview/save/remove work; no exclusion from unchecked item | C/F #30; [native evidence](validation/exclusions.md) |
| M01 | App-managed categories include release archives | Backups/Photos/Mail/Messages/system present; release archives absent | C/G/F [#54](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/54), #31 (M6) |
| M02 | Native owner guidance, optional selected metadata, no library surgery | Existing guidance/launch fallback/read-only metadata; add safe Xcode Organizer guidance for missing category | C/F #31; G #54; no archive deletion |

## Alerts and future action capabilities

| ID | Reference intent | Native baseline / difference | Status / owner |
|---|---|---|---|
| A01 | Off by default, threshold, Apply/validation, permission and capacity-only checks | Controller/UI implemented behind future flag; genuine OS authorization/delivery not qualified | C/F #27; timestamped alert-open native evidence retained |
| A02 | Window close/menu-bar, Quit safe boundary, independent login status/approval | Lifecycle/controller and native settings implemented; effective OS/login behavior qualification incomplete | C/F #28; no root daemon |
| A03 | Quiet episode, recovery margin, persistent 24h snooze | Policies/control tests implemented; real OS delivery/lifecycle remains gated | C/F #29 |
| A04 | Visible effective monitoring context and separate login explanation | Login settings clear; global footer remains on-demand; repair navigation currently generic System Settings | C/G #53 and #27/#28 (contextual instructions) |
| A05 | Show current capacity and explain one alert/recovery margin/snooze | Settings lacks reference's current-reading display and full quiet-reminder explanation | G/F #27/#29 (UI integration, not just policy tests) |
| C01 | iCloud local-only eviction with pin/upload/conflict/offline evidence | Read-only cloud inventory works; pinning unknown, eviction unsupported and no cloud action category | F #6/#15; no ordinary deletion substitute |
| C02 | Xcode generated-data inventory, selection, rebuild/protection and permanent results | Genuine owned probe is not app integration or supported concurrent-owner contract | F #16/#17; release archives/dSYMs protected |
| B01 | Chrome/Safari discovered groups, profile/shared mapping, sizes/support | No production browser review UI or validated discovery; genuine Chrome probe only partial feasibility | F #18/#19/#20/#21 |
| B02 | Running/helpers, reopen, denied/unsupported/unknown/empty guidance | No integrated browser states/recovery routes; all required within owning adapter tickets | F #18–#21; never force-quit or erase website data |
| B03 | Shared browser selection, inline profiles, permanent consequence and per-group result | Not integrated; no cookies/history/credentials/offline/session scope expansion | F #19/#21; must update plan/confirmation/results together |
| E01 | Homebrew/pip optional validated tool inventory/cleanup | Narrow read-only future routes exist beyond prototype core; vendor mutation still conditional | C/F #22–#25; narrower supported versions are documented, not parity completion |
| E02 | Docker inventory, protected volumes, actual vs virtual space | Future read-only route exists; no prototype/core cleanup promise and no Docker mutation | C/F #33; no prune/delete |
| E03 | Platform/performance/accessibility/privacy qualification | Native/cross-toolchain/disposable evidence incomplete for minimum OS/Intel/provider/VoiceOver/full display coverage | F #34/#35; commercialization #40 separately deferred |

## Every exceptional prototype scenario

This lists the full 18-case review selector separately so a covered mechanism cannot conceal a missing recovery action. Prototype “normal” is the baseline; it is not a nineteenth exceptional feature. A state can exist in code without having all native branches freshly captured.

| Prototype state / reference ID | Native state and remaining gap | Owner |
|---|---|---|
| first / SCAN-01 | Unscanned Overview supported; complete scope onboarding/plan prerequisite decisions pending | #42/#43, #44/#46 |
| noLocations / SCAN-02 | Overview chooser exists; Settings included-location editor/scan absent | #46 |
| partial / SCAN-03 | Partial/unknown scope evidence and suspended selections exist; scope-specific settings recovery incomplete | #4/#41/#43, #46 |
| revoked / ACCESS-01 | Rechoose and scanner error available; named location access management missing, real grant qualification separate | #4/#46/#35 |
| interrupted / SCAN-04 | Stop and pending Refresh required work; no complete baseline from interrupted scan | #10/#41/#39; full multi-location recovery #46 |
| offlineVolume / SCAN-05 | Missing/disconnected totals unknown; reconnect/omit management missing | #4/#34/#46 |
| capacityUnknown / CAP-01 | Unknown display exists; retry/current vs last reading not complete | #49, alert branch #27 |
| stale / PLAN-02 | Refresh suspends review with retained identities; prerequisite route redesign unresolved | #10/#41, #44 |
| noFindings / SCAN-06 | Honest empty Downloads available; no-findings setup/plan contract unresolved | #42/#43, #44/#46 |
| emptyPlan / PLAN-01 | Useful-scan native category remains selectable; no-scan fallback/chooser/hierarchy drift pending | #8, #44 |
| emptyHistory / HIST-01 | Cleanup-only empty state implemented; completed-scan activity decision pending | #13/#51 |
| noMatches / FILES-01 | Filtering only; no clear-search empty state and stale inspector hiding | #47 |
| browserDenied / CACHE-01 | No production group review/recovery yet | #19/#21, qualification #18/#20 |
| browserUnsupported / CACHE-02 | No production support matrix UI yet | #19/#21, #18/#20 |
| browserUnknown / CACHE-03 | No production uncertain-mapping UI yet | #19/#21, #18/#20 |
| browserEmpty / CACHE-04 | No production empty/group/native-browser guidance flow yet | #19/#21 |
| cloudBlocked / CLOUD-01 | All eviction unavailable; future per-item pin/upload/conflict reasons/actions gated | #6/#15, inspector #47 |
| allSkipped / RESULT-01 | Per-target skipped/no-op behavior exists; explicit outcome heading and recovery next steps incomplete | #11/#50 |

Additional branches not in that selector remain required: running browser/reopen; scanner recheck/budget; pending refresh; exact confirmation Cancel; execution stop/partial/failed/unknown; durable startup recovery; failed journal; clear/reset guarded/partial failure; first/missing/cleared/incompatible growth; threshold/authorization/snooze/login approval; diagnostics Save cancel/failure. Each is owned above and in the linked validation reports or #35. A prototype simulator button is not the production test for any branch.

## Native evidence index

These source pointers make the classification reproducible at the pinned baseline. Reports preserve their own source/run and limits; this audit does not upgrade them.

| Area | Native source / recorded evidence |
|---|---|
| Shell, locations, empty plan, secondary origins, initial capacity | [StillApp.swift](../Still/App/StillApp.swift): WorkspaceView, navigation, locations, plan, chooseDownloads, startupCapacity task and fixed action composition; [fidelity evidence](validation/visual-fidelity.md) |
| Scope refresh and inspected observations | [FolderInspection.swift](../Still/App/FolderInspection.swift): scanAgain, showObserved, FolderInspectionView; [FolderScanner](../Packages/StillCore/Sources/StillCore/FolderScanner.swift); [Overview verification](validation/overview-restoration.md) |
| Shared plan/category/confirmation | [SessionPlan.swift](../Still/App/SessionPlan.swift): eligibleRows, overviewDownloadsCoverage, LiveCleanupPlanView, CleanupConfirmationView; [refresh](validation/refresh.md), [cancel/retry](validation/cancel-retry.md) |
| Capacity and terminal results | [VolumeCapacity.swift](../Still/App/VolumeCapacity.swift), [CleanupExecutionView.swift](../Still/App/CleanupExecutionView.swift): separate before/after samples and per-target outcomes; [executor evidence](validation/downloads-executor.md) |
| History/recovery/local records | [CleanupHistoryView.swift](../Still/App/CleanupHistoryView.swift), [CleanupRecoveryView.swift](../Still/App/CleanupRecoveryView.swift); [history/reset](validation/history-reset.md), [startup recovery](validation/startup-recovery.md) |
| Growth | [GrowthHistoryView.swift](../Still/App/GrowthHistoryView.swift): future flag, nil-comparison path and comparison rendering; [comparison evidence](validation/growth-comparisons.md) |
| Cloud metadata | [CloudInventoryView.swift](../Still/App/CloudInventoryView.swift), Overview cloud row; #5/#6 and [Overview uncertainty evidence](validation/overview-restoration.md) |
| Alerts/login | [StorageAlerts.swift](../Still/App/StorageAlerts.swift), [AppLifecycle.swift](../Still/App/AppLifecycle.swift), [StorageAlerts package](../Still/Packages/StorageAlerts); [controlled orchestration](validation/alert-monitoring-orchestration.md), [alert-open context](validation/alert-open-context.md) |
| Exclusions/diagnostics | [ExclusionsView.swift](../Still/App/ExclusionsView.swift), [DiagnosticsView.swift](../Still/App/DiagnosticsView.swift); [rule evidence](validation/exclusions.md), [diagnostics evidence](validation/redacted-diagnostics.md) |
| App-managed categories | [ManagedStorageView.swift](../Still/App/ManagedStorageView.swift), [ManagedStorageCategory](../Packages/StillCore/Sources/StillCore/ManagedStorage.swift); #31/#54 |
| Shared UI | [DesignSystem.swift](../Still/App/DesignSystem.swift), [DesignGallery.swift](../Still/App/DesignGallery.swift), [native contract](DESIGN-SYSTEM.md); native visual evidence under [visual](visual/README.md) |
| Future tools and qualification | [HomebrewInspection.swift](../Still/App/HomebrewInspection.swift), [PipInspection.swift](../Still/App/PipInspection.swift), [DockerInspection.swift](../Still/App/DockerInspection.swift), [current capability gates](DEVELOPMENT.md); existing #6/#16/#18/#20/#22–#35 |

## Explicit departures and non-features

- SF Symbols, native sheets/controls/materials and measured native sizing replace web CSS; no mobile-layout requirement or exact synthetic disk-category chart.
- Downloads select-all includes all eligible ordinary files, not only old installers. It never targets whole folders. This approved correction supersedes early fixture naming.
- One live session selection replaces obsolete staged “Add/Update plan” drafts. View cleanup plan navigates; Back preserves membership. Quit ends unexecuted authority; crash journals remain.
- No inspector Exclude button; explicit settings rules govern exclusions. No automatic scan, automatic cleanup, desired-free-space input, universal Undo or Trash emptying.
- M1 lacks cloud/developer/browser mutation by approved design; those are retained future tickets, not removed features. Cloud metadata in Overview is explicitly scoped, not a made-up aggregate or eviction estimate.
- App-managed directories/libraries may remain Unknown/Not inspected rather than recursively traversed for a sample-looking total. No direct backup/library/database deletion.
- Review-only browser/cache/permission/alert simulations and milestone switcher do not ship. A development future flag does not promote M2–M6 to production.
- History is currently cleanup-only; whether this is the intended permanent departure is **unresolved #51**, not silently accepted here. Appearance persistence was unresolved in this baseline; #53 is now implemented under SHELL-APPEARANCE.md with [bounded qualification](validation/shell-appearance.md).

## Decision checkpoint and ongoing acceptance gate

The user has confirmed the connected #44/#46/#47/#48 contract plus #50's terminal boundary in [FLOW-LOCK](FLOW-LOCK.md). Q1–Q30 and FL01–FL14 are the current intended behavior. The baseline table still describes f9e854f; no gap becomes Covered merely because its repair was approved.

The scan-status/inspector/scope-row presentation and connected delivery decisions are confirmed in FLOW-LOCK Q27–Q30. Before feature code resumes, review their annotated visual states. Do not reopen settled flow decisions or add unrelated hardening. #51/#53 retain their separate History/appearance decisions; #49/#52/#54 and future qualification remain tracked.
The checkpoint is not a demand to build all M2–M8 features first. Future adapter/monitoring gates remain on their own issues; current M1 must present honest states and still form a coherent product. No general signing dependency is reintroduced.

For every subsequent feature/repair ticket:

1. Name affected parity IDs and milestone; identify prototype screen/state, native entry/return route and expected action/consequence. If behavior differs, record an approved reason or unresolved decision.
2. Change SPEC and DESIGN-HANDOFF together when the contract changes. Update shared components/gallery rather than implementing a new isolated style. Historical evidence stays historical.
3. Cover the **whole flow**, not only its seam: entry → discovery/evidence → selection/refinement → confirmation/Cancel → execution/result/recovery → next route, as applicable. Check zero/unknown/partial/stale/denied/unsupported states and unaffected work.
4. Exercise agreed public boundaries; preserve exact safety assertions. Review original source-pinned native Light/Dark captures at initial/minimum sizes, viewport/focus/scroll and caller return. Missing manual/platform checks remain explicit ticket items.
5. Update this ledger and the owning issue with source, test/capture evidence and remaining limits. “Covered” requires a useful product journey and documented parity, not merely a component, helper, probe or green build. An intentionally future-gated implementation must retain explicit promotion/qualification ownership; do not describe an inaccessible development route as shipped product parity.

## Tracking and delivery order

Parent #45 tracks this audit and current flow reconciliation. New focused findings: #46 Locations, #47 Explorer/inspector, #48 route/local-data integration, #49 capacity, #50 results, #51 History contract, #52 growth flows, #53 shell/preference contract, #54 release-archive guidance. Existing #44 owns Cleanup plan grilling. Flow decisions for #44/#46/#47/#48 and the #50 boundary are approved; annotated visual/delivery readiness is still being reviewed. Other issues retain their triage/gates. Related future qualification/action tickets are retained and receive the corresponding parity references rather than duplicate “build browser cleanup” issues.

The connected flow discussion is complete and explicitly confirmed. The next checkpoint is annotated visual-state approval under FLOW-LOCK; design/delivery Q27–Q30 are confirmed. Add native implementation blockers when those slices are agreed; sub-issue containment alone is not a blocker.

## Recovery, Results and access checkpoint — #60/#61/#63

The approved connected journey now includes caller-aware manual recovery, retained History disclosure/viewport context, truthful terminal outcome summaries, safe unresolved recovery routing, and restrained optional folder-access education. Shared Light/Dark components and original initial/minimum captures remain aligned with the approved flow lock. [Qualification](validation/recovery-results.md) records actual red → green, 5/5 terminal tests, 2/2 History maintenance tests and 8/8 affected regressions. Synthetic outcome presentation remains separate from Core executor fixtures and real OS qualification. Full parent issues and all future milestones stay open; #62 Local records is the next dependent slice, and M8 remains deferred.


## Shell and appearance lock — October 24

Current N05/N06/N07/A04 decision overlay: #53 Q1–Q13 and consolidated contract are user-confirmed in [SHELL-APPEARANCE](SHELL-APPEARANCE.md). Historical audit rows remain baseline findings. Current N05/N06/N07/A04 disposition is Covered within #53’s bounded implementation at `c5886e8`; [qualification](validation/shell-appearance.md) records actual normal-click/theme/size/flow proof and limits. Badge categories, accurate context/monitoring, saved shared appearance and partial failure behavior are explicit. The locked contract is implemented; broader OS/accessibility and future-feature gates remain unchanged.

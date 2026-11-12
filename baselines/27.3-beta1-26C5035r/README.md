# macOS 27.3 beta1 `26C5035r` — 2026-11-04 retest

Host: MacBook Pro `Mac15,11`, Apple M3 Max. Boot 10:07:04 +0800; install receipt
10:09:06 +0800. Kernel `xnu-13432.60.57~99`.

## Scope and method

`log-summary.json` covers 10:07:04–16:03:52 +0800 (T+0 to T+5h56m48s).
One combined `/usr/bin/log show --start … --end … --style ndjson --predicate …`
query completed successfully. Predicates are included in that file. Default persisted
log levels, without `--info --debug`, matching the RC1 capture command. No raw
message bodies are committed. The host was in normal use, not idle. These counts
are **not matched pairs** with RC1's 40-minute capture, and lower peaks do not prove a fix.

Apple's [27.3 beta release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27_3-release-notes)
were checked on 2026-11-04; none of this repository's outstanding issues are explicitly listed as resolved.

## Findings

| Issue | Observation | Interpretation |
|---|---|---|
| #34 SwiftUI MenuBarExtra AXPress | Existing MBXWindow app opens/closes through AXPress in 5 successful trials across two usable runs; fresh compilation of the checked-in probe opens 3/3. DuoUpdater itself opens a 370×449 panel in 0.13 s through a single AXPress. | Working on this host/build; 27.2 release guest remains broken (0/3 repeated presses, mouse control opens); see `vm-27.2-axpress.md`. VoiceOver itself was not tested. |
| #26 notification visibility race | 0/8 visible at immediate query, 5/8 at 5 ms, 6/8 at 10 ms, 8/8 at 15 ms. Serial first-visible query issue time 1.48 / median 7.065 / 13.48 ms; replies 12.64–17.34 ms. | Still reproducible. One run; no latency trend claimed. Chrome helper lifecycle was not tested. |
| #18 Contacts group change history | 138,247 ACHANGE rows with ZENTITY=19 across 12 sources, vs 128,836 on RC1. All seven previously nonzero sources increased; a previously empty source now has one row. 42,529 failing client fetches across 47 processes, last at 15:57:55. | Still failing on 27.3; accumulated delta spans intervening 27.2 uptime and is not a 27.3 growth rate. |
| #19 imagent sandbox retry | 39,130 ContactsAccountsService records, 29,362 naming error 159. Profile remains 405 lines, with no ContactsAccountsService mention. | Still reproducing. `imagent.sb` is the current profile; no byte-identity claim without comparison to an archive. |
| #2 Shortcuts/Siri storm | 750,245 records; peak 3,326/s; 728 seconds ≥500/s. Bursts continue through the 15:40 bucket (T+5h33m onward). | Still storming well after boot; lower peak than RC1 is not a controlled improvement measurement. |
| #1 CoreMedia | 412 matching records, 269 from DingTalk. | Signature persists; app-dependent volume is not evidence of fix or regression. |
| #24 mds/CoreDuet | 65,576 records, peak 720/s at 10:26:35. | Burst captured; lower than historic storm, not sufficient to call fixed. |
| #15 appstoreagent/dasd Code=8 | 0 matching records. | Continues not reproducing; conditional trigger not exercised. |
| #23 ecosystemd trust loop | 3,262 ecosystemd/ecosystemanalyticsd records, 390 anchor-fetch messages, all from ecosystemanalyticsd; ecosystemd itself 0 anchors; 0 UNIX error exception: 5 in either process. | No recurrence of the original ecosystemd EIO retry loop observed. |
| #35 menu bar unclickable | 0 WindowServer messages containing Corrupt tree. | Not reproduced; correlation signature is not a controlled trigger or a fix criterion. |

`diagnostic-inventory.txt` inventories reports modified since boot. No matching new
modelmanagerd/NotificationCenter crash report was found. WeChat has a `.spin` report;
this is not classified as the old ViewBridge crash. WindowServer has a CPU-resource
report, but normal desktop load was not controlled and no idle-CPU verdict is made.

## AXPress details and limits

`axpress-window.txt`: 2 successful opens/closes, third attempt lost the icon from
the AX tree. `axpress-window-repeat.txt`: header only, inconclusive and excluded.
`axpress-window-source.txt`: freshly compiled checked-in probe, 3 successful
opens/closes, window layer 101, 194×96. The mouse-click control was correctly
refused because Alcove covered the target. Thus no synthetic click is counted as
an AXPress success. `axpress-duoupdater.txt`: one AXPress, panel left open for inspection.

`mbxdiag.txt` still reports a nil target/action on the in-process NSStatusBarButton.
AXPress now works despite that, so the old missing-target/action observation alone
is **not a sufficient explanation** for the earlier defect. The 27.3 implementation
path has not been established by binary analysis.

AppKit control opened 3/3 (`axpress-appkit.txt`); `.menu` control emitted only a
header (`axpress-menu.txt`), so it supplies no usable result in this pass.

#27 inert banners, #28 AirPods, #29 focus-chain freeze, #35 whole-menu-bar failure
still need their specific manual trigger or an actual recurrence. Absence from this
capture does not establish a fix.

## Guest comparison

[`vm-27.2-axpress.md`](vm-27.2-axpress.md) records the VMPal 27.2 release `26B123` control.
Both guest and host DuoUpdater report version 0.5.21. Guest AXPress fails while
mouse input opens the panel; host AXPress opens it.

## Later investigation, 2026-11-12–13

[#36 — DuoShot ignores the system menu-bar visibility switch](https://github.com/jizhi0v0/macos27-beta-issues/issues/36)
was tested separately from the November 4 capture above. The unchanged installed
bundle obeys the switch when copied to the repository test directory (3/3 and
2/2 rounds), while fresh instances from two `/Applications` paths fail (0/2
each). Exact system association fault and first affected build unknown.
[Experiment ledger, switch readbacks, screenshots, and bundle comparison](menu-bar-visibility/README.md).

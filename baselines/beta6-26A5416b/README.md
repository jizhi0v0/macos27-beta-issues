# beta6 `26A5416b` — first measurements

Upgraded from beta5 `26A5406e` on **2026-08-19**, boot at **13:12:23**.
Xcode deliberately left at `27A5237l`, so the OS row moves and the toolchain row does not —
SDK-tracked entries (**#11**) are untouched and not re-tested here.

Baseline to compare against: [`../beta5-final/`](../beta5-final/README.md).

| file | contents |
|---|---|
| `postboot-window.txt` | the one-shot post-boot window, T+0 → T+7m47s |
| `contactsd-backlog.txt` | #18 per-source rows, taken T+9m |

Raw post-boot log (32 MB gz) is at `~/Developer/macos27-beta6-postboot/` — not committed
(public repo; a full system log carries paths and identifiers). Captured with
`log show --start <boot>`: `--last 8m` **spans the reboot** and mixes the beta5 session in,
which is what the first two ad-hoc counts did.

---

## Decided

### #18 contactsd — 🔴 **still broken on beta6, decisively**

| | beta3 | beta5 08-11 | beta5 08-18 | **beta6 T+9m** |
|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 90,209 | **91,030** |
| worst single source | 17,918 | 23,849 | 27,202 | **27,388** |

**All 12 sources carried over, every non-zero one increased, none reset.** That settles the
question this snapshot was built to answer: the upgrade did **not** migrate or rebuild the
Contacts stores, so there is no "cleared by the upgrade" false positive to rule out — the same
backlog crossed an OS upgrade and kept growing. contactsd log volume is unchanged too
(27,809 lines in the 8-minute window ≈ 214k/h, against beta5's ~218k/h).

### #19 imagent — 🔴 unchanged **at the source level**

`com.apple.imagent.sb` is still **404 lines** and still the outlier against **26** sibling
profiles that name `com.apple.AddressBook.ContactsAccountsService` (both re-verified on beta6).
The one-line fix was not applied. 2,383 `ContactsAccountsService` lines in the post-boot window.

### #2 Shortcuts / siriactionsd — measured **worse**, one window

| | beta5 (post-boot capture) | **beta6 (post-boot)** |
|---|---|---|
| peak rate | 181 lines/s | **864 lines/s** |
| lines in window | — | 16,203 |

Busiest seconds: 864 @ 13:13:19, 725 @ 13:13:21, 640 @ 13:13:55 — i.e. within ~60 s of boot.
Same window *shape* as beta5's figure, so the comparison is fair, but this is **one window**
and has not been replicated. Not a verdict yet.

## Not decidable yet

### #3 WindowServer — 🔴 **46.5–48.4 % on beta6**, but *when* it broke is NOT established

The measurement is solid and replicated. The attribution to beta6 is **not**, and an earlier
version of this file overstated it.

**What is established:** on beta6 `26A5416b`, WindowServer sits at 46.5 % / 48.4 % on a
validated quiesced desktop, against the ~4 % that closed #3 🟢 on beta5.

**What is not:** that beta6 is where it broke. The beta5 🟢 dates from **2026-08-11** and covers
beta5's early days only. On **2026-08-18 — still beta5** — WindowServer's lifetime average was
already **37.4 %** (112,796 s over 3 d 11 h) with a 79.7 % loaded sample. That reading was flagged
at the time as not-quiesced and therefore not decision-grade, and a quiesced beta5 re-test was
scheduled *before* the upgrade — it was never run, and the upgrade made it permanently
unobtainable. See [`../beta5-final/README.md`](../beta5-final/README.md) §7.

So two hypotheses remain live and the data on hand cannot separate them:

- **(a)** beta6 regressed the compositor;
- **(b)** it came back during beta5 already — some later condition — and beta6 merely inherits it.

Weak evidence for (a): beta6 reaches 46.5 % at ~24 min uptime, whereas historically this defect
showed at 13–21 min (beta1) and 39 min (beta2) uptime, so an uptime-accumulation model does not
obviously fit a beta5-that-was-fine-at-08-11. Weak evidence for (b): the 08-18 lifetime figure.
Neither settles it.

**This is what makes the beta5↔beta6 binary diff the decisive next step**, not just a nice-to-have:
if SkyLight's update path is byte-identical across the two builds, beta6 did not regress the code
and the cause is environmental or state-based, which redirects the whole investigation.

Third run is clean and the *measurement* is in.

| run | WindowServer | window valid? |
|---|---|---|
| 13:14–13:16:56 | 45.6 % | ✗ post-upgrade reindex (`mds_stores` 63→84 %, `corespotlightd` 42 %), and idle reset mid-window (`actualUserIdle` 8.2 → 27.2) — the machine was touched |
| 13:28:28–13:31:17 | 47.5 % | ✗ screen saver started 13:30:28, 75 s into the 122 s window (~39 % of it). A hand-launched `caffeinate -du -t 420 &` had died at age 00:00:12 |
| **13:36:38–13:39:29** | **46.5 %** | ✅ **valid** |

**Why run 3 counts:** the script held its own assertion for **2 m 04 s**, covering the whole
122 s window (powerd: `Created` → `ClientDied age:00:02:04`, killed by the script afterwards).
loginwindow logged `PMNoDisplaySleepEnabled so do not launch screen saver` — the screen saver
was *suppressed by the assertion*, not merely late. `actualUserIdle` was sampled once at 82.6 s
and **never reset**, so there was no input during the window. Reindex was finished, Claude was
quit, and the only processes owning on-screen windows were Finder (13), Surge (2), WindowServer
(2), WindowManager and DuoTerminal.

**The comparison:**

| | WindowServer, quiesced |
|---|---|
| beta4 `26A5388g` (the original regression) | 42–46 % floor, min 42.0 % across 10 replicates |
| beta5 `26A5406e` → closed 🟢 | **~4 %** clean idle, 7.7 % with menu-bar apps |
| **beta6 `26A5416b`** | **46.5 %** |

Same machine, same script, same method. beta6 is back inside the beta4 band — a 10×
regression against beta5, far too large to be explained by the two things still running
(Activity Monitor at 5.5 %, `ecosystemd` at 18 % at midpoint). `MenuBarAgent` is 0.2 %, so
this is **not** [#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22)'s mechanism.
`Invalid window` spam is 9/60 s, still decoupled from the CPU as always.

**Replicated.** A fourth run (13:45:50–13:47:52), with Activity Monitor also quit, returned
**48.4 %** — both validity checks passing (`screen saver: did not start`, `user input: none
detected (idle never reset)`, single sample 56.3 s). Saved as `ws-idle-run4.txt`.

| run | WindowServer | valid |
|---|---|---|
| 1 | 45.6 % | ✗ reindex + input |
| 2 | 47.5 % | ✗ screen saver 39 % of window |
| **3** | **46.5 %** | ✅ |
| **4** | **48.4 %** | ✅ |

## The stack — what is actually burning the CPU

`sudo spindump WindowServer 8`, 2026-08-19 13:44:21, archived at
`~/Developer/macos27-beta6-postboot/ws_spindump_beta6.txt.gz`. spindump's own accounting gives
WindowServer **3.472 s / 8 s = 43.4 %**, independently corroborating the 46.5 / 48.4 % readings.

**All of it is one thread.** `ws_main_thread` takes **3.184 s** of the 8 s (39.8 %); every other
WindowServer thread combined is ~0.15 s. Of its 801 samples, 501 sit idle in `mach_msg` and
**297 are in a single path**:

```
CGXRunOneServicesPass -> post_port_data -> non_coalesced_timer_handler
  -> run_timer_pass -> update_display_callback -> CGXUpdateDisplay      (297)
    -> WS::Updater::UpdateDisplays                                      (158 + 60 + 58 + 10)
      -> WS::Updater::prepare_coreanimation                             (158)
        -> WS::Updater::defenestrator3::ca_prepare_begin_window_update   (155)
          -> WSSessionConnectionPerformWithPluginOwner                   (155)
            -> CARenderUpdateAddContext2                                 (144)
              -> CA::Render::Update::add_context                         (76 + 63)
                -> CA::Render::Updater::prepare_layer / prepare_layer0 /
                   prepare_sublayer0   -- recursing 40+ levels deep
                  -> CA::OGL::render_layers / LayerNode::apply /
                     ImagingNode::render
```

Four separate `UpdateDisplays` passes appear inside one 8 s sample, on a desktop whose only
on-screen windows are Finder (13), Surge (2), WindowServer (2–3), WindowManager and DuoTerminal.

**The part that makes this a defect rather than workload:** *nothing was feeding it.* Across all
801 samples, the only processes seen committing CoreAnimation transactions at all are
**WindowManager (3 samples), MenuBarAgent (3) and DuoTerminal (2)**. No client is animating.
WindowServer is running full display-update passes — walking and re-preparing a 40+-deep layer
tree, down into actual `CA::OGL` rendering — against a **static** scene, on a timer that the
symbol name says is explicitly *not* coalesced (`non_coalesced_timer_handler`).

**Caveat, stated:** two valid runs, not ten.

**Still open:** which window owns the 40+-deep layer tree. The spindump does not name the
`CGXWindow*`, and `WSSessionConnectionPerformWithPluginOwner` only says a plugin owner is
involved. A beta5↔beta6 diff of `WS::Updater::UpdateDisplays` / `prepare_coreanimation` is the
obvious next step — the beta5 dyld shared cache is archived, so that diff is still possible.

### #1 CoreMedia — emitter set did not match, retest needed

56 hits in the post-boot window (Mail 31, WeType 22, UURemote 3) against beta5's **1,744 in
8 min**. **Not comparable:** 77 % of beta5's count was DingTalk (1,338), and DingTalk was not
running — it had been quit for the WindowServer test. Re-run with DingTalk, WeType and Mail
all up before reading anything into this. (UURemote is a new emitter not in the write-up.)

## Other post-boot counts, recorded without interpretation

| | beta6 post-boot window (7m47s) |
|---|---|
| total log lines | 1,569,559 |
| `ecosystemd` (#23) | 56,808 |
| `mds` + `mds_stores` (#24) | 8,792 |
| `Invalid window` (#3 spam) | 296 |
| `Could not fetch group`, all processes (#18) | 1,054 |
| `AddressBookManager` spawns | 1 |

---

# #3 — probe round 2 (2026-08-19 14:00–14:10): three leads, three negatives

State at probe time: uptime 50 min, near-idle desktop (Finder 13 windows, Surge 2,
WindowServer 2, WindowManager 1, Claude 1, DuoTerminal 1). Paired before/after design with the
same app set throughout, cumulative `utime+stime` deltas over 60 s windows.

## 1. `killall MenuBarAgent` — no effect

| phase | WindowServer | MenuBarAgent |
|---|---|---|
| A (before) | **46.5 %** | 0.0 % |
| B (after restart, 45 s settle) | **46.5 %** | 0.1 % |

MenuBarAgent did restart (pid 683 → 66158); WindowServer kept pid 401. The number did not move
by so much as 0.1 point, and MenuBarAgent's own CPU was ~0 throughout.

**[#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22)'s mechanism does not explain
#3 on beta6.** This also removes the proposed bridge between the binary diff's region changes and
the CPU: those changes were interesting *because* #22 blamed region-state accumulation, and the
one intervention #22 reports as clearing it does nothing here.

Phase A's 46.5 % is also a fifth independent reading of the floor, matching 46.5 / 48.4 / 45.6 /
47.5 — and this one with Claude open, so the floor is not sensitive to that either.

## 2. Continuity / screen capture — no session

`ContinuityCaptureAgent`, `replayd`, `SidecarRelay`, `AirPlayXPCHelper` all present but at
**0.0 %**. One built-in display, `Mirror: Off`, no capture assertions. The 1.2–2.5 % that
`ContinuityCaptureAgent` showed in two earlier midpoint samples was not a session.

## 3. Brightness / EDR — **falsified again; an overstatement retracted**

A 60 s sample showed WindowServer logging ~2,500 QuartzCore `commitBrightness` / `swap
brightness` lines — ~42/s on a static desktop — and this was briefly written up here as "the
driver". **That was wrong, from a single 60 s window that happened to land on bursts.** Checked
properly:

- **Coverage over 300 s: 46 seconds of 300 contain any brightness line** — bursty, not sustained.
  (beta5's figure in [#25](issues/apple-corebrightness-nan-oscillation.md) was 21 of 300.)
- Peak rate **240–242 lines/s**, exactly the 120 pairs/s = one update per frame at 120 Hz that
  #25 already documented. Same mechanism, not a new one.
- **Zero brightness frames in the hot stack.** A `grep -i` for brightness/EDR/tone-map over
  `ws_main_thread` returns 5 hits, all false positives — `AGX…bindUntrackedResourcesToChannel`
  and `initWithSharedResourceList`, where `trackedResources` contains the substring `edR`.
  A strict grep for real symbols returns **0**.

So **#25's original falsification survives on beta6**: brightness cannot account for a sustained
floor when it covers 15 % of seconds and appears in none of the hot stacks. The one new fact
worth carrying back to #25 is that its burst *coverage* is about 2× beta5's — a frequency data
point for #25, not an explanation for #3.

## Where #3 stands after this round

The floor is real, replicated five times, and none of the three obvious external drivers explains
it. The compositing code is identical to beta5's. What remains is the shape of the thing being
composited: the spindump's `prepare_layer` recursion is **40+ levels deep**, and the update pass
is not early-outing on a static scene.

Next probe, and it needs no new tooling: **bisect the on-screen window owners.** Quit them one at
a time — Finder (13 windows), Surge, WindowManager, DuoTerminal — measuring 60 s between each.
If one of them owns the deep tree, the floor drops when it goes.

---

# #3 — refresh rate: beta6's floor is NOT beta4's floor

ProMotion disabled, display confirmed at **60.0 Hz** via `CGDisplayCopyDisplayMode`.
Quiesced run saved as `ws-idle-60hz.txt`, both validity checks passing.

| | WindowServer |
|---|---|
| **120 Hz**, quiesced ×2 | 46.5 %, 48.4 % → mean **47.5 %** |
| **60 Hz**, quiesced | **34.2 %** |
| 60 Hz, loaded ×3 (Chrome/WeChat/DingTalk/Activity Monitor also up) | 34.1 / 36.9 / 38.2 → mean 36.4 % |

The 60 Hz quiesced desktop was **cleaner** than the 120 Hz ones — Finder 13, WindowServer 2,
DuoTerminal 1, WindowManager 1, with no Claude and no Surge windows, where the 46.5 % run had
Claude 1 + Surge 2. So 34.2 % is if anything an under-statement of the gap.

## What halving the refresh rate did

**−27.9 %.** Pure per-frame work would have given −50 %. Treating it as one per-frame component
`P` plus one refresh-independent component `F`:

```
F + P   = 47.5      (120 Hz)
F + P/2 = 34.2      (60 Hz)
    ->  P = 26.5 points (56 %)     F = 21.0 points (44 %)
```

So a little over half the floor scales with refresh and a little under half does not.

## The finding: this does not have beta4's shape

[#3](issues/apple-windowserver-invalid-window.md) recorded beta4 as **refresh-independent** —
42.0 % at 60 Hz vs 45.9 % at 120 Hz, five replicates each, a **−8.5 %** reduction, and the
write-up says in as many words: *"Halving the display refresh rate does not halve WindowServer's
CPU. Do not bother."*

beta6 drops **−27.9 %** under the same manipulation. The magnitude at 120 Hz coincides
(46–48 % vs 42–46 %), which is what made this look like beta4's floor returning — but the two
respond to refresh rate completely differently. **Same number, different mechanism.**

That reframes the whole question. It is evidence that beta6's floor is a *new* defect that
happens to land in the same range, not a re-appearance of the beta4 one — and it is consistent
with the binary diff, which found beta5's and beta6's compositing code identical: if beta6 had
regressed by reverting to beta4's code, the code would differ and the refresh response would
match. Neither is true.

**Caveats:** n=1 at 60 Hz quiesced, though the three loaded 60 Hz runs (34.1–38.2 %) bracket it
consistently. beta4's figures come from a different build and a different app set, so the −8.5 %
vs −27.9 % contrast is across-study, not a controlled experiment.

**Practically:** 60 Hz buys back ~13 points of a core. Real, but not a fix — 34.2 % is still
~8× beta5's ~4 %.

## Next

The 44 % that does *not* scale with refresh is the more interesting half: something is costing
~21 points regardless of how often frames are produced. The window-owner bisect is still the
next probe, and it should now be run **at both refresh rates**, since a window that owns the
per-frame half and one that owns the fixed half would look different.

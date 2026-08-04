VERIFICATION: FILE-READY (upgraded 2026-07-25, beta4 `26A5388g`) — the 2026-06-26 HOLD is lifted. The decisive quiesced test was finally run under control: WindowServer holds a **stable 45.9% floor (5 replicates, sd 0.9, spread 1.1×) on a desktop with nothing animating** and Spotlight fully settled. **Headline evidence: the floor is independent of refresh rate — 45.9% at 120 Hz vs 42.0% at 60 Hz (5 replicates each), so it is not per-frame compositing cost.** MenuBarAgent, aggregate app load, brightness, remote-desktop capture, dynamic wallpaper, window count and the Spotlight storm were each tested and falsified — see `issues/apple-windowserver-invalid-window.md` for the full elimination table. Attach: spindump captured during the idle window, sysdiagnose, and the `tools/ws-replicate.sh` output. (Superseded prior text: the beta2 "may just be compositing workload" HOLD.)

# Title
WindowServer sustains ~46% CPU on an idle single-display Mac with no animating content (macOS 27.0 beta4 26A5388g)

# Apple area / component to select
Windowing / WindowServer (SkyLight / CoreGraphics / QuartzCore).

# Description
On macOS 27.0 (26A5388g), WindowServer holds ~46% CPU on a genuinely idle desktop — every user application quit, including all menu-bar apps, with only Finder, System Settings and a terminal window on screen and nothing animating.

This is not compositing workload. It was measured as five back-to-back 60-second windows in a single state, using cumulative utime+stime deltas rather than the decaying average `ps %cpu` reports:

  rep 1: 45.5%   rep 2: 47.3%   rep 3: 46.4%   rep 4: 45.0%   rep 5: 45.1%
  mean 45.9%  min 45.0%  max 47.3%  sd 0.9  spread 1.1x

Concurrently, Spotlight was fully settled (aggregate mds + mdworker CPU = 0.0% across all five windows), so indexing load is excluded.

A spindump shows ws_main_thread accounts for 84% of the process CPU (4.825 s of 5.744 s), with 56% of samples under update_display_callback -> CGXUpdateDisplay:
  - 27% in WS::Updater::prepare_coreanimation -> ca_prepare_begin_window_update, recursing ~54 stack frames deep through CA::Render::Updater::prepare_layer0 / prepare_sublayer0
  - 19% in CompositorMetal::composite -> CA::OGL::render
  -  5% in present_update -> CA::WindowServer::IOMFBServer::finish_skylight_update

On the idle desktop the same structure persists at lower amplitude (1001 samples: 590 idle in mach_msg, 321 in update_display_callback, 168 in prepare_coreanimation) — that is, WindowServer keeps running the display-update timer and re-preparing CoreAnimation layer trees on a static screen.

KEY OBSERVATION — the floor is independent of refresh rate, so it is not per-frame compositing cost. With the set of running applications held constant, halving the display refresh rate barely moves it. Two 5-replicate runs, refresh rate recorded by the measuring script itself:

  120 Hz: mean 45.9%  (min 45.0, max 47.3, sd 0.9)
   60 Hz: mean 42.0%  (min 34.9, max 44.3, sd 3.6)
   42.0 / 45.9 = 0.92

Halving the frame rate removed roughly 8% of the cost, not 50%. Whatever WindowServer is doing at idle therefore runs at a fixed rate or continuously, rather than once per displayed frame. This seems the most useful handle for narrowing the cause.

Separately and continuously, the SkyLight log emits `_CGXPackagesSetWindowConstraints: Invalid window` at ~4/sec (690 lines in 170 s; 320 in 73 s in an independent window), independent of load and of how many apps are running. This line appears in 0 hot stacks, so it is not the CPU sink, but it indicates a window persistently failing constraint validation. The lines carry no PID, so the offending window cannot be attributed from the log alone; a window-server / CGWindowList dump is needed.

# Steps to Reproduce
1. Run macOS 27.0 26A5388g on a Mac15,11 with only the internal display (no external monitor, no mirroring).
2. Quit every user application, including all menu-bar / notch apps (here: Alcove, Klack, Surge) and third-party input methods. Leave Finder and a terminal.
3. Disable the screensaver and display sleep so the compositor is not parked.
4. Measure WindowServer's cumulative CPU (utime+stime) over several consecutive 60-second windows while not touching the machine. Do not rely on `ps %cpu`, which reports a decaying average.
5. Observe WindowServer holding ~45-47% across every window.
6. `log show --last 60s --predicate 'process == "WindowServer"'` — observe `_CGXPackagesSetWindowConstraints: Invalid window` at ~4/sec.

7. Set the display to 60 Hertz (System Settings -> Displays -> Refresh Rate) and repeat step 4 without changing anything else — observe that the cost does NOT halve (~42%).

# Expected vs Actual
- Expected: with no client committing CoreAnimation transactions and no on-screen content changing, WindowServer should fall to a low single-digit idle baseline; the display-update timer should coalesce away rather than re-walking layer trees.
- Actual: WindowServer sustains ~46% CPU indefinitely at 120 Hz and ~42% at 60 Hz, continuing to run update_display_callback and prepare CoreAnimation layer trees on a static screen, and emits ~4 window-constraint errors per second.

# Workaround
None found. Quitting applications removes only the load stacked on top of the floor (81% -> ~46%); the floor itself persists. Dropping the display to 60 Hz does not help (42.0% vs 45.9%).

# What was ruled out
Each of these was tested and falsified, not assumed:
- MenuBarAgent menu-bar animation — quitting Alcove dropped MenuBarAgent from 21.9% to 0.1%; WindowServer did not drop (44.8% -> 49.3% -> 52.3%).
- Aggregate application load — quitting Claude, Chrome, Telegram, DingTalk, Mail, IntelliJ, Spotify, OrbStack, Alcove and Klack took WindowServer from 81.2% to ~46%, where it stopped. The stated prediction was <20% if load explained it.
- Brightness / corebrightnessd — 0 brightness frames in hot stacks; the NaN oscillation burst occurred once in 30 minutes and lasted 12 s.
- Remote-desktop screen capture — AweSun, RustDesk, UURemote and ToDesk all at 0.0% CPU with zero CGDisplayStream / ScreenCaptureKit / SCStream log lines in 10 minutes.
- Dynamic or aerial wallpaper — wallpaper Provider is "default"; WallpaperAerialsExtension used 0.001 s per 10 s.
- Window count — 80 windows total, 5-8 on screen.
- Spotlight indexing — mds + mdworker aggregate was 0.0% throughout the replicated run.
- Display sleep during measurement — coreaudiod held PreventUserIdleDisplaySleep across the whole measurement period.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.0 26A5388g (beta4)
- Single internal Liquid Retina XDR display, 3456x2234 @ 120.0 Hz, no external monitor, no mirroring
- Liquid Glass compositing active; Reduce Transparency and Reduce Motion both OFF

# Suggested attachments
- spindump of WindowServer captured during the idle window (`tools/ws-idle-spindump.sh`)
- sysdiagnose taken while WindowServer is at the ~46% floor with all apps quit
- `tools/ws-replicate.sh` output showing the five replicates and the spread
- `log collect --last 5m` archive showing the Invalid window cadence

VERIFICATION: CONFIRMED — WindowServer 61.7% CPU / 18:16 cumulative TIME at uptime 39 min, and 159 `_CGXPackagesSetWindowConstraints: Invalid window` in `log show --last 60s` steady ~2.6/sec (2026-06-26 10:32 +0800, beta2 26A5368g).

# Title
WindowServer sustains ~48–62% CPU with continuous `_CGXPackagesSetWindowConstraints: Invalid window` (SkyLight) on a single-internal-display Mac, long after boot

# Apple area / component to select
Windowing / WindowServer (SkyLight / CoreGraphics).

# Description
On macOS 27.0 (26A5368g), WindowServer holds high CPU well past boot with foreground apps mostly idle and no external display attached. At uptime 39 min, WindowServer[445] was at 61.7% instantaneous CPU with 18:16 cumulative TIME (≈47% average over the whole 39 min uptime). Concurrently the SkyLight log repeats `_CGXPackagesSetWindowConstraints: Invalid window` at a steady rate: 159 occurrences in a 60s window, ~2.6/sec, spread evenly across the whole window (10:31:59 → 10:32:58) — i.e. a continuous condition, not a one-time post-boot transient.

The `Invalid window` lines carry no PID, so the offending window cannot be attributed directly. NOTE: an earlier hypothesis blaming `textunderstandingd` was withdrawn — on re-measurement, five unrelated system services (`textunderstandingd`, `studentd`, `nsattributedstringagent` ×2, `universalaccessd`) all fail WindowServer pings simultaneously, which indicates WindowServer is saturated and slow to answer pings (a symptom), not that any one of them owns the bad window. The window that triggers the loop is currently unidentified; a sysdiagnose with a window-server/CGWindowList dump is needed to attribute it.

# Steps to Reproduce
1. Run macOS 27.0 26A5368g on a Mac15,11 with only the internal display (no external monitor, no mirroring).
2. Use the machine normally for ~30+ min.
3. `ps -Aceo pid,%cpu,time,comm -r | grep WindowServer` — observe sustained high CPU and large cumulative TIME.
4. `log show --last 60s --predicate 'eventMessage CONTAINS "Invalid window"'` — observe continuous `_CGXPackagesSetWindowConstraints: Invalid window` at a few per second.

# Expected vs Actual
- Expected: WindowServer CPU drops to a low idle baseline when foreground apps are idle and no display topology changes are occurring; no recurring window-constraint errors.
- Actual: WindowServer sustains ~48–62% CPU at idle and emits `_CGXPackagesSetWindowConstraints: Invalid window` ~2.6/sec continuously, well past boot.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.0 26A5368g
- Single internal Liquid Retina XDR display, no external monitor, no mirroring
- Liquid Glass compositing active (some baseline cost expected, but does not account for sustained ~48% + the recurring error)

# Suggested attachments
- sysdiagnose taken while WindowServer CPU is high (includes window list / CGS dump)
- `log collect --last 5m` archive showing the Invalid window cadence and the `pid 1437 failed to act on a ping` lines
- `ps` snapshot showing WindowServer %CPU and cumulative TIME
- Spindump of WindowServer during the high-CPU period

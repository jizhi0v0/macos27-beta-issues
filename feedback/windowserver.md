VERIFICATION: CONFIRMED — WindowServer 61.7% CPU / 18:16 cumulative TIME at uptime 39 min, and 159 `_CGXPackagesSetWindowConstraints: Invalid window` in `log show --last 60s` steady ~2.6/sec (2026-06-26 10:32 +0800, beta2 26A5368g).

# Title
WindowServer sustains ~48–62% CPU with continuous `_CGXPackagesSetWindowConstraints: Invalid window` (SkyLight) on a single-internal-display Mac, long after boot

# Apple area / component to select
Windowing / WindowServer (SkyLight / CoreGraphics).

# Description
On macOS 27.0 (26A5368g), WindowServer holds high CPU well past boot with foreground apps mostly idle and no external display attached. At uptime 39 min, WindowServer[445] was at 61.7% instantaneous CPU with 18:16 cumulative TIME (≈47% average over the whole 39 min uptime). Concurrently the SkyLight log repeats `_CGXPackagesSetWindowConstraints: Invalid window` at a steady rate: 159 occurrences in a 60s window, ~2.6/sec, spread evenly across the whole window (10:31:59 → 10:32:58) — i.e. a continuous condition, not a one-time post-boot transient.

The `Invalid window` lines carry no PID, so the offending window cannot be attributed directly. Best-effort isolation (hypothesis, not confirmed): in the same capture WindowServer logged `pid 1437 failed to act on a ping it dequeued before timing out` ×5. PID 1437 = `/usr/libexec/textunderstandingd` (the Apple Intelligence text-understanding daemon). A client that fails WindowServer pings is consistent with a window left in a bad/zombie state that forces repeated constraint re-evaluation. This attribution is inferred from the co-occurring ping timeout only and should be treated as a lead, not a fact — the constraint error itself is unattributed.

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

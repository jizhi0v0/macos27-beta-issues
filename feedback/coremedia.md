VERIFICATION: CONFIRMED — 1192 lines/60s of fpSupport_GetVideoRangeForCoreDisplayWithPreference (all externalPanel=YES, internal-only Mac), captured 2026-06-26 10:32 +0800, uptime 39 min, beta2 26A5368g.

# Title
CoreMedia/MediaToolbox logs fpSupport_GetVideoRangeForCoreDisplayWithPreference at default level in a tight per-process loop, flooding logd; reports externalPanel=YES on an internal-only Mac

# Apple area / component to select
Media / CoreMedia (MediaToolbox). Sub-area: logging / unified log spam.

# Description
On macOS 27.0 (26A5368g), MediaToolbox repeatedly emits the log line
`<<<< Alt >>>> fpSupport_GetVideoRangeForCoreDisplayWithPreference: displayID 1 reported potentialHeadRoom=16 wideColorSupported=YES marz=NO almd=NO deviceAllowsHDR=YES isBuiltinPanel=YES externalPanel=YES prefersHDR10=NO`
many times per second, once per client process that touches the WebKit/CoreMedia display-capability path. It is logged at *default* level, so logd persists every line to disk.

Two problems:
1. The query runs in a tight loop (~4–8 lines/sec per process, multiple processes simultaneously) well past boot, not as a one-time capability probe.
2. The reported parameters are wrong: `externalPanel=YES` on a MacBook Pro with only the internal Liquid Retina XDR display and no external monitor attached. `isBuiltinPanel=YES` and `externalPanel=YES` are both set, which is contradictory.

Measured at uptime 39 min, `log show --last 60s` returned 1192 occurrences:
- WeType (input method) 480/60s (~8/s)
- DingTalk (Electron) 472/60s (~8/s)
- Bob (WebKit translator) 240/60s (~4/s)
All 1192 lines carried `externalPanel=YES`.

# Steps to Reproduce
1. Boot a Mac15,11 (or any internal-display-only Mac) into macOS 27.0 26A5368g.
2. Launch a few WebKit/Electron apps that query display HDR/color capability (an input method, an Electron chat app, a WebKit-based translator).
3. Run: `log show --last 60s --predicate 'eventMessage CONTAINS "fpSupport_GetVideoRangeForCoreDisplay"'`
4. Observe hundreds-to-thousands of default-level lines, several per second per process.

# Expected vs Actual
- Expected: the display video-range capability is queried once (or cached), logged at debug level (not persisted), and reports correct panel topology (`externalPanel=NO` when no external display is attached).
- Actual: queried in a per-process loop several times/sec, logged at default level (persisted to disk by logd), and reports `externalPanel=YES` on an internal-only machine.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.0 26A5368g
- Single internal Liquid Retina XDR display, no external monitor, no mirroring

# Suggested attachments
- sysdiagnose taken during the flood
- `log collect --last 5m` archive
- Saved output of the `log show --last 60s` predicate above showing the per-process line counts and the externalPanel=YES parameter

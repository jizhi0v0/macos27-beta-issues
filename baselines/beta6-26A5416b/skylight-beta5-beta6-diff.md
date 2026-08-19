# SkyLight / QuartzCore, beta5 `26A5406e` ↔ beta6 `26A5416b`

Run 2026-08-19 to answer one question for [#3](https://github.com/jizhi0v0/macos27-beta-issues/issues/3):
**did the code that is burning the CPU change between the two builds?**

## Answer: no. The hot path is byte-identical.

## Method

Neither framework exists as a file on disk — both live only in the dyld shared cache. Both sides
were extracted with the **same** tool, so no extraction-flavour difference can leak into the
comparison (the trap that limited [#17](https://github.com/jizhi0v0/macos27-beta-issues/issues/17)'s
diff to a Rosetta build):

- beta5 cache: `~/Developer/macos27-beta5-binary-archive/dyld_shared_cache/` — the copy taken
  the day before the upgrade. Without it this comparison would have been impossible.
- beta6 cache: the live `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/`.
- Extractor: `dsc_extractor.bundle` from Xcode-beta, driven by a 20-line C program
  (`~/Developer/ws-diff/extract.c`). 4,083 dylibs per side, `result=0` both times.
- Comparison: `~/Developer/ws-diff/fdiff.py` — per-function disassembly via `llvm-objdump`,
  normalised (address column, raw bytes, absolute operands and **`adrp` symbol annotations**
  stripped), then diffed.

**Normalisation matters.** Before `adrp` annotations were stripped, `update_display_callback`
showed "14 changed instructions" — every one of them was llvm-objdump naming a data page after
the *nearest* symbol, which renames when unrelated data shifts. All 14 vanished under correct
normalisation. A naive diff here produces confident nonsense.

## Result 1 — the hot path from the spindump is unchanged

| function | beta5 | beta6 | |
|---|---|---|---|
| `non_coalesced_timer_handler` | 0x28 / 10 insns | 0x28 / 10 | identical |
| `run_timer_pass` | 0x2d0 / 180 | 0x2d0 / 180 | identical |
| `update_display_callback` | 0x17a4 / 1513 | 0x17a4 / 1513 | identical |
| `CGXUpdateDisplay` | 0x9c / 39 | 0x9c / 39 | identical |
| `WS::Updater::UpdateDisplays` | 0x77bc / 7663 | 0x77bc / 7663 | identical |
| `WS::Updater::prepare_coreanimation` | 0x2f2c / 3019 | 0x2f2c / 3019 | identical |
| `WS::Updater::defenestrator3::ca_prepare_begin_window_update` | 0xcc8 / 818 | 0xcc8 / 818 | identical |
| QuartzCore `CA::Render::Updater::prepare_layer` | 0xa9bc / 10863 | 0xa9bc / 10863 | identical |
| QuartzCore `CA::Render::Update::add_context` | 0x3764 / 3545 | 0x3764 / 3545 | identical |
| QuartzCore `CA::OGL::render_layers` | 0x77c / 479 | 0x77c / 479 | identical |

Not a sample: **all 156** SkyLight functions matching the updater/display/timer area were
disassembled and compared — **156 identical, 0 different.**

The `update_display_callback` throttle statics (`backoffPeriod`, `lastEvaluatedTime`,
`timeInUpdaterSinceLastEvaluation`, `updatePendingAfterBackoff`, `lastUpdateEndedTime`,
`previousSequenceNumber`) exist identically in both builds — the backoff machinery is not new
and was not removed.

## Result 2 — what beta6 *did* change in SkyLight

SkyLight grew 9,494,528 → 9,498,624 bytes (+4096, one page). Only **9** functions changed size,
and they are all in the same area — structural regions, CA context regions, event routing:

| Δ | function |
|---|---|
| +196 | `__XWindowRoutingRecordsForScreenLocation` (the mach-message hit-test entry point) |
| +68 | `(anonymous)::ca_context_region::attach()` |
| −8 | `_WSDumpRemoteRegions_block_invoke_2` |
| +4 ×6 | `WSCAContextRegionForID`, `WSCAWindowRegionForWindowCreatingIfNecessary`, `WSCASurfaceRegionForSurfaceCreatingIfNecessary`, `WSRemoteRegionForID`, `WSConnectionForRemoteRegionContextID`, `WSRemoveCAContextRegionByID` |

Symbols added in beta6:

- `structural_region::unobscured_event_location_matches(CGPoint, bool)` — **new**
- `structural_region_container::event_at_location_matches_apply_until(...)` — **new**
  (beta5 had only `event_location_matches_apply_until`)
- `weak_map_find_and_lock<unsigned, ca_context_region>` — **new**

Removed in beta5→beta6: `WSSessionStructuralRegionData::region_for_context_id(unsigned)`.

Inside `attach()`, beta5's **inlined open-addressed hash lookup** (the `udiv`/`msub`/`csel`
modulo-bucket sequence libc++ emits for `unordered_map::find`) is replaced by the new
`weak_map_find_and_lock`. Shape of a lifetime/locking fix, not a change to tree structure.

## What this means for #3

**It falsifies "beta6 regressed the compositor."** The code doing the work is the same code that
ran at ~4 % on beta5. Whatever changed is not in these instructions.

Two explanations survive, and this diff does not choose between them:

1. **The regression predates beta6.** Consistent with the 2026-08-18 reading — still beta5 —
   of a 37.4 % lifetime average. The quiesced beta5 re-test that would have settled this was
   scheduled and never run before the upgrade; that number is now unobtainable.
2. **beta6 changed the *state* the unchanged code walks.** The one changed area — structural
   regions and CA context regions — is exactly what the external report in
   [#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22) blamed
   ("structural-region state accumulation"). But the changed functions are on the **event
   hit-test** path, not the display-update path, so there is no demonstrated mechanism connecting
   them to the CPU. **A lead, not a finding.**

## Limits, stated

- Result 2's "only 9 changed" is **size-based** across all 14,918 common text symbols. A function
  can change without changing size; outside the 156 exhaustively compared, that is not excluded.
- Both sides are cache-extracted images, not the on-disk originals — fair against each other,
  but a shared systematic offset cannot be ruled out.
- 17 symbols exist only in beta5 and 31 only in beta6; the rest are `GCC_except_table`
  renumbering, the expected signature of code shifting.

## Next

The obvious experiment no longer needs a disassembler: since the compositing code is unchanged,
**find the state**. The spindump does not name the `CGXWindow*` owning the 40+-deep layer tree.
Enumerating the on-screen layer/region tree while WindowServer is at 46 % — and checking whether
it drains on `killall MenuBarAgent` the way #22 reports — tests both surviving explanations
directly.

#!/bin/bash
# Continuous watcher for the corebrightnessd `nan` oscillation
# (issues/apple-corebrightness-nan-oscillation.md, GitHub #25).
#
# WHY: the original "roughly once every 30 minutes" claim came from spot checks
# and was WRONG by a wide margin -- an ad-hoc 9 h 17 m watcher on beta5
# 26A5406e found nan lines in 75 of 104 windows (72%), 37,088 lines total,
# peaking at 4,609 in a single 5-minute window. That watcher was never
# committed, so the numbers in the issue file cannot currently be re-derived.
# This is that watcher, made rerunnable, so beta6 can be A/B'd against beta5.
#
# WHAT IT FIXES vs the ad-hoc version:
#   - windows TILE exactly (each --start is the previous --end) instead of
#     "roughly every 5 minutes", so a rate is well defined and nothing is
#     double-counted or missed while a probe is running;
#   - it rewrites summary.txt after every window, so intermediate results can
#     be read at any time without stopping the run;
#   - it records the covariates that decide how the numbers are read:
#     Auto-Brightness state, cumulative corebrightnessd CPU, and the peak
#     per-second rate inside each window (the issue documents ~116 lines/s
#     bursts -- an average over 5 minutes hides those);
#   - it gzips every window's raw log AS IT IS TAKEN, because these lines are
#     evicted from the in-memory ring buffer within tens of minutes (see the
#     comment at the archive step) -- without this, any window that turns out
#     to be interesting can no longer be examined.
#
# USAGE:
#   bash tools/corebrightness-nan-watch.sh              # runs until Ctrl-C
#   POLL=300 HOURS=9 bash tools/corebrightness-nan-watch.sh
#   nohup bash tools/corebrightness-nan-watch.sh >/tmp/cb-nan.log 2>&1 &
#
# Results: /tmp/cb-nan-watch/<timestamp>/{windows.csv,summary.txt,first-hit.txt}
# No sudo needed.
#
# TWO TRAPS THIS AVOIDS (both fail SILENTLY -- they return a plausible small
# number rather than an error, see the methodology notes in the issue files):
#   - `log` is a zsh builtin; a bare `log show` through a pipe returns nothing,
#     which reads exactly like "no nan". Always /usr/bin/log.
#   - `--info --debug` is REQUIRED: these lines are emitted below the default
#     level, so without it the count silently undercounts.
# macOS also has no timeout(1), so this polls with bounded `log show`, never
# `log stream`.

set -u

POLL=${POLL:-300}                  # window length in seconds (also the cadence)
HOURS=${HOURS:-0}                  # 0 = run until Ctrl-C
OUTROOT=${OUTROOT:-/tmp/cb-nan-watch}
LOG=/usr/bin/log                   # never the zsh builtin

# TWO STREAMS, AND THE SECOND ONE IS THE ISSUE'S ACTUAL EVIDENCE.
# The first version of this watcher only followed corebrightnessd, and that led
# straight to a wrong conclusion: corebrightnessd's own lines carry a valid
# `lux=464.21`, so "the issue's `ambient lux: nan` does not reproduce on beta5"
# looked true. It is not -- the all-NaN brightness state the issue is built on
# is logged by WINDOWSERVER under (QuartzCore) [com.apple.coreanimation:
# Brightness], a stream the corebrightnessd predicate never sees. Measured on
# 26A5406e over 30 min: 24,809 WindowServer Brightness lines, 23,843 with nan,
# 11,761 with `ambient lux: nan`. Always follow both.
PRED_CB='process == "corebrightnessd"'
PRED_WS='process == "WindowServer" AND category == "Brightness"'

DIR="$OUTROOT/$(date +%Y-%m-%d-%H%M%S)"
RAWDIR="$DIR/raw"
mkdir -p "$RAWDIR"
CSV="$DIR/windows.csv"
SUM="$DIR/summary.txt"
echo "window_start,window_end,secs,cb_lines,cb_nan,cb_peak,ws_lines,ws_nan,ws_luxnan,ws_peak" > "$CSV"

secs() { awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}'; }
cb_cpu() {  # cumulative utime+stime of corebrightnessd, in seconds
  ps -Ao utime=,stime=,comm= 2>/dev/null \
    | awk '$3 ~ /corebrightnessd$/ {print $1"\n"$2}' | secs \
    | awk '{t+=$1} END {printf "%.0f", t+0}'
}
lux_state() {
  # Auto-Brightness has no machine-readable switch here (com.apple.CoreBrightness
  # and com.apple.BezelServices both report "Domain not found" on 26A5406e), so
  # record the covariate that actually matters instead: whether the ambient-light
  # input itself is valid. The issue's beta4 capture had `ambient lux: nan` while
  # Auto-Brightness was ON -- the feature running on garbage input. Read it from
  # the WindowServer stream, which is where that field lives.
  $LOG show --last 60s --info --debug --predicate "$PRED_WS" --style syslog 2>/dev/null \
    | grep -o 'ambient lux: [^,]*' | sort | uniq -c | sort -rn | head -3 \
    | sed 's/^/    /' || true
  echo "    (record the Auto-Brightness checkbox by hand: System Settings > Displays)"
  echo "    backlight hardware for comparison (the issue's control -- panel values were sane):"
  ioreg -c AppleARMBacklight -r 2>/dev/null \
    | grep -oE '"(BrightnessMilliNits|rawBrightness)" = [0-9]+' | head -2 | sed 's/^/      /'
}

T_START=$(date "+%Y-%m-%d %H:%M:%S")
CPU0=$(cb_cpu)
{
  echo "=== corebrightnessd nan watcher ==="
  echo "build:  $(sw_vers -productVersion) $(sw_vers -buildVersion)"
  echo "model:  $(sysctl -n hw.model)"
  echo "start:  $T_START   window=${POLL}s   limit=${HOURS}h (0 = until Ctrl-C)"
  echo "predicate: $PRED   (--info --debug)"
  echo "ambient-light input at start (is lux itself nan?):"
  lux_state
  echo
} | tee "$SUM"

WINDOWS=0; HITS=0; TOTAL_NAN=0; MAX_NAN=0; MAX_AT=""; MAX_PEAK=0
WHITS=0; LUXHITS=0; TOTAL_WNAN=0; TOTAL_WLUX=0; MAX_WPEAK=0
PREV_END=$(date "+%Y-%m-%d %H:%M:%S")
T0=$(date +%s)

summarize() {
  local now cpu1 elapsed
  now=$(date "+%Y-%m-%d %H:%M:%S"); cpu1=$(cb_cpu); elapsed=$(( $(date +%s) - T0 ))
  {
    echo "=== corebrightnessd nan watcher ==="
    echo "build:  $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "model:  $(sysctl -n hw.model)"
    echo "start:  $T_START"
    echo "now:    $now   (elapsed $((elapsed/3600))h $(((elapsed%3600)/60))m)"
    echo "window: ${POLL}s, tiled (each start = previous end)"
    echo
    echo "windows sampled : $WINDOWS"
    echo
    echo "-- WindowServer (QuartzCore) Brightness -- the stream the issue is built on --"
    echo "windows with nan     : $WHITS $(awk -v h="$WHITS" -v w="$WINDOWS" 'BEGIN{if(w>0) printf "(%.0f%%)", h/w*100}')"
    echo "windows with lux=nan : $LUXHITS $(awk -v h="$LUXHITS" -v w="$WINDOWS" 'BEGIN{if(w>0) printf "(%.0f%%)", h/w*100}')"
    echo "total nan lines      : $TOTAL_WNAN"
    echo "  of which lux=nan   : $TOTAL_WLUX"
    echo "peak burst rate      : $MAX_WPEAK nan lines/s within a window"
    echo
    echo "-- corebrightnessd -- mostly the brightness RAMP (see below) --"
    echo "windows with nan: $HITS $(awk -v h="$HITS" -v w="$WINDOWS" 'BEGIN{if(w>0) printf "(%.0f%%)", h/w*100}')"
    echo "total nan lines : $TOTAL_NAN"
    echo "worst window    : $MAX_NAN lines  ($MAX_AT)"
    echo "peak burst rate : $MAX_PEAK nan lines/s within a window"
    awk -v a="$CPU0" -v b="$cpu1" -v e="$elapsed" \
      'BEGIN{if(e>0) printf "corebrightnessd CPU: %.2f%% cumulative over the run\n", (b-a)/e*100}'
    echo
    echo "per-window detail: $CSV"
    echo "raw windows (gzip): $RAWDIR   -- gzcat one to drill into a window"
    echo "HOW TO READ:"
    echo "  - The WindowServer block is the defect: NaN brightness state, including"
    echo "    'ambient lux: nan' while Auto-Brightness is on. A high windows-with-nan"
    echo "    share means any short spot check has that chance of catching it, which"
    echo "    is what made the original 'once every 30 min' estimate wrong."
    echo "  - The corebrightnessd 1/0 churn is NOT that defect: measured 2026-08-13,"
    echo "    it is a brightness ramp -- an AggregatedLux change inserts an SDR_RAMP"
    echo "    and the key updates once per frame (120/s at 120 Hz) until 'Finished"
    echo "    ramps' removes it 5.0 s later. Bounded, explained, ~0.3% CPU."
  } > "$SUM"
}
# The sleep runs as a background child that we `wait` on, so a TERM to this
# process is handled immediately. With a plain foreground `sleep`, bash defers
# the trap until the sleep returns, so `kill` on a nohup'd run appeared to do
# nothing for up to POLL seconds (observed: had to pkill -P the child).
SLEEP_PID=""
trap 'kill $SLEEP_PID 2>/dev/null; summarize; echo; echo "stopped -- summary: $SUM"; exit 0' INT TERM

echo "watching corebrightnessd: ${POLL}s tiled windows. Summary rewritten each window: $SUM"

while :; do
  sleep "$POLL" & SLEEP_PID=$!
  wait $SLEEP_PID 2>/dev/null
  END=$(date "+%Y-%m-%d %H:%M:%S")
  RAW=$($LOG show --start "$PREV_END" --end "$END" --info --debug \
          --predicate "$PRED_CB" --style syslog 2>/dev/null)
  WRAW=$($LOG show --start "$PREV_END" --end "$END" --info --debug \
          --predicate "$PRED_WS" --style syslog 2>/dev/null)
  TOT=$(printf '%s\n' "$RAW" | grep -c '^2026' || true)
  NAN=$(printf '%s\n' "$RAW" | grep -c 'nan' || true)
  WTOT=$(printf '%s\n' "$WRAW" | grep -c '^2026' || true)
  WNAN=$(printf '%s\n' "$WRAW" | grep -c 'nan' || true)
  WLUX=$(printf '%s\n' "$WRAW" | grep -c 'ambient lux: nan' || true)
  # peak per-second rate inside the window -- the 5-minute average hides bursts
  PEAK=$(printf '%s\n' "$RAW" | grep 'nan' | awk '{print $2}' | cut -d. -f1 \
           | uniq -c | awk 'BEGIN{m=0} {if($1>m) m=$1} END{print m+0}')
  WPEAK=$(printf '%s\n' "$WRAW" | grep 'nan' | awk '{print $2}' | cut -d. -f1 \
           | uniq -c | awk 'BEGIN{m=0} {if($1>m) m=$1} END{print m+0}')

  WINDOWS=$((WINDOWS+1)); TOTAL_NAN=$((TOTAL_NAN+NAN))
  TOTAL_WNAN=$((TOTAL_WNAN+WNAN)); TOTAL_WLUX=$((TOTAL_WLUX+WLUX))
  [ "$NAN" -gt 0 ] && HITS=$((HITS+1))
  [ "$WNAN" -gt 0 ] && WHITS=$((WHITS+1))
  [ "$WLUX" -gt 0 ] && LUXHITS=$((LUXHITS+1))
  if [ "$NAN" -gt "$MAX_NAN" ]; then MAX_NAN=$NAN; MAX_AT="$PREV_END -> $END"; fi
  [ "$PEAK" -gt "$MAX_PEAK" ] && MAX_PEAK=$PEAK
  [ "$WPEAK" -gt "$MAX_WPEAK" ] && MAX_WPEAK=$WPEAK

  echo "$PREV_END,$END,$POLL,$TOT,$NAN,$PEAK,$WTOT,$WNAN,$WLUX,$WPEAK" >> "$CSV"
  printf '[%s] w%-3s  cbd %-5s/nan %-5s  |  WS %-6s/nan %-6s luxnan %-6s peak %s/s\n' \
    "$(date '+%H:%M:%S')" "$WINDOWS" "$TOT" "$NAN" "$WTOT" "$WNAN" "$WLUX" "$WPEAK"

  # keep one raw sample as evidence the count is real, not a grep artefact
  if [ "$NAN" -gt 0 ] && [ ! -f "$DIR/first-hit.txt" ]; then
    { echo "=== first window with nan: $PREV_END -> $END ==="
      printf '%s\n' "$RAW" | grep 'nan' | head -40; } > "$DIR/first-hit.txt"
  fi

  # ARCHIVE EVERY WINDOW NOW -- this evidence is perishable. Measured 2026-08-13
  # on 26A5406e: a window recorded live as 2,357 lines / 1,031 nan re-queried 40
  # minutes later returned 240 lines / 0 nan, because --info --debug messages
  # live in an in-memory ring buffer and are evicted oldest-first. A newer
  # window from the same run still had 1,386 of 1,437. So any window that turns
  # out to be interesting is usually un-analysable by the time you notice, and
  # `log show` will tell you so by returning a plausible smaller number rather
  # than an error. ~50 KB gzipped per 5-minute window (~5 MB per 9 h run).
  STAMP=$(echo "$PREV_END" | tr ' :' '-')
  printf '%s\n' "$RAW"  | gzip > "$RAWDIR/$STAMP.corebrightnessd.txt.gz"
  printf '%s\n' "$WRAW" | gzip > "$RAWDIR/$STAMP.windowserver.txt.gz"

  PREV_END=$END
  summarize
  if [ "$HOURS" != "0" ]; then
    awk -v e="$(( $(date +%s) - T0 ))" -v h="$HOURS" 'BEGIN{exit !(e >= h*3600)}' && break
  fi
done

summarize
echo "done -- summary: $SUM"

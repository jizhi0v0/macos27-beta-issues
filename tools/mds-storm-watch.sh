#!/bin/bash
# Catch the mds CoreDuet activity storm live.
#
# The storm in issues/apple-mds-coreduet-activity-storm.md is INTERMITTENT:
# 145,241 mds lines/60s when it fires, ~132/60s when it doesn't, and querying
# the archive shows it is NOT predicted by uptime-since-boot (see the post-boot
# table in that file — 0 lines at +4min/+30min/+1h/+3h/+6h of one boot). A
# one-shot `log show` is therefore a lottery. This polls cheaply and takes a
# full evidence snapshot only when the rate crosses a threshold.
#
# USAGE:
#   bash tools/mds-storm-watch.sh            # watch until it fires, then stop
#   bash tools/mds-storm-watch.sh -k         # keep watching (snapshot each burst)
#   POLL=30 THRESHOLD=200 bash tools/mds-storm-watch.sh
#
# Leave it running in a Terminal tab (or `nohup ... &`). Snapshots land in
#   /tmp/mds-storm/<timestamp>/
# Nothing here needs sudo; a couple of extras are skipped without it.
#
# Two traps this script exists to avoid (both fail SILENTLY, see the
# methodology notes in the issue files):
#   - `log` is a zsh builtin. Bare `log show` through a pipe returns nothing,
#     which reads exactly like "no storm". Always /usr/bin/log.
#   - macOS has no timeout(1), so `timeout N log stream ...` yields 0 lines.
#     This script polls with bounded `log show --last`, never `log stream`.

set -u

POLL=${POLL:-60}            # seconds between probes
PROBE=${PROBE:-10}          # length of each cheap probe window
THRESHOLD=${THRESHOLD:-300} # CoreDuet lines/sec that counts as "storming"
                            # (idle ~2/s; storm ~2,420/s — 300 is far above noise)
WINDOW=${WINDOW:-60}        # full-capture window once triggered
OUTROOT=${OUTROOT:-/tmp/mds-storm}
KEEP=0
[ "${1:-}" = "-k" ] && KEEP=1

LOG=/usr/bin/log            # never the zsh builtin
secs() { awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}'; }

# cumulative utime+stime for a process name, in seconds — immune to the
# decaying average that `ps %cpu` reports
cpu_cum() {
  ps -Ao utime=,stime=,comm= 2>/dev/null \
    | awk -v n="$1" '$3 ~ n {print $1"\n"$2}' | secs \
    | awk '{t+=$1} END {printf "%.0f", t+0}'
}

probe() { # -> CoreDuet lines seen in the last $PROBE seconds
  # --info --debug is REQUIRED. Verified 2026-08-11 on one 60 s window:
  # without it this command counted 1,451 CoreDuet lines, with it 3,032 — a
  # ~52% undercount, because those lines are emitted below default level.
  # The consequence was a threshold that silently needed ~2x the real traffic
  # to trip. Same family of trap as `log` being a zsh builtin: it fails by
  # returning a plausible small number, not an error.
  $LOG show --last "${PROBE}s" --info --debug --predicate 'process == "mds"' --style syslog 2>/dev/null \
    | grep -c 'CoreDuet' || true
}

snapshot() {
  local rate=$1
  local dir="$OUTROOT/$(date +%Y-%m-%d-%H%M%S)"
  mkdir -p "$dir"
  echo "[$(date '+%H:%M:%S')] STORM: ${rate}/s >= ${THRESHOLD}/s — capturing ${WINDOW}s into $dir"

  # --- state BEFORE the window (cumulative CPU baseline) ---
  local mds0 sto0 ctx0 t0
  mds0=$(cpu_cum '/mds$'); sto0=$(cpu_cum 'mds_stores$'); ctx0=$(cpu_cum 'contextstored$')
  t0=$(date +%s)

  {
    echo "=== mds storm snapshot ==="
    echo "when:   $(date)"
    echo "build:  $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "boot:   $(sysctl -n kern.boottime)"
    echo "uptime: $(uptime)"
    echo "trigger: ${rate} CoreDuet lines/sec over a ${PROBE}s probe"
    echo
    echo "=== indexing state at trigger time (mdutil -as) ==="
    mdutil -as 2>&1
    echo
    echo "=== Spotlight processes (cumulative TIME is the number that matters) ==="
    ps -Ao pid,%cpu,time,comm | grep -E 'Metadata\.framework|contextstored' | grep -v grep
    echo
    echo "=== mdworker_shared instances alive ==="
    pgrep -c mdworker_shared 2>/dev/null || echo 0
    echo
    echo "=== Spotlight store sizes (skipped without sudo) ==="
    sudo -n du -sh /System/Volumes/Data/.Spotlight-V100/Store-V2/* 2>/dev/null \
      || echo "(no passwordless sudo — rerun the du by hand if needed)"
  } > "$dir/state-before.txt" 2>&1

  # --- the window itself: let it elapse, then take the last WINDOW seconds ---
  sleep "$WINDOW"
  $LOG show --last "${WINDOW}s" --style syslog > "$dir/log${WINDOW}.txt" 2>/dev/null

  local mds1 sto1 ctx1 t1 elapsed
  mds1=$(cpu_cum '/mds$'); sto1=$(cpu_cum 'mds_stores$'); ctx1=$(cpu_cum 'contextstored$')
  t1=$(date +%s); elapsed=$((t1 - t0))

  # --- analysis ---
  local L="$dir/log${WINDOW}.txt" total mdsl duet ctxl spawns
  total=$(grep -c '^2026' "$L" || true)
  mdsl=$(grep -cE ' mds\[[0-9]+\]' "$L" || true)
  # scope to mds's own lines — other processes emit CoreDuet messages too, and
  # an unscoped count can exceed the mds total and read as nonsense
  duet=$(grep -E ' mds\[[0-9]+\]' "$L" | grep -c 'CoreDuet: ClientContext objectForContextualKeyPath' || true)
  ctxl=$(grep -cE ' contextstored\[[0-9]+\]' "$L" || true)
  spawns=$(grep -c 'com\.apple\.mdworker\.shared' "$L" || true)

  {
    echo "=== analysis (${WINDOW}s window, ${elapsed}s wall) ==="
    echo "total timestamped log lines : $total"
    echo "mds lines                   : $mdsl"
    echo "  of which CoreDuet activity: $duet"
    echo "contextstored lines         : $ctxl"
    echo "mdworker.shared spawns      : $spawns"
    [ "$total" -gt 0 ] && awk -v m="$mdsl" -v t="$total" \
      'BEGIN{printf "mds share of all log volume : %.1f%%\n", m/t*100}'
    echo
    echo "=== CPU over the window (cumulative delta — NOT ps %cpu) ==="
    awk -v a="$mds0" -v b="$mds1" -v e="$elapsed" 'BEGIN{printf "mds           : %.1f%% of one core\n",(b-a)/e*100}'
    awk -v a="$sto0" -v b="$sto1" -v e="$elapsed" 'BEGIN{printf "mds_stores    : %.1f%%\n",(b-a)/e*100}'
    awk -v a="$ctx0" -v b="$ctx1" -v e="$elapsed" 'BEGIN{printf "contextstored : %.1f%%\n",(b-a)/e*100}'
    echo
    echo "=== top log emitters in the window ==="
    awk '{for(i=1;i<=NF;i++) if($i ~ /\[[0-9]+\]/){print $i; break}}' "$L" \
      | sed 's/\[[0-9]*\]//' | sort | uniq -c | sort -rn | head -12
    echo
    echo "=== per-second mds rate (is it continuous or bursty?) ==="
    grep -E ' mds\[[0-9]+\]' "$L" | awk '{print $2}' | cut -d. -f1 \
      | uniq -c | awk '{printf "  %s  %s/s\n",$2,$1}'
    echo
    echo "=== indexing state AFTER the window ==="
    mdutil -as 2>&1
    ps -Ao pid,%cpu,time,comm | grep -E 'Metadata\.framework|contextstored' | grep -v grep
  } > "$dir/analysis.txt" 2>&1

  echo "[$(date '+%H:%M:%S')] captured -> $dir"
  echo "  read:  $dir/analysis.txt"
  sed -n '1,12p' "$dir/analysis.txt"
}

echo "watching mds: probe ${PROBE}s every ${POLL}s, trigger at >= ${THRESHOLD} CoreDuet lines/sec"
echo "(idle is ~2/s, the storm was ~2,420/s. Ctrl-C to stop.)"
mkdir -p "$OUTROOT"

while :; do
  n=$(probe)
  rate=$(( n / PROBE ))
  if [ "$rate" -ge "$THRESHOLD" ]; then
    snapshot "$rate"
    [ "$KEEP" -eq 1 ] || { echo "done — rerun with -k to keep watching"; exit 0; }
    sleep 300   # cooldown so one long storm doesn't fill the disk
  else
    printf '[%s] %s/s\n' "$(date '+%H:%M:%S')" "$rate"
  fi
  sleep "$POLL"
done

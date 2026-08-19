#!/bin/bash
# Replicated ecosystemd measurement for issues/apple-ecosystemd-trust-retry-loop.md (#23).
#
# WHY THIS EXISTS: the beta5 spot-check produced 12.2% and then ~4.7% for the
# same daemon within twenty minutes, both taken while the machine was heavily
# loaded. Neither is decision-grade. This runs N windows back-to-back in one
# state and reports the spread, the same way tools/ws-replicate.sh does for
# WindowServer.
#
# Two traps this avoids, both of which fail SILENTLY:
#   - `ps %cpu` is a decaying average and reported 0.0% for a daemon that was
#     provably burning 12% at the time. Only cumulative utime+stime deltas count.
#   - `log` is a zsh builtin; a bare `log show` through a pipe returns nothing,
#     which reads exactly like "the loop stopped". Always /usr/bin/log.
#
# USAGE (Terminal, after quitting your apps):
#   bash tools/eco-replicate.sh
#   REPS=3 WIN=45 bash tools/eco-replicate.sh
#
# Unlike the WindowServer scripts this does NOT need the screen awake — the
# loop is not compositing work — but leaving the machine otherwise idle keeps
# the CPU numbers comparable across runs.

set -u
REPS=${REPS:-5}
WIN=${WIN:-60}
LEAD=${LEAD:-30}
OUT=/tmp/eco_replicate.txt

secs() { awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else if(NF==2) print $1*60+$2; else print $1}'; }
cpu_of() { ps -o utime=,stime= -p "$1" 2>/dev/null | awk '{print $1" "$2}'; }
delta_pct() {
  local bu bs au as
  bu=$(echo "$1" | awk '{print $1}' | secs); bs=$(echo "$1" | awk '{print $2}' | secs)
  au=$(echo "$2" | awk '{print $1}' | secs); as=$(echo "$2" | awk '{print $2}' | secs)
  echo "$au $bu $as $bs $3" | awk '{printf "%.1f", (($1-$2)+($3-$4))/$5*100}'
}

PID=$(pgrep -x ecosystemd | head -1)
if [ -z "$PID" ]; then echo "ecosystemd is not running"; exit 1; fi

{
  echo "=== replicated ecosystemd measurement ==="
  echo "build: $(sw_vers -productVersion) $(sw_vers -buildVersion)"
  echo "reps=$REPS window=${WIN}s  pid=$PID"
  echo "start: $(date)"
  echo
  echo "baseline for comparison — beta4 26A5388g:"
  echo "  SecTrustCopyAppleTrustAnchors ~68-85/s | 15,885 lines/60s | 1,227 EIO | CPU 26-57%"
  echo
} > "$OUT"

echo "lead-in ${LEAD}s — quit your apps now, then leave the machine alone."
sleep "$LEAD"

{
  echo "--- all running /Applications bundles at measurement start ---"
  ps -Ao comm= | grep "^/Applications" | sed 's|/Contents/.*||; s|.*/||' | sort -u | tr '\n' ' '
  echo; echo
  printf "%-4s %8s %10s %12s %8s\n" "rep" "eco%" "anchors/s" "lines/win" "EIO"
} >> "$OUT"

vals=()
for i in $(seq 1 "$REPS"); do
  b=$(cpu_of "$PID"); t0=$(date +%s); WSTART=$(date '+%Y-%m-%d %H:%M:%S')
  sleep "$WIN"
  a=$(cpu_of "$PID"); t1=$(date +%s); el=$((t1-t0)); WEND=$(date '+%Y-%m-%d %H:%M:%S')
  pct=$(delta_pct "$b" "$a" "$el")

  # Look back over the window we just measured. Not `log stream` — macOS has
  # no timeout(1), so a bounded stream is not possible without hanging.
  #
  # FIXED 2026-08-19. The defect recorded here on 2026-08-11 was real: across a
  # 5-rep run these three columns came back byte-identical in 4 of 5 reps
  # (7519 lines / 468 EIO), impossible for independent 60 s windows on a process
  # emitting ~125 lines/s. The guess in that note was right -- `--last Ns`
  # resolves against the log buffer's flush boundary, so back-to-back queries
  # land on the same flushed extent. Pinning the window with explicit --start
  # and --end fixes it: three such windows measured 2050 / 1950 / 2087 anchors
  # and 492 / 468 / 501 EIO, i.e. they vary as independent samples should.
  # The eco% column was never affected -- it comes from ps utime+stime deltas.
  L=$(/usr/bin/log show --start "$WSTART" --end "$WEND" --info --debug --predicate 'process == "ecosystemd"' 2>/dev/null)
  lines=$(printf '%s' "$L" | grep -c '')
  anch=$(printf '%s' "$L" | grep -c 'SecTrustCopyAppleTrustAnchors')
  eio=$(printf '%s' "$L" | grep -c 'UNIX error exception: 5')
  printf "%-4s %8s %10s %12s %8s\n" "$i" "$pct" "$(echo "$anch $WIN" | awk '{printf "%.1f", $1/$2}')" "$lines" "$eio" >> "$OUT"
  vals+=("$pct")
done

{
  echo
  printf '%s\n' "${vals[@]}" | awk '
    {v[NR]=$1; s+=$1; if(NR==1||$1<mn)mn=$1; if(NR==1||$1>mx)mx=$1}
    END{m=s/NR; for(i=1;i<=NR;i++) d+=(v[i]-m)^2;
        printf "ecosystemd CPU: mean=%.1f%%  min=%.1f%%  max=%.1f%%  sd=%.1f\n", m, mn, mx, sqrt(d/NR)}'
  echo
  echo "HOW TO READ:"
  echo "  The loop is confirmed still present by the anchors/s and EIO columns"
  echo "  regardless of CPU — those are not load-sensitive. CPU is the open"
  echo "  question: beta4 recorded 26-57%, and beta5 spot-checks disagreed with"
  echo "  each other (12.2% then 4.7%) under heavy load."
  echo "  A tight spread here settles it; a wide one means the state is still"
  echo "  uncontrolled and something else is varying."
  echo "done: $(date)"
} >> "$OUT"

cat "$OUT"

#!/bin/bash
# Replicated WindowServer measurement.
#
# WHY: single-shot measurements of "idle" desktops ranged 22.5%-81% and were not
# decision-grade -- the state was never as controlled as it looked (a hidden
# menu-bar app still animating; a 60 Hz vs 120 Hz refresh-rate difference).
# This runs N windows back-to-back in ONE state and reports the spread, and
# records the covariates that turned out to matter: refresh rate, the full list
# of on-screen window owners, and Spotlight load.
#
# It produced the decisive figures for issues/apple-windowserver-invalid-window.md:
#   120 Hz -> mean 45.9%, sd 0.9    60 Hz -> mean 42.0%, sd 3.6
# i.e. the idle floor is INDEPENDENT of refresh rate, so it is not per-frame
# compositing cost. It also falsified a single-reading claim to the contrary --
# which is exactly why this script exists: replicate before concluding.
#
# USAGE (Terminal):
#   bash tools/ws-replicate.sh          # 5 x 60s  (~6 min incl. lead-in)
#   REPS=3 WIN=45 bash tools/ws-replicate.sh
#
# Quit apps during the lead-in, then leave the machine alone until it prints DONE.

REPS=${REPS:-5}
WIN=${WIN:-60}
LEAD=${LEAD:-40}
OUT=/tmp/ws_replicate.txt

secs() { awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}'; }
cpu_of() { ps -o utime=,stime= -p "$1" 2>/dev/null | awk '{print $1" "$2}'; }
# aggregate cumulative CPU across every pid matching a pattern
agg_of() {
  ps -Ao comm=,utime=,stime= 2>/dev/null | grep -E "$1" \
    | awk '{n=NF; print $(n-1), $n}' | while read -r u s; do echo "$u"; echo "$s"; done \
    | secs | awk '{t+=$1} END{printf "%.2f", t+0}'
}
delta() { echo "$1 $2 $3" | awk '{printf "%.1f", ($2-$1)/$3*100}'; }

run() {
  : > "$OUT"
  {
    echo "=== replicated WindowServer measurement ==="
    echo "build: $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "reps=$REPS window=${WIN}s"
    echo "start: $(date)"
  } >> "$OUT"

  sleep "$LEAD"
  WS=$(pgrep -x WindowServer | head -1)

  {
    echo
    echo "refresh rate: $(/usr/bin/swift -e '
import CoreGraphics
var i=[CGDirectDisplayID](repeating:0,count:8); var n:UInt32=0
CGGetActiveDisplayList(8,&i,&n)
if n>0, let m=CGDisplayCopyDisplayMode(i[0]) { print("\(m.refreshRate) Hz") }' 2>/dev/null)"
    echo "on-screen window owners:"
    /usr/bin/swift -e '
import CoreGraphics
guard let l = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String:Any]] else { exit(0) }
var c:[String:Int]=[:]
for w in l { c[(w[kCGWindowOwnerName as String] as? String) ?? "?", default:0] += 1 }
for (k,v) in c.sorted(by:{$0.value > $1.value}) { print(String(format:"    %3d  %@", v, k)) }' 2>/dev/null
    echo
    printf "%-4s %8s %10s %10s\n" "rep" "WS%" "mds+wkr%" "note"
  } >> "$OUT"

  vals=""
  for r in $(seq 1 "$REPS"); do
    b_ws=$(cpu_of "$WS");  b_md=$(agg_of "mds|mdworker|mds_stores")
    t0=$(date +%s)
    sleep "$WIN"
    t1=$(date +%s); el=$((t1-t0))
    a_ws=$(cpu_of "$WS");  a_md=$(agg_of "mds|mdworker|mds_stores")

    bu=$(echo "$b_ws"|awk '{print $1}'|secs); bs=$(echo "$b_ws"|awk '{print $2}'|secs)
    au=$(echo "$a_ws"|awk '{print $1}'|secs); as=$(echo "$a_ws"|awk '{print $2}'|secs)
    ws=$(echo "$au $bu $as $bs $el" | awk '{printf "%.1f", (($1-$2)+($3-$4))/$5*100}')
    md=$(delta "$b_md" "$a_md" "$el")

    printf "%-4s %8s %10s\n" "$r" "$ws" "$md" >> "$OUT"
    vals="$vals $ws"
  done

  {
    echo
    echo "$vals" | awk '{
      n=NF; mn=$1; mx=$1; s=0
      for(i=1;i<=n;i++){ s+=$i; if($i<mn)mn=$i; if($i>mx)mx=$i }
      m=s/n; v=0
      for(i=1;i<=n;i++) v+=($i-m)*($i-m)
      printf "WindowServer: mean=%.1f%%  min=%.1f%%  max=%.1f%%  sd=%.1f  spread=%.1fx\n", m, mn, mx, sqrt(v/n), (mn>0? mx/mn : 0)
    }'
    echo
    echo "HOW TO READ:"
    echo "  spread < 1.3x and mean > 40%  -> stable high floor; regression is real, file it."
    echo "  spread < 1.3x and mean < 20%  -> it was workload all along; close the issue."
    echo "  spread > 1.5x                 -> still uncontrolled; check the mds+wkr column:"
    echo "                                   if WS% tracks it, Spotlight load is the confound."
    echo "done: $(date)"
  } >> "$OUT"
}

run &
disown
echo "Running $REPS x ${WIN}s. Quit apps NOW and leave the machine alone."
echo "~$(( (LEAD + REPS*WIN)/60 + 1 )) min. Results: $OUT"

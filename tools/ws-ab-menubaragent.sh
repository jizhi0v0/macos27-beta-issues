#!/bin/bash
# Decisive A/B for the WindowServer high-CPU state: measure it, capture evidence
# while it is still there, restart MenuBarAgent, measure again.
#
# WHY THIS EXISTS
# ---------------
# #3 (the ~42-46% idle floor on beta4) and #22 (a further ~55% that accumulates
# over days and is cleared by `killall MenuBarAgent`) were only ever linked by
# one number: #22's post-recovery 44.9% landing inside #3's 42-46% floor. On
# beta5 26A5406e the floor is gone on jizhi0v0's M3 Max (~4% clean idle), so
# that link no longer holds and the question is what the OTHER machine reads
# AFTER restarting MenuBarAgent.
#
# So: run this WHILE THE MACHINE IS IN THE BAD STATE (UI laggy, WindowServer
# high after hours of uptime). Running it on a freshly booted machine measures
# nothing.
#
# THE PHASE-B NUMBER ALONE DOES NOT DECIDE ANYTHING -- MEASURED, NOT ASSUMED
# -------------------------------------------------------------------------
# An earlier version of this script printed a verdict straight off phase B
# ("still ~45% -> the two-layer reading was wrong"). Test-running it on a
# healthy beta5 M3 Max, on a WORKING desktop (21 on-screen window owners: Mail,
# WeChat, Chrome, Spotify, iPhone Mirroring...), produced:
#
#     phase A 66.0%  ->  phase B 47.8%
#
# i.e. a machine whose idle floor is ~4% still lands on 47.8% after the kill,
# purely from ordinary compositing load. So "~45% after the kill" is NOT
# evidence of a floor -- and note that #22's original 44.9% was likewise
# measured on a working desktop, never on an idle one, which is a gap in the
# original two-layer argument, not something this script invented.
#
# The floor is an IDLE measurement, so it can only be answered by an idle
# control. This script therefore ends by telling you to quit everything and run
# tools/ws-replicate.sh; that number -- call it phase C -- is the one that maps
# onto #3's 42-46% (beta4) vs ~4% (beta5).
#
#   C in single digits -> the floor is fixed on this machine too; whatever
#                         phase B showed was load, or #22's separate layer
#   C at ~40-46%       -> the floor IS present here on beta5 -> #3 is not fixed
#                         cross-machine, which is the finding worth having
#   the high state never comes back at all -> #22 is fixed too
#
# TWO TRAPS THIS SCRIPT CONTROLS FOR
# ----------------------------------
# 1. A LOCKED SCREEN RAISES WindowServer CPU -- the lock UI is animated, so it
#    composites MORE than a static idle desktop. One beta5 run here was 73%
#    locked and had to be voided. `pmset displaysleep` is the WRONG knob; the
#    lock is the loginwindow screensaver idle timer. This script sets
#    com.apple.screensaver idleTime to 0 for the run, restores it after, AND
#    verifies from the loginwindow log that no lock actually overlapped.
# 2. `ps %cpu` reports a decaying average. This measures cumulative
#    utime+stime deltas over a fixed window instead.
#
# USAGE (Terminal, not through an agent). Run as YOUR OWN user, never under
# sudo -- as root the screensaver preference and the CoreGraphics window list
# belong to a different session, so the lock guard would silently do nothing:
#   sudo -v                                     # optional: enables the stack capture
#   bash tools/ws-ab-menubaragent.sh            # ~14 min, unattended
#   REPS=3 WIN=45 bash tools/ws-ab-menubaragent.sh
#   NOKILL=1 bash tools/ws-ab-menubaragent.sh   # phase A only, don't restart MenuBarAgent
#
# Start it, then LEAVE THE MACHINE ALONE (don't quit apps -- the bad state is
# what we are measuring) until it prints DONE. Results: /tmp/ws_ab.txt
#
# `sample WindowServer` needs root, so it is taken in the first seconds of the
# run while a `sudo -v` credential cache is still valid. Skip the `sudo -v` and
# the script just prints the command to run by hand.

if [ "$(id -u)" = "0" ]; then
  echo "Run this as your normal user, NOT under sudo." >&2
  echo "As root the screensaver preference and the window list are a different" >&2
  echo "session, so the lock guard would silently do nothing." >&2
  echo "For the stack capture, run 'sudo -v' first and then re-run without sudo." >&2
  exit 1
fi

REPS=${REPS:-5}
WIN=${WIN:-60}
LEAD=${LEAD:-30}
SETTLE=${SETTLE:-45}      # let the menu bar rebuild before measuring phase B
OUT=/tmp/ws_ab.txt

secs() { awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}'; }
cpu_of() { ps -o utime=,stime= -p "$1" 2>/dev/null | awk '{print $1" "$2}'; }

# one measurement phase: prints "rep  WS%" lines, echoes the values
phase() { # $1 = label, $2 = ws pid
  local vals="" r b a bu bs au as t0 t1 el ws
  echo "--- phase $1 ---" >> "$OUT"
  printf "%-4s %8s\n" "rep" "WS%" >> "$OUT"
  for r in $(seq 1 "$REPS"); do
    b=$(cpu_of "$2"); t0=$(date +%s)
    sleep "$WIN"
    t1=$(date +%s); a=$(cpu_of "$2"); el=$((t1-t0))
    bu=$(echo "$b"|awk '{print $1}'|secs); bs=$(echo "$b"|awk '{print $2}'|secs)
    au=$(echo "$a"|awk '{print $1}'|secs); as=$(echo "$a"|awk '{print $2}'|secs)
    ws=$(echo "$au $bu $as $bs $el" | awk '{printf "%.1f", (($1-$2)+($3-$4))/$5*100}')
    printf "%-4s %8s\n" "$r" "$ws" >> "$OUT"
    vals="$vals $ws"
  done
  echo "$vals" | awk -v l="$1" '{
    n=NF; mn=$1; mx=$1; s=0
    for(i=1;i<=n;i++){ s+=$i; if($i<mn)mn=$i; if($i>mx)mx=$i }
    m=s/n; v=0; for(i=1;i<=n;i++) v+=($i-m)*($i-m)
    printf "%s: mean=%.1f%%  min=%.1f%%  max=%.1f%%  sd=%.1f\n", l, m, mn, mx, sqrt(v/n)
  }' >> "$OUT"
  echo "$vals" | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; printf "%.1f", s/NF}'
}

run() {
  local T0 T1 IDLE WS MBA MEAN_A MEAN_B INV_A INV_B
  T0=$(date "+%Y-%m-%d %H:%M:%S")
  : > "$OUT"
  {
    echo "=== WindowServer A/B across a MenuBarAgent restart ==="
    echo "build:  $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "model:  $(sysctl -n hw.model)  $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    echo "uptime: $(uptime | sed 's/^ *//')"
    echo "reps=$REPS window=${WIN}s  start: $T0"
  } >> "$OUT"

  # --- lock guard -----------------------------------------------------------
  IDLE=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo unset)
  defaults -currentHost write com.apple.screensaver idleTime -int 0 2>/dev/null
  echo "screensaver idleTime: was $IDLE, set to 0 for the run" >> "$OUT"

  sleep "$LEAD"
  WS=$(pgrep -x WindowServer | head -1)
  MBA=$(pgrep -f "MenuBarAgent.app/Contents/MacOS/MenuBarAgent" | head -1)
  {
    echo "WindowServer pid $WS   elapsed $(ps -o etime= -p "$WS" | tr -d ' ')"
    echo "MenuBarAgent pid ${MBA:-none}  elapsed $(ps -o etime= -p "${MBA:-0}" 2>/dev/null | tr -d ' ')"
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
  } >> "$OUT"

  # Stack capture FIRST, while a `sudo -v` credential cache is still valid --
  # and while the bad state is definitely still up. `sudo -n` never prompts, so
  # an unattended run degrades to a printed command instead of hanging.
  if sudo -n true 2>/dev/null; then
    sudo -n sample "$WS" 10 -file /tmp/ws_sample_before.txt >/dev/null 2>&1 \
      && echo "sample -> /tmp/ws_sample_before.txt" >> "$OUT" \
      || echo "sample failed -- run by hand: sudo sample WindowServer 10 -file /tmp/ws_sample_before.txt" >> "$OUT"
  else
    echo "sample skipped (no sudo credential). In the bad state run by hand:" >> "$OUT"
    echo "    sudo sample WindowServer 10 -file /tmp/ws_sample_before.txt" >> "$OUT"
  fi

  # --- phase A: the state as found ------------------------------------------
  MEAN_A=$(phase "A (as found)" "$WS")

  # log evidence that only exists while the state is up
  INV_A=$(/usr/bin/log show --last 60s --style compact \
            --predicate 'eventMessage CONTAINS "Invalid window"' 2>/dev/null | grep -c "Invalid window")
  echo "Invalid window: $INV_A lines / 60 s (phase A)" >> "$OUT"

  # --- gate: is the bad state actually present? ------------------------------
  if awk -v m="$MEAN_A" 'BEGIN{exit !(m < 25)}'; then
    {
      echo
      echo "STOP: phase A mean is ${MEAN_A}% -- the high-CPU state is NOT present."
      echo "Restarting MenuBarAgent now would prove nothing. Re-run this script"
      echo "while the UI is actually laggy (typically after hours of uptime)."
    } >> "$OUT"
    NOKILL=1
  fi

  # --- phase B: after restarting MenuBarAgent --------------------------------
  if [ -z "$NOKILL" ]; then
    echo >> "$OUT"
    echo "killall MenuBarAgent at $(date "+%H:%M:%S")" >> "$OUT"
    killall MenuBarAgent 2>>"$OUT"
    sleep "$SETTLE"
    WS=$(pgrep -x WindowServer | head -1)   # WindowServer should NOT have changed
    MEAN_B=$(phase "B (after MenuBarAgent restart)" "$WS")
    INV_B=$(/usr/bin/log show --last 60s --style compact \
              --predicate 'eventMessage CONTAINS "Invalid window"' 2>/dev/null | grep -c "Invalid window")
    echo "Invalid window: $INV_B lines / 60 s (phase B)" >> "$OUT"
  fi

  # --- restore + verify no lock overlapped ----------------------------------
  T1=$(date "+%Y-%m-%d %H:%M:%S")
  if [ "$IDLE" != "unset" ]; then
    defaults -currentHost write com.apple.screensaver idleTime -int "$IDLE" 2>/dev/null
  fi
  {
    echo
    echo "--- lock check over $T0 .. $T1 (any line here VOIDS the run) ---"
    /usr/bin/log show --start "$T0" --end "$T1" --style compact \
      --predicate 'process == "loginwindow" AND (eventMessage CONTAINS "screensaver.didstart" OR eventMessage CONTAINS "screensaver.didstop")' 2>/dev/null \
      | grep -i screensaver || echo "    (none -- run is valid)"
    echo "screensaver idleTime restored to $IDLE"
    echo
    echo "--- result ---"
    if [ -n "$MEAN_B" ]; then
      awk -v a="$MEAN_A" -v b="$MEAN_B" 'BEGIN{
        printf "A (bad state) %.1f%%  ->  B (after MenuBarAgent restart) %.1f%%\n", a, b
        if (b < 10)  print "  B is in single digits: the restart cleared it, and there is no residue to explain."
        else         print "  B is " int(b+0.5) "%: this is a WORKING desktop, so it does NOT by itself show a floor -- a healthy beta5 machine measured 47.8% here under ordinary app load. Do the idle control below."
        if (a - b < 10) print "  A and B are close: the MenuBarAgent restart did NOT clear much this time -- say so; it would not match #22s recovery."
      }'
      echo
      echo "  NOW DO THE IDLE CONTROL (phase C) -- this is the number that decides it:"
      echo "    quit every app, then:  bash tools/ws-replicate.sh   (~6 min, results /tmp/ws_replicate.txt)"
      echo "    C in single digits -> the #3 floor is fixed on this machine too"
      echo "    C at ~40-46%       -> the floor IS present here on beta5; #3 is not fixed cross-machine"
      echo "  Paste A, B and C together with the window-owner list above."
    else
      echo "phase A only: ${MEAN_A}%  (no MenuBarAgent restart was performed)"
    fi
    echo
    echo "DONE: $T1"
  } >> "$OUT"
}

run &
disown
echo "Running: ${REPS}x${WIN}s before, MenuBarAgent restart, ${REPS}x${WIN}s after."
echo "Do NOT quit apps -- the bad state is the thing being measured. Leave the machine alone."
echo "~$(( (LEAD + 2*REPS*WIN + SETTLE)/60 + 2 )) min. Results: $OUT"

#!/bin/bash
# Decisive WindowServer idle-baseline test.
#
# Solves the confound documented in issues/apple-windowserver-invalid-window.md:
# "a clean idle baseline is impossible mid-session because the Claude app must
# stay open and is a top driver". This script is detached from Claude entirely,
# so you can QUIT Claude while it measures.
#
# USAGE (run in Terminal, NOT through Claude):
#   bash tools/ws-idle-baseline.sh
#   -> then immediately quit Claude, Chrome, and everything else, and DON'T
#      touch the machine for 3 minutes. Let the screen sit (disable the
#      screensaver / display sleep first, or it will park the compositor).
#   -> reopen Claude afterwards and read /tmp/ws_idle_baseline.txt
#
# Measures cumulative utime+stime deltas, which are immune to the decaying
# average that `ps %cpu` reports.

OUT=/tmp/ws_idle_baseline.txt
LEAD=45      # seconds to let you quit apps and walk away
WINDOW=120   # measurement window

secs() { awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}'; }
cpu_of() { ps -o utime=,stime= -p "$1" 2>/dev/null | awk '{print $1" "$2}'; }
delta_pct() { # before_str after_str elapsed
  local bu bs au as
  bu=$(echo "$1" | awk '{print $1}' | secs); bs=$(echo "$1" | awk '{print $2}' | secs)
  au=$(echo "$2" | awk '{print $1}' | secs); as=$(echo "$2" | awk '{print $2}' | secs)
  echo "$au $bu $as $bs $3" | awk '{printf "%.1f", (($1-$2)+($3-$4))/$5*100}'
}

run() {
  : > "$OUT"
  {
    echo "=== WindowServer idle baseline ==="
    echo "build: $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "start: $(date)"
    echo "lead-in ${LEAD}s (quit apps now), then ${WINDOW}s measurement"
    echo
  } >> "$OUT"

  sleep "$LEAD"

  WS=$(pgrep -x WindowServer | head -1)
  MBA=$(pgrep -f "MenuBarAgent.app/Contents/MacOS/MenuBarAgent" | head -1)

  # Do NOT use a hardcoded app-name pattern here -- an earlier version did, and
  # it silently missed Alcove/Klack/Surge, which made a NON-idle desktop look
  # idle and produced a bogus "confirmed regression" verdict. List every process
  # that owns an on-screen window instead, so nothing can hide.
  echo "--- processes owning on-screen windows at measurement start ---" >> "$OUT"
  /usr/bin/swift -e '
import CoreGraphics
guard let l = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String:Any]] else { exit(0) }
var c: [String:Int] = [:]
for w in l { c[(w[kCGWindowOwnerName as String] as? String) ?? "?", default: 0] += 1 }
for (k,v) in c.sorted(by: {$0.value > $1.value}) { print(String(format: "  %3d  %@", v, k)) }
' >> "$OUT" 2>/dev/null
  echo "--- all running /Applications bundles ---" >> "$OUT"
  ps -Ao comm= | grep "^/Applications" | sed 's|/Contents/.*||; s|.*/||' | sort -u | tr '\n' ' ' >> "$OUT"
  echo >> "$OUT"; echo >> "$OUT"

  # Hold a display + user-active assertion across the whole run.
  #
  # This is NOT optional: the screen saver idle time on this machine is 120 s
  # (loginwindow: `idleTimePreference | idleTime: 120`), shorter than a full
  # run, and the screen saver is a full-screen animation WindowServer has to
  # composite -- on 2026-08-19 it started 75 s into the window and inflated the
  # result. Two runs were wasted before this was added.
  #
  # Form matters, per caffeinate(8):
  #   -u without -t is dropped after a DEFAULT 5 SECONDS, so -t is mandatory;
  #   -t and -w are both IGNORED when a utility is invoked, so this has to be a
  #     standalone background process, not `caffeinate ... some-command`;
  #   -w $$ would be wrong here -- in bash 3.2 (which is what macOS ships) $$
  #     inside a subshell is the PARENT's pid, and the parent exits immediately
  #     after `run & disown`, which would release the assertion at once.
  # A launching shell's own `caffeinate -t N &` is not reliable either: one such
  # job was logged by powerd as ClientDied at age 00:00:12.
  caffeinate -d -u -t $((WINDOW + 180)) &
  CAFF=$!

  t0=$(date +%s)
  WSTART=$(date '+%Y-%m-%d %H:%M:%S')
  b_ws=$(cpu_of "$WS"); b_mba=$(cpu_of "$MBA")

  sleep $((WINDOW/2))
  echo "--- midpoint top drivers ---" >> "$OUT"
  top -l 2 -s 2 -o cpu -stats command,cpu -n 12 2>/dev/null \
    | awk '/^Processes:/{c++} c==2' \
    | grep -vE "Load Avg|CPU usage|SharedLibs|MemReg|PhysMem|^VM|Networks|Disks|Processes|^$" >> "$OUT"
  echo >> "$OUT"
  sleep $((WINDOW/2))

  t1=$(date +%s); elapsed=$((t1-t0))
  a_ws=$(cpu_of "$WS"); a_mba=$(cpu_of "$MBA")

  {
    echo "--- RESULT (cumulative CPU over ${elapsed}s) ---"
    echo "WindowServer: $(delta_pct "$b_ws" "$a_ws" "$elapsed")%"
    [ -n "$MBA" ] && echo "MenuBarAgent: $(delta_pct "$b_mba" "$a_mba" "$elapsed")%"
    echo
    echo "Invalid window / 60s: $(/usr/bin/log show --last 60s --style syslog \
      --predicate 'process == "WindowServer"' 2>/dev/null | grep -c 'Invalid window')"
    echo
    # --- window validity, checked from loginwindow's own log ---
    # Do NOT grep for ScreenSaverEngine/legacyScreenSaver: on macOS 27 no such
    # process appears even when the screen saver IS running (verified 2026-08-19,
    # 0 hits across a window in which it demonstrably ran). loginwindow's
    # "starting screen saver due to user idle" is the reliable marker.
    SS=$(/usr/bin/log show --start "$WSTART" --style syslog \
      --predicate 'process == "loginwindow"' 2>/dev/null \
      | grep -c 'starting screen saver due to user idle')
    # Detect INPUT, not low idle. Once the caffeinate assertion is held,
    # loginwindow cancels its idle timer and stops sampling -- so there is often
    # exactly ONE actualUserIdle value in the window and it can be far below the
    # window length. An earlier version demanded `min >= window length`, which
    # that behaviour makes unsatisfiable; it flagged a perfectly clean run.
    # A reset (a later sample LOWER than an earlier one) is the real evidence of
    # a keypress or mouse move.
    IDLESEQ=$(/usr/bin/log show --start "$WSTART" --style syslog \
      --predicate 'process == "loginwindow"' 2>/dev/null \
      | sed -n 's/.*actualUserIdle = \([0-9.]*\).*/\1/p')
    RESETS=$(echo "$IDLESEQ" | awk 'NR>1 && $1 < prev {n++} {prev=$1} END {print n+0}')
    echo "--- WINDOW VALIDITY ---"
    if [ "$SS" -gt 0 ]; then
      echo "  INVALID: screen saver started during the window ($SS activation(s))."
      echo "           It is a full-screen animation WindowServer must composite,"
      echo "           so the number above is inflated. Re-run."
    else
      echo "  screen saver: did not start (OK)"
    fi
    if [ -n "$IDLESEQ" ]; then
      if [ "$RESETS" -gt 0 ]; then
        echo "  INVALID: user idle was reset $RESETS time(s) during the window --"
        echo "           the machine was touched, and input events are WindowServer"
        echo "           work. Re-run without touching it."
      else
        echo "  user input: none detected (idle never reset) (OK)"
      fi
      echo "  actualUserIdle samples: $(echo "$IDLESEQ" | tr '\n' ' ')"
    else
      echo "  user input: no loginwindow samples in window (assertion held early;"
      echo "              treat as OK unless you know you touched the machine)"
    fi
    echo
    echo "VERDICT:"
    echo "  <15%  -> compositing workload, not a regression. Close the issue."
    echo "  >40%  -> real beta regression. Capture: sudo sysdiagnose -f ~/Desktop"
    echo "  else  -> subtract MenuBarAgent's share and re-judge."
    echo "done: $(date)"
  } >> "$OUT"

  kill "$CAFF" 2>/dev/null
}

run &
disown
echo "Measuring in background. Quit your apps NOW and leave the machine alone."
echo "A caffeinate assertion is held for the run, and the result reports whether"
echo "the screen saver fired and whether the machine was actually left idle."
echo "Results in ~$(( (LEAD+WINDOW)/60 + 1 )) min at: $OUT"

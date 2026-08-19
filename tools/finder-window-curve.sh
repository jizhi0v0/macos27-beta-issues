#!/bin/bash
# Cost-per-on-screen-window curve, using Finder windows as the knob.
#
# WHY: on 2026-08-19 a bare beta6 desktop measured 4.5% WindowServer at 120Hz and
# 34.2%/46.5% with 13 Finder windows open. That per-window cost is the open
# question -- is ~2.6 points of a core per window normal, or a macOS 27 defect?
# This produces the curve; comparing it against a macOS 26 machine answers it.
#
# RUN IT FROM TERMINAL AND QUIT THE CLAUDE APP FIRST. Claude.app is an Electron
# window whose activity indicator animates continuously while an agent works, and
# it was measured at ~41 points on its own -- roughly twelve Finder windows. Any
# measurement taken with it open is dominated by it. Same for browsers playing
# video, Telegram with animated stickers, and anything else that redraws.
#
# Start it, then LEAVE THE MACHINE ALONE until it prints DONE. ~6 minutes.
# Results: /tmp/finder_curve.txt

STEPS=${STEPS:-"0 4 8 12"}
WIN=${WIN:-60}
OUT=/tmp/finder_curve.txt
DIRS=(/Applications /System /Users /Library /usr /tmp /etc /var /opt /private "$HOME" "$HOME/Developer")

secs(){ awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}'; }
cpu(){ ps -o utime=,stime= -p "$1" 2>/dev/null | awk '{print $1,$2}'; }
owners(){ /usr/bin/swift -e '
import CoreGraphics
guard let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String:Any]] else { exit(0) }
var c:[String:Int]=[:]
for w in l { c[(w[kCGWindowOwnerName as String] as? String) ?? "?", default:0] += 1 }
print(c.sorted{$0.value > $1.value}.map{"\($0.key):\($0.value)"}.joined(separator: " "))' 2>/dev/null; }

run() {
  # hold the display awake for the whole sweep -- see ws-idle-baseline.sh for why
  # the form matters (-u without -t is dropped after 5s; -t/-w are ignored when a
  # utility is invoked; -w $$ binds to the parent under bash 3.2)
  caffeinate -d -u -t $(( (WIN + 20) * 6 )) & CAFF=$!
  {
    echo "=== WindowServer cost per on-screen Finder window ==="
    echo "build:   $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "model:   $(sysctl -n hw.model)"
    echo "refresh: $(/usr/bin/swift -e 'import CoreGraphics
if let m = CGDisplayCopyDisplayMode(CGMainDisplayID()) { print("\(m.refreshRate) Hz") }' 2>/dev/null)"
    echo "start:   $(date '+%F %T %z')   window=${WIN}s per step"
    echo
    printf "%-5s %-9s %s\n" "N" "WS%" "on-screen owners"
  } > "$OUT"
  WSTART=$(date '+%Y-%m-%d %H:%M:%S')
  for N in $STEPS; do
    killall Finder 2>/dev/null; sleep 6
    if [ "$N" -gt 0 ]; then
      for i in $(seq 0 $((N-1))); do open "${DIRS[$i]}" 2>/dev/null; sleep 0.4; done
    fi
    sleep 12                       # let the windows finish drawing
    WS=$(pgrep -x WindowServer); O=$(owners)
    B=$(cpu "$WS"); T0=$(date +%s); sleep "$WIN"; T1=$(date +%s); A=$(cpu "$WS")
    bu=$(echo "$B"|awk '{print $1}'|secs); bs=$(echo "$B"|awk '{print $2}'|secs)
    au=$(echo "$A"|awk '{print $1}'|secs); as=$(echo "$A"|awk '{print $2}'|secs)
    printf "%-5s %-9s %s\n" "$N" \
      "$(echo "$au $bu $as $bs $((T1-T0))" | awk '{printf "%.1f%%", (($1-$2)+($3-$4))/$5*100}')" "$O" >> "$OUT"
  done
  killall Finder 2>/dev/null
  {
    echo
    echo "--- WINDOW VALIDITY (same checks as ws-idle-baseline.sh) ---"
    SS=$(/usr/bin/log show --start "$WSTART" --style syslog --predicate 'process == "loginwindow"' 2>/dev/null \
         | grep -c 'starting screen saver due to user idle')
    [ "$SS" -gt 0 ] && echo "  INVALID: screen saver started ($SS) -- re-run" \
                    || echo "  screen saver: did not start (OK)"
    SEQ=$(/usr/bin/log show --start "$WSTART" --style syslog --predicate 'process == "loginwindow"' 2>/dev/null \
          | sed -n 's/.*actualUserIdle = \([0-9.]*\).*/\1/p')
    R=$(echo "$SEQ" | awk 'NR>1 && $1 < prev {n++} {prev=$1} END {print n+0}')
    [ "$R" -gt 0 ] && echo "  INVALID: user idle reset $R time(s) -- machine was touched" \
                   || echo "  user input: none detected (OK)"
    echo
    echo "Claude.app running during the sweep? -> $(pgrep -x Claude >/dev/null && echo 'YES -- RESULTS INVALID, it is worth ~41 points' || echo 'no (good)')"
    echo "done: $(date '+%F %T %z')"
  } >> "$OUT"
  kill "$CAFF" 2>/dev/null
}
run &
disown
echo "Sweep running (${STEPS} windows, ${WIN}s each). QUIT CLAUDE NOW if it is open."
echo "Leave the machine alone. Results in ~6 min at: $OUT"

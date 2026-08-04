#!/bin/bash
# Capture a spindump of WindowServer WHILE the desktop is genuinely idle.
#
# Everything before this measured *that* WindowServer is high (~45-52% with all
# GUI apps quit). Only a spindump taken during that same idle window can show
# *why*. The earlier spindump (18:04) was taken with Mail/DingTalk/Telegram/
# Claude all live, so its stacks reflect a loaded desktop, not an idle one.
#
# USAGE (run in Terminal, needs sudo for spindump):
#   sudo bash tools/ws-idle-spindump.sh
#   -> quit every app immediately, then don't touch the machine for ~3 min.
#      Turn OFF screensaver + display sleep first.
#
# Output: /tmp/ws_idle_spindump.txt  (+ /tmp/ws_idle_spindump_summary.txt)

if [ "$(id -u)" -ne 0 ]; then
  echo "Needs root for spindump. Re-run: sudo bash $0" >&2
  exit 1
fi

REAL_USER=${SUDO_USER:-$(stat -f%Su /dev/console)}
OUT=/tmp/ws_idle_spindump.txt
SUM=/tmp/ws_idle_spindump_summary.txt
LEAD=50
secs() { awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}'; }

run() {
  : > "$SUM"
  echo "=== idle spindump run: $(date) ===" >> "$SUM"
  sleep "$LEAD"

  WS=$(pgrep -x WindowServer | head -1)

  echo "--- GUI apps alive at capture ---" >> "$SUM"
  pgrep -l -f "Claude|Chrome|Telegram|DingTalk|Spotify|Mail.app|IntelliJ|OrbStack|Alcove|Surge" \
    | grep -viE "crashpad|helper \(gpu" | head -15 >> "$SUM"

  echo "--- on-screen window count ---" >> "$SUM"
  su "$REAL_USER" -c '/usr/bin/swift -e "
import CoreGraphics
let a = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String:Any]])?.count ?? -1
let o = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String:Any]])?.count ?? -1
print(\"all=\(a) onscreen=\(o)\")
"' >> "$SUM" 2>/dev/null

  b=$(ps -o utime=,stime= -p "$WS" | awk '{print $1,$2}')
  t0=$(date +%s)

  echo "--- capturing 10s spindump ---" >> "$SUM"
  spindump "$WS" 10 -o "$OUT" >/dev/null 2>&1

  t1=$(date +%s)
  a=$(ps -o utime=,stime= -p "$WS" | awk '{print $1,$2}')
  el=$((t1-t0))
  bu=$(echo "$b" | awk '{print $1}' | secs); bs=$(echo "$b" | awk '{print $2}' | secs)
  au=$(echo "$a" | awk '{print $1}' | secs); as=$(echo "$a" | awk '{print $2}' | secs)
  echo "WindowServer CPU during capture (${el}s): $(echo "$au $bu $as $bs $el" \
    | awk '{printf "%.1f%%", (($1-$2)+($3-$4))/$5*100}')" >> "$SUM"

  echo "--- top processes during capture (from spindump) ---" >> "$SUM"
  awk '/^Process: /{p=$2" "$3} /^CPU Time: /{gsub("s","",$3); if(p!=""){print $3, p; p=""}}' "$OUT" \
    2>/dev/null | sort -rn | head -12 >> "$SUM"

  chmod 644 "$OUT" "$SUM" 2>/dev/null
  echo "DONE $(date)" >> "$SUM"
}

run &
disown
echo "Capturing in background. Quit all apps NOW and leave the machine alone (~3 min)."
echo "Summary: $SUM"
echo "Full spindump: $OUT"

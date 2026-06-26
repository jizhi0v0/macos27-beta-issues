#!/bin/bash
# Decisive WindowServer baseline test for the "high CPU" question in
# issues/apple-windowserver-invalid-window.md
#
# RUN THIS ON A QUIESCED DESKTOP:
#   - quit Claude, Chrome (or stop any playing video), Spotify, and other
#     continuously-animating apps
#   - close most windows; let the desktop sit idle ~20s
#   - then run: bash tools/check-windowserver.sh
#
# Uses `top -l 2` (2nd frame = a real sampled value, not the noisy instant).

echo "== WindowServer sampled CPU + top compositing drivers =="
top -l 2 -s 2 -o cpu -stats command,cpu,time -n 8 2>/dev/null \
  | awk '/^Processes:/{c++} c==2' \
  | grep -vE "Load Avg|CPU usage|SharedLibs|MemReg|PhysMem|^VM|Networks|Disks|Processes|^$" \
  | head -9

echo
echo "== Invalid-window log spam (separate minor bug), last 60s =="
/usr/bin/log show --last 60s --style syslog 2>/dev/null \
  | grep -c "_CGXPackagesSetWindowConstraints: Invalid window"

cat <<'NOTE'

== How to read it ==
  WindowServer < ~15%  on a truly idle/quiesced desktop
      -> the ~48% seen earlier was just compositing WORKLOAD, not a bug.
         Close the WindowServer issue.
  WindowServer > ~40%  while genuinely idle (nothing animating, few windows)
      -> likely a real beta regression. Capture and file:
         sudo spindump WindowServer 8 -o ~/ws_spindump.txt
         sudo sysdiagnose -f ~/Desktop
NOTE

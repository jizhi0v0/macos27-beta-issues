#!/bin/bash
# Causal test for the "notification is inert" freeze (see issues/#26, Variations).
#
# The problem with testing this by hand: to find out whether a notification is
# interactive you have to interact with it — and interaction may itself be what
# spawns UserNotificationCenter. So the correlation "UNC alive <=> notification
# works" is confounded by the act of measuring.
#
# This script breaks that loop: it launches UserNotificationCenter WITHOUT you
# touching the notification, so the only thing that changed is UNC's liveness.
#
#   ./unc-revive-test.sh revive    # run this WHILE a notification is inert
#   ./unc-revive-test.sh check     # run this AFTER you click it once
#
UNC=/System/Library/CoreServices/UserNotificationCenter.app
alive() { ps aux | grep "[U]serNotificationCenter" | awk '{print $2}' | tr '\n' ' '; }

case "${1:-revive}" in
revive)
  echo "T0 $(date '+%H:%M:%S')  UNC before : $(alive)"
  echo "   --- launching UserNotificationCenter (you: DO NOT touch the notification) ---"
  open -g "$UNC" 2>&1 || open "$UNC" 2>&1
  sleep 1.5
  echo "T1 $(date '+%H:%M:%S')  UNC after  : $(alive)"
  echo
  echo "NOW: click the stuck notification exactly ONCE, then run:  $0 check"
  echo "  worked  -> UNC liveness is the cause"
  echo "  no      -> the earlier correlation was reverse causality; UNC is a bystander"
  date +%s > /tmp/unc-revive-t0
  ;;
check)
  t0=$(cat /tmp/unc-revive-t0 2>/dev/null || echo 0)
  win=$(( $(date +%s) - t0 + 5 )); [ "$win" -lt 10 ] && win=10
  echo "checking the last ${win}s of usernoted (objective — independent of what you saw)"
  got=$(/usr/bin/log show --predicate 'process == "usernoted"' --info --debug --last "${win}s" 2>/dev/null | grep -c "Received response")
  fwd=$(/usr/bin/log show --predicate 'process == "usernoted"' --info --debug --last "${win}s" 2>/dev/null | grep -cE "sent to NSUserNotification client|Notifying UserNotifications client")
  echo "  clicks that reached usernoted : $got"
  echo "  of those, forwarded to the app: $fwd"
  echo "  UNC alive now                 : $(alive)"
  echo
  if   [ "$got" -eq 0 ]; then echo "=> click never reached usernoted — same shape as the Reminders freeze"
  elif [ "$fwd" -eq 0 ]; then echo "=> received but not forwarded — same shape as the Chrome bug (#26 main body)"
  else                        echo "=> delivered normally — the notification was live at click time"
  fi
  ;;
esac

#!/bin/bash
# Causal test for the "notification is inert" freeze (issues/#26, Variations).
#
# Why this exists: to find out whether a stuck notification is interactive you
# have to interact with it — and interaction may itself be what spawns
# UserNotificationCenter. So "UNC alive <=> notification works" is confounded by
# the act of measuring. This changes UNC's liveness WITHOUT touching the stuck
# notification, leaving liveness as the only variable.
#
#   ./unc-revive-test.sh spawn    # run WHILE a notification is inert
#   ./unc-revive-test.sh check    # run AFTER clicking the stuck one exactly once
#
# DO NOT try to launch UserNotificationCenter.app directly (`open`, or running
# the binary). It carries a launch constraint: the kernel SIGKILLs it within
# ~100 ms with "Namespace CODESIGNING, Code 4, Launch Constraint Violation", and
# the crash is auto-reported to Apple. An earlier version of this script did
# exactly that — it produced a crash, not a test. Verified on 27.0 26A5406e.
# The only sanctioned way to get UNC running is to make the system present a
# notification, which is what `spawn` does.

alive() { ps aux | grep "[U]serNotificationCenter" | awk '{print $2}' | tr '\n' ' '; }

case "${1:-spawn}" in
spawn)
  echo "T0 $(date '+%H:%M:%S')  UNC before: $(alive)"
  echo "   posting a throwaway notification so the SYSTEM spawns UNC via the sanctioned path"
  osascript -e 'display notification "unc-revive-test probe" with title "probe"' 2>&1
  sleep 2
  echo "T1 $(date '+%H:%M:%S')  UNC after : $(alive)"
  date +%s > /tmp/unc-revive-t0
  echo
  echo "NOW: click the ORIGINAL stuck notification exactly ONCE (ignore the probe), then:"
  echo "     $0 check"
  ;;
check)
  t0=$(cat /tmp/unc-revive-t0 2>/dev/null || echo 0)
  win=$(( $(date +%s) - t0 + 5 )); [ "$win" -lt 10 ] && win=10
  echo "reading the last ${win}s of usernoted — objective, independent of what you saw"
  got=$(/usr/bin/log show --predicate 'process == "usernoted"' --info --debug --last "${win}s" 2>/dev/null | grep -c "Received response")
  fwd=$(/usr/bin/log show --predicate 'process == "usernoted"' --info --debug --last "${win}s" 2>/dev/null | grep -cE "sent to NSUserNotification client|Notifying UserNotifications client")
  echo "  clicks that reached usernoted : $got"
  echo "  of those, forwarded to the app: $fwd"
  echo "  UNC alive now                 : $(alive)"
  echo
  if   [ "$got" -eq 0 ]; then echo "=> click never reached usernoted — the Reminders shape; UNC being up did NOT help"
  elif [ "$fwd" -eq 0 ]; then echo "=> received but not forwarded — the Chrome shape (#26 main body)"
  else                        echo "=> delivered normally — spawning UNC revived it; liveness is causal, not a bystander"
  fi
  echo "(caveat: the probe notification is itself a new notification, so a positive"
  echo " result cannot separate 'UNC came up' from 'a new notification arrived'.)"
  ;;
esac

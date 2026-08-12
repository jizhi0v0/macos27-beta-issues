#!/bin/bash
# Waits for the precondition of the #26 "shape A" failure, then tells you to run
# the one experiment that would unify the two failure shapes.
#
# Background (issues/chrome-notification-banner-frozen-unresponsive.md):
#   shape A — click DOES reach usernoted, but there is no live client to forward
#             it to.   61 clicks -> 61 "Received response", 0 forwarded.
#   shape B — click does NOT reach usernoted at all.  0 of 5.
# They have never been tried on the SAME notification, so it is still open
# whether they are one defect seen from two presentations (banner vs list) or
# two separate defects. This watcher catches the moment the test is possible.
#
# Precondition it waits for: a Chrome notification is still outstanding while
# "Google Chrome Helper (Alerts)" has exited — that is exactly the state in
# which shape A was measured.
#
#   ./shapeAB-watch.sh            # poll every 20s, alert on the terminal
#   POLL=10 ./shapeAB-watch.sh    # faster polling
#
if [ "$1" = "report" ]; then
  echo "last 5 minutes of usernoted, Chrome only:"
  got=$(/usr/bin/log show --predicate 'process == "usernoted"' --info --debug --last 5m 2>/dev/null | grep -i chrome | grep -c "Received response")
  fwd=$(/usr/bin/log show --predicate 'process == "usernoted"' --info --debug --last 5m 2>/dev/null | grep -i chrome | grep -c "sent to NSUserNotification client")
  echo "  clicks that reached usernoted : $got"
  echo "  of those, forwarded           : $fwd"
  if   [ "$got" -eq 0 ]; then echo "  => shape B (nothing reached usernoted)"
  elif [ "$fwd" -eq 0 ]; then echo "  => shape A (reached, never forwarded)"
  else                        echo "  => delivered normally"; fi
  exit 0
fi

POLL=${POLL:-20}
DB="$HOME/Library/Group Containers/group.com.apple.usernoted/db2/db"

outstanding() {   # number of Chrome notifications still displayed
  /usr/bin/python3 - "$DB" <<'PY' 2>/dev/null || echo 0
import sqlite3, sys
try:
    con = sqlite3.connect(sys.argv[1]); cur = con.cursor()
    cur.execute("SELECT app_id FROM app WHERE identifier LIKE '%chrome%'")
    n = 0
    for (a,) in cur.fetchall():
        cur.execute("SELECT list FROM displayed WHERE app_id=?", (a,))
        r = cur.fetchone()
        if r and r[0]:
            n += len(r[0]) // 16
    print(n)
except Exception:
    print(0)
PY
}
helper_pid() { ps aux | grep "Chrome Helper (Alerts)" | grep -v grep | awk '{print $2}' | head -1; }

echo "watching — Chrome notification outstanding + Alerts helper gone. Ctrl-C to stop."
while true; do
  n=$(outstanding); h=$(helper_pid)
  if [ "${n:-0}" -gt 0 ] && [ -z "$h" ]; then
    printf '\a'
    cat <<MSG

=========================================================
$(date '+%H:%M:%S')  PRECONDITION MET — $n Chrome notification(s) outstanding, Alerts helper NOT running

Do these two clicks, in this order, on the SAME notification:

  1. click it as an on-screen BANNER        (if it is still shown as one)
  2. open Notification Center, click the SAME entry in the LIST

Then run:   $(dirname "$0")/shapeAB-watch.sh report

  both fail the same way        -> one defect
  banner: nothing reaches usernoted, list: reaches but is not forwarded
                                -> shape A and shape B are one root cause seen
                                   through two presentations
=========================================================

MSG
    exit 0
  fi
  sleep "$POLL"
done

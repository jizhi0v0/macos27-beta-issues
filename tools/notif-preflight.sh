#!/bin/bash
# Refuse to start a #26 origin trial unless the starting state matches the
# localhost run's: zero outstanding Chrome notifications (ANY bundle) and no
# live Alerts helper. The 2026-08-27 16:38 run was invalidated because an
# Alerts-bundle notification from 15:55 was still outstanding, which makes the
# helper survive for reasons that have nothing to do with the origin.
set -u
S="$(cd "$(dirname "$0")" && pwd)"
SRC="$HOME/Library/Group Containers/group.com.apple.usernoted/db2"

rm -f "$S"/pf-db "$S"/pf-db-wal "$S"/pf-db-shm
cp "$SRC/db" "$S/pf-db" || { echo "ABORT: cannot copy db"; exit 2; }
[ -f "$SRC/db-wal" ] && cp "$SRC/db-wal" "$S/pf-db-wal"
[ -f "$SRC/db-shm" ] && cp "$SRC/db-shm" "$S/pf-db-shm"

# WAL matters: reading with immutable=1 skips it and returns a stale snapshot.
out=$(sqlite3 "$S/pf-db" \
  "select a.identifier, count(*) from record r join app a on r.app_id=a.app_id
   where lower(a.identifier) like '%chrome%' group by a.identifier;" 2>&1)
rc=$?
if [ $rc -ne 0 ]; then echo "ABORT: sqlite failed rc=$rc: $out"; exit 2; fi

echo "=== PREFLIGHT $(date '+%H:%M:%S') ==="
if [ -n "$out" ]; then
  echo "  ABORT — Chrome notifications still outstanding:"
  echo "$out" | sed 's/^/    /'
  exit 1
fi
echo "  outstanding Chrome notifications (any bundle): 0  ✅"

alive=$(ps -Ao comm= | grep -cF 'Chrome Helper (Alerts)')
echo "  live Alerts helpers: $alive"
[ "$alive" = 0 ] || { echo "  ABORT — a helper is already alive; the race cannot fire."; exit 1; }
echo "  ✅ clean start"

#!/bin/bash
# Cumulative utime+stime delta sampler -- immune to the decaying average that
# `ps %cpu` reports (memory: "one CPU reading isn't decision-grade").
# NOT a quiesced-idle baseline: it measures the machine AS LOADED, so a beta6
# reading taken the same way, with a comparable app set, is comparable.
#
# Two traps already paid for, do not reintroduce:
#   - macOS ships bash 3.2: no `declare -A`. Using it emitted a header-only table.
#   - `ps -o utime=,stime=` returns FRACTIONAL seconds (MM:SS.ss). bash $(( ))
#     cannot do floats and aborts mid-table. All arithmetic is in awk.
OUT="$1"; WINDOW="${2:-300}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PROCS="WindowServer mds_stores ecosystemd ecosystemanalyticsd trustd contactsd imagent MenuBarAgent ControlCenter logd corebrightnessd usernoted"
snap() { for p in $PROCS; do pid=$(pgrep -x "$p" | head -1); [ -n "$pid" ] && echo "$p $pid $(ps -o utime=,stime= -p "$pid" 2>/dev/null)"; done; }
{
  echo "=== cumulative-CPU delta over ${WINDOW}s (loaded state, not quiesced) ==="
  echo "build:  $(sw_vers -productVersion) $(sw_vers -buildVersion)"
  echo "start:  $(date '+%F %T %z')"
  echo "uptime: $(uptime)"
  echo
  echo "--- co-running /Applications bundles (the load context) ---"
  ps -Ao comm= | grep "^/Applications" | sed 's|/Contents/.*||; s|.*/||' | sort -u | tr '\n' ' '
  echo; echo
} > "$OUT"
snap > "$TMP/before"; T0=$(date +%s)
sleep "$WINDOW"
snap > "$TMP/after";  T1=$(date +%s); EL=$((T1-T0))
awk -v EL="$EL" '
  function secs(t,  a,n){ n=split(t,a,":"); return (n==3)? a[1]*3600+a[2]*60+a[3] : a[1]*60+a[2] }
  FNR==NR { pid[$1]=$2; b[$1]=secs($3)+secs($4); order[++k]=$1; next }
          { a[$1]=secs($3)+secs($4) }
  END {
    printf "%-22s %8s %12s %12s\n", "process","pid","cum_before","delta_%CPU"
    for(i=1;i<=k;i++){ p=order[i]
      if(!(p in a)) { printf "%-22s %8s %12s %12s\n", p, pid[p], "-", "DIED"; continue }
      printf "%-22s %8s %11.0fs %11.2f%%\n", p, pid[p], b[p], (a[p]-b[p])/EL*100 }
  }' "$TMP/before" "$TMP/after" >> "$OUT"
{ echo; echo "elapsed: ${EL}s"; echo "end:     $(date '+%F %T %z')"; echo "uptime:  $(uptime)"; } >> "$OUT"

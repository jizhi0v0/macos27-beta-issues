#!/bin/bash
# Retrospective 30-min log-rate baseline, matched to the windows already
# recorded for beta5 in issues/. `log` is a zsh builtin -- /usr/bin/log always.
OUT="$1"
L=/usr/bin/log
{
echo "=== 30-min retrospective log rates ==="
echo "build: $(sw_vers -productVersion) $(sw_vers -buildVersion)"
echo "taken: $(date '+%F %T %z')   window: --last 30m"
echo
echo "-- #19 imagent (recorded beta5: 6,522 CAS + 4,894 sandbox / 30 min) --"
printf "  ContactsAccountsService lines : %s\n" "$($L show --last 30m --predicate 'process == "imagent"' 2>/dev/null | grep -c ContactsAccountsService)"
printf "  sandbox/deny lines            : %s\n" "$($L show --last 30m --predicate 'process == "imagent"' 2>/dev/null | grep -ciE 'sandbox|deny')"
printf "  imagent total lines           : %s\n" "$($L show --last 30m --predicate 'process == "imagent"' 2>/dev/null | wc -l)"
echo
echo "-- #18 contactsd (recorded beta5: ~218k lines/h; contactsd itself ~45 'Could not fetch group' /30min) --"
printf "  contactsd total lines         : %s\n" "$($L show --last 30m --predicate 'process == "contactsd"' 2>/dev/null | wc -l)"
printf "  'Could not fetch group' BY contactsd : %s\n" "$($L show --last 30m --predicate 'process == "contactsd"' 2>/dev/null | grep -c 'Could not fetch group for change type')"
printf "  'Could not fetch group' ALL processes: %s   <-- do NOT attribute to contactsd\n" "$($L show --last 30m --predicate 'eventMessage CONTAINS "Could not fetch group for change type"' 2>/dev/null | grep -vc '/usr/bin/log')"
printf "  AddressBookManager spawns     : %s\n" "$($L show --last 30m --predicate 'process == "launchd"' 2>/dev/null | grep -c 'Successfully spawned AddressBookManager')"
echo
echo "-- #23 ecosystemd --"
printf "  ecosystemd total lines        : %s\n" "$($L show --last 30m --predicate 'process == "ecosystemd"' 2>/dev/null | wc -l)"
printf "  trustd total lines            : %s\n" "$($L show --last 30m --predicate 'process == "trustd"' 2>/dev/null | wc -l)"
echo
echo "-- #1 CoreMedia fpSupport (steady-state, NOT the post-boot window) --"
printf "  fpSupport_GetVideoRange lines : %s\n" "$($L show --last 30m 2>/dev/null | grep -c fpSupport_GetVideoRange)"
echo
echo "-- #3 WindowServer 'Invalid window' spam --"
printf "  Invalid window lines          : %s\n" "$($L show --last 30m 2>/dev/null | grep -c '_CGXPackagesSetWindowConstraints: Invalid window')"
echo
echo "-- #24 mds / CoreDuet --"
printf "  mds+mds_stores total lines    : %s\n" "$($L show --last 30m --predicate 'process == "mds" OR process == "mds_stores"' 2>/dev/null | wc -l)"
echo
echo "done: $(date '+%F %T %z')"
} > "$OUT" 2>&1

# Non-Chrome reproducer for the macOS 27 alert-notification click bug

Two tiny app bundles sharing **none of Chrome's code**, demonstrating that the failure in
[#26](https://github.com/jizhi0v0/macos27-beta-issues/issues/26) is a macOS defect that hits *any* app
using Apple's own "a separate helper process posts alert-style notifications" pattern.

- `NotifDemo.app` (`com.jizhi0v0.notifdemo`) — launches the helper with a `--from-parent` marker.
- `NotifDemoHelper.app` (`com.jizhi0v0.notifdemo.helper`) — posts one categorized notification, then
  evaluates Chromium's exact `OkayToTerminateService` predicate on its own `getDeliveredNotifications`
  and `exit(0)`s if the array is empty. Optionally refuses to run standalone, the way
  `Google Chrome Helper (Alerts)` does.

```bash
./build.sh          # builds + ad-hoc signs both, installs into ~/Applications
open ~/Applications/NotifDemo.app --args --tag CLICKA
cat ~/notifdemo.log
```

Click **Allow** on the first run. Results append to `~/notifdemo.log`.

## Measured on macOS 27.0 beta5 `26A5406e` (2026-08-12)

**The race hits a non-Chrome app every time — 14 / 14** `add()` cycles returned `count=0`, queried
0.35–2.23 ms *after* `add()`'s completion handler had already fired. So an app implementing this
entirely reasonable-looking idle check kills its own alerts helper 100 % of the time.

**The same binary takes the opposite branch on macOS 26.6** — the cleanest single comparison in this
investigation, since the query is issued at essentially the same instant on both:

```
macOS 26.6  25G72     OkayToTerminateService query: count=1 mineVisible=Y issued=+0.52ms replied=+2.38ms
                      DECISION: notifications.empty() == false -> returns NO  -> staying alive
macOS 27.0  26A5406e  OkayToTerminateService query: count=0 mineVisible=N issued=+0.49ms replied=+1.07ms
                      DECISION: notifications.empty() == true  -> returns YES -> exit(0)   (14/14)
```

Three click conditions, differing only in whether the helper survives a standalone relaunch:

| | helper alive at click? | `Received response` | forwarded? | `appDeath` on click | user-visible |
|---|---|---|---|---|---|
| **A** exits, refuses standalone (Chrome-faithful) | no | yes | **no** | **yes, +78 ms** | **click does nothing** |
| **B** exits, standalone allowed | no → relaunched | yes | **yes, +159 ms** | no | works |
| **C** stays alive | yes | yes | **yes, +2 ms** | no | works |

**Condition B is the point:** identical race, identical self-kill, and the click still lands — purely
because the relaunched instance stayed alive. macOS's relaunch recovery is sound in principle and
fails only for clients that cannot run standalone.

## Log-signature gotcha

`sent to NSUserNotification client` is a success signal **only on the legacy `NSUserNotification`
path** (which Chrome's helper uses). This demo registers on the *modern* UN path, where the
equivalents are `Notifying UserNotifications client <bundle>:<pid> about response` →
`Received … reply for response`, and the failure marker is
`Error  Failed to notify application with <bundle> for response`. The legacy clause never appears for
this demo **even in condition C where delivery worked**, so its absence proves nothing here. Note the
asymmetry: that `Failed to notify` error appears on the modern path but **0 times** across Chrome's
7-minute stuck window — Chrome's failure really is silent.

## Caveats

- Presentation style resolved to `alertStyle=1` (banner), not Chrome's Alerts; the response path is the
  same but this is not a byte-identical match.
- A/B/C are one click each; the 14/14 figure covers the race, not the click conditions.
- The macOS 26.6 arm covers the race/decision only (n=1, `count=1` → helper stays alive); the click
  conditions A/B/C were not re-run there, since with the helper alive there is nothing to test.
  The wider 26.6 control remains [`../un-delivered-race-probe/`](../un-delivered-race-probe/), 16/16 at 0 ms.
- Do not `pkill` the helper while its permission prompt is up — that permanently records a denial for
  the bundle id.

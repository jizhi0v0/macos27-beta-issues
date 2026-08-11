NOT YET POSTED. This is a COMMENT for the existing Chromium issue, not a new bug report:
  https://issues.chromium.org/issues/370536109
  "Push Notifications 'notificationclick' not handled in MacOS 15" — opened 2024-10-01, P2, still unfixed.

Why comment instead of filing new: that issue is the same user-visible bug (see its #5: "clicking may
even open a Chrome instance, but not the correct URL"), Google reproduced it in #12, and it sat
unexplained for 16 months until 2026-02-04 when notifications went to maintenance mode (P0/P1 only).
Nobody there found a root cause. Crucially, reporters in #22/#23 independently observed that
"when multiple notifications are present simultaneously, notificationclick becomes effective" — which
our mechanism explains exactly, and which is the strongest evidence it is the same defect.

A second, closely related issue worth watching: https://issues.chromium.org/issues/375640809
Companion Apple Feedback draft (the root cause side): feedback/un-getdeliverednotifications-race.md

--- comment text as posted ---

Root cause found, with a deterministic reproducer that needs no browser at all. I hit this on macOS 27.0 beta5 (26A5406e) with Chrome 151.0.7922.109 and traced it end to end. I cannot test macOS 15, so I can't prove it is the same defect there — but the mechanism explains the reporter observations in this thread, including the "multiple notifications make it work" effect in #22/#23, which I think is the strongest sign it is the same bug.

## The OS lies about what is displayed, and Chrome kills its Alerts helper on the answer

On macOS 27 beta5, after -[UNUserNotificationCenter addNotificationRequest:withCompletionHandler:] has ALREADY invoked its completion handler with no error, getDeliveredNotificationsWithCompletionHandler: still returns an EMPTY array for the next ~7-24 ms (median ~15 ms). On macOS 26.6 the notification is visible to the very first query, issued 10-30 microseconds after that same callback, with zero misses.

Measured with a ~50-line standalone Swift app, 32 trials per OS across two passes:

                          macOS 27.0 beta5      macOS 26.6
  visible at 0 ms              0 / 16            16 / 16
  visible at 5 ms              0 / 16            16 / 16
  visible at 10 ms             5 / 16            16 / 16
  visible at 15 ms            10 / 16            16 / 16
  visible at 25 ms            16 / 16            16 / 16
  first-visible (serial)   7.1 / 15.4 / 23.7 ms   0.01-0.03 ms

That is precisely the condition MacNotificationServiceUN::OkayToTerminateService treats as "safe to terminate":

    GetDisplayedNotifications(
        /*profile=*/nullptr, /*origin=*/std::nullopt,
        base::BindOnce([](std::vector<mojom::NotificationIdentifierPtr> notifications) {
          return notifications.empty();
        }).Then(std::move(callback)));

So when that check lands inside the window, Chrome tears down Google Chrome Helper (Alerts).app while its own notification is still on screen. Observed helper lifetimes after posting on beta5: 42 ms and 140 ms (against 3.3 s / 19 s / 39 s / 165 s in runs where the check landed outside the window; on macOS 26.6 the helper simply stays alive as long as a notification is outstanding - I watched one live for 13 minutes).

Once the helper is gone, the click is unrecoverable. usernoted does receive it and does try to relaunch the registered client via LaunchServices, but a Chromium helper launched with no arguments exits immediately by design. Over one 7-minute stuck window:

    clicks received by usernoted ("Received response") : 61
    Alerts-helper appDeath events                      : 60   <- one relaunch-and-die per click
    clicks forwarded to the client                     :  2

usernoted even logs "Foreground launch ... successful" against a process that has already exited, then discards the click with no error on the legacy NSUserNotification path Chrome uses. This is the part that matches "clicking may even open a Chrome instance, but not the correct URL" from #5: the OS-level app activation still happens, the notificationclick event never does.

## Why it is ~50% and not always, and why multiple notifications "fix" it

CheckIfServiceCanBeTerminated() in notification_dispatcher_mojo.cc is event-driven and is never called on SHOWING a notification. It fires from the constructor, CloseNotificationWithId, CloseNotificationsWithProfileId, OnNotificationAction, the empty-reply dispatchers, and the restart timer. So the check lands at an arbitrary offset from the last add() - usually seconds later, when the notification is long since visible, and nothing bad happens; occasionally a few ms later, inside the window, and the helper dies.

That directly explains #22 / #23: with several notifications outstanding, getDeliveredNotifications is non-empty even while the newest one is still inside its window, so OkayToTerminateService returns false, the helper survives, and clicks work. It is not that multiple notifications fix anything - they just keep the array non-empty.

It also explains why clicking one notification can break a different one: OnNotificationAction() forces an immediate termination check, so interacting with notification A can kill the helper on behalf of notification B that was posted moments earlier and is still invisible to the query.

## Chrome can fix this without waiting for Apple

I built a two-bundle demo sharing none of Chrome's code, emulating this architecture: a helper posts one notification, evaluates the exact OkayToTerminateService predicate, and exits if empty. On beta5 its own post-add query returned count=0 in 14/14 trials (queried 0.35-2.23 ms after add()'s completion fired), so it killed itself every time. On macOS 26.6 the same binary got count=1 at +0.52 ms and stayed alive.

Then three click conditions, differing ONLY in whether the helper survives a standalone relaunch:

    A  exits, refuses standalone launch (Chrome-faithful)  ->  click dropped, relaunch dies +78 ms
    B  exits, standalone launch allowed                    ->  click DELIVERED +159 ms
    C  stays alive                                         ->  click delivered +2 ms

Row B is the actionable result: identical OS race, identical self-termination, and the click still lands - purely because the relaunched process stayed alive. So either of these is sufficient:

1. Don't treat a single empty getDeliveredNotifications result as authoritative moments after this process's own add() reported success (re-check, or suppress termination within a short window of a successful add()). macOS 26 never trips this, so a guard costs nothing there.
2. Let the Alerts helper survive an argument-less relaunch and re-register as a notification client, so the OS's existing recovery path can work.

## Reproducing the user-visible bug

Real Web Push (which wakes the service worker from suspension) triggers it far more reliably than calling showNotification() from an open page - roughly 4 of 7 notifications on beta5 vs 1 of 10 for the open-page path. Send a push with requireInteraction: true plus an actions entry so it goes down the Alerts path, wait a few seconds until `ps aux | grep "Chrome Helper (Alerts)"` shows it gone, then click. Signature while stuck:

    log show --predicate 'process == "usernoted"' --info --debug --last 5m | grep -c "Received response"
    log show --predicate 'process == "usernoted"' --info --debug --last 5m | grep -c "sent to NSUserNotification client"

The first count rises with every click; the second stays flat. Trigger any new Chrome notification, or restart Chrome, and every backlogged notification becomes clickable again at once.

Full investigation, raw logs, and both standalone reproducers (the getDeliveredNotifications probe and the non-Chrome demo):
https://github.com/jizhi0v0/macos27-beta-issues/issues/26

Caveats, stated plainly: my two machines are different hardware (M3 Max laptop on beta5, M4 mini on 26.6), though the confound runs opposite to the effect and a ~1000x gap is not a CPU difference; the probe cannot distinguish "not yet delivered" from "delivered but the query serves a stale snapshot"; and I have no macOS 15 machine, so the link to the original report here is by mechanism, not by direct measurement.

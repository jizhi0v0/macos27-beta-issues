# Chrome notification banner freezes: no auto-dismiss, swipe-to-dismiss and click both do nothing (other apps' banners unaffected)
# Chrome 通知横幅卡死：不会自动消失，右滑关闭和点击均无反应（其他 app 的通知不受影响）

> 🔗 **Track / 关注此问题:** [#26 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/26)

| | |
|---|---|
| **Status** | 🔴 Reproducible on demand — present on beta4 `26A5388g`, still present on beta5 `26A5406e` (2026-08-11) |
| **macOS** | 27.0 beta4 `26A5388g` → beta5 `26A5406e` (first noticed on beta4; machine has since moved to beta5, still reproduces) |
| **Component** | Apple Notification Center (banner interaction) ↔ Google Chrome web-push notifications |
| **Chrome** | `151.0.7922.109` (Official Build) (arm64) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

A Chrome notification banner (web-push style, e.g. a YouTube channel notification) appears and then **never goes away on its own**, and cannot be dismissed or acted on by the user:

- **No auto-dismiss.** The banner stays on screen indefinitely — confirmed still present after several minutes, well past the few seconds a banner normally lives for.
- **Swipe-to-dismiss does nothing.** The normal right-swipe gesture on the banner has no effect — it doesn't slide, doesn't reveal the clear/options controls, doesn't dismiss.
- **Click does nothing.** Clicking the banner neither dismisses it nor activates it (no tab focus, no navigation to the linked page).
- **Other apps are unaffected.** Notifications from other apps (e.g. Facebook) arriving on the same machine around the same time behave normally — auto-dismiss, swipe, and click all work.

一条 Chrome 的网页推送通知横幅（例如 YouTube 频道通知）弹出后**不会自动消失**，也**无法用任何方式处理**：不会自动隐去（观察到持续挂在屏幕上数分钟，远超正常横幅几秒的存活时间）；**右滑**（标准的关闭手势）没有任何反应，不滑动、不弹出清除/选项控件；**点击**同样没有反应，既不关闭也不跳转到对应网页。同一时间段其他 app（例如 Facebook）的通知一切正常——自动消失、右滑、点击都能用。

## Evidence / 证据

User-observed on two occasions, both showing the same YouTube/Chrome banner ("iOS 27 has reduced the Liquid Glas…", subtitle "For you: Beta Profiles") stuck on screen — first noticed on beta4, reproduced again after updating to beta5 `26A5406e` (2026-08-11).

### Not the same as Chrome's generic "site updated in background" notification / 不是 Chrome 的通用「后台更新」占位通知

The same Notification-Center session also showed an unrelated, separate Chrome notification — `www.youtube.com` / **"This site has been updated in the background."** — which is Chrome/Chromium's own generic fallback text for a **silent push**: the site's service worker received a push event but didn't call `showNotification()` (or didn't await its promise) in time, so Chrome is forced to show *some* notification per the Push API spec, with no real title/body/target of its own (see [Pushpad's explainer](https://pushpad.xyz/blog/this-site-has-been-updated-in-the-background)). Clicking that one just focuses Chrome and does nothing else — but that's expected for this notification type, since it carries no destination. **That is not the stuck one.**

### The actual stuck notification, decoded from the Notification Center database / 从通知数据库里解出的、真正卡住的那条

macOS still maintains the legacy per-user notification store at `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (SQLite) on this beta5 machine — confirmed present and actively being written (`db-wal` timestamp updating in real time). Schema: `app`, `record`, `delivered`, `displayed`, `requests`, `snoozed` (`delivered`/`displayed`/`requests`/`snoozed` are one row per `app_id`, each holding a BLOB — empirically a packed list of the notification UUIDs currently in that state for that app; this schema is private/undocumented by Apple, so this reading is inferred from field names and observed behavior, not from official docs).

```
$ sqlite3 "$DB" "SELECT app_id, identifier FROM app WHERE identifier LIKE '%chrome%';"
65|com.google.chrome
66|com.google.chrome.framework.alertnotificationservice   ← Chrome's actual XPC notification-posting identifier

$ sqlite3 "$DB" "SELECT rec_id, app_id, datetime(request_date+978307200,'unixepoch','localtime'), presented FROM record WHERE app_id IN (65,66);"
143413|66|2026-08-11 18:01:00|0
```

That is the **only** Chrome record left in the `record` table (out of 439 rows total, spanning all apps) — every other Chrome/YouTube/Instagram notification from the same session has already aged out normally. Decoding `record.data` (a `bplist00`/NSKeyedArchiver blob) for `rec_id=143413`:

```
title:    www.youtube.com
subt:     For you: Beta Profiles
body:     iOS 27 has reduced the Liquid Glass button blur so much that it's basically gone. #ios27
dest:     https://www.youtube.com/
```

This **is** the "iOS 27 has reduced the Liquid Glass…" banner from the screenshots, confirming it's a normal, well-formed notification **with a real destination URL** — not a contentless placeholder. Yet clicking it does not open that URL, and it does not dismiss.

Both the `delivered` and `displayed` per-app BLOBs for `app_id=66` decode to exactly **one 16-byte UUID**, `B8F0A752-EE32-4556-A534-3C144C72C2AB` — matching `record 143413`'s UUID exactly, and nothing else:

```
$ xxd delivered_66.bin
00000000: b8f0 a752 ee32 4556 a534 3c14 4c72 c2ab  ...R.2EV.4<.Lr..
$ xxd displayed_66.bin
00000000: b8f0 a752 ee32 4556 a534 3c14 4c72 c2ab  ...R.2EV.4<.Lr..
```

I.e. **macOS's own bookkeeping still considers this specific notification "delivered" and "displayed"**, while its sibling Chrome notifications from the same session (the two Instagram ones, the "site updated in background" one) have already cleared from these same per-app lists as expected. That's independent, DB-level corroboration of "stuck" — it's not just a rendering glitch on top of an otherwise-resolved notification; the system's own live-notification tracking agrees this one is still open. (`presented=0` on this record is **not** anomalous by itself — most recently-arrived records from unrelated apps show the same value; only the delivered/displayed persistence is the distinguishing signal.)

This narrows where the bug likely sits: Chrome handed macOS a well-formed notification with a real payload and destination, and macOS accepted and is still tracking it as live — so the failure looks like it's on the **receiving/interaction side** (`usernoted` / `UserNotificationCenter.app` banner UI / `NotificationCenter.app`), not in what Chrome sent. Not proven — see open questions.

## Relationship to the older "click doesn't navigate" Sequoia bug / 和旧的「点击不跳转」bug 的关系

This is **not** the same bug as the long-standing macOS 15 Sequoia-era issue where clicking a Chrome notification failed to open/navigate to the linked page (that one is well documented externally, e.g. [MacRumors: "Chrome Notifications not clickable"](https://forums.macrumors.com/threads/chrome-notifications-not-clickable.2432947/), first reported on Sequoia 15.1 beta in 2024-08 and still unresolved as of 2025-03). The reporter's own prior testing found that older bug **fixed as of macOS 26 beta2**.

What's being tracked here is a **different, stronger failure**: the banner doesn't just fail to navigate on click — it fails to respond to *any* interaction at all (click **or** swipe) and never times out. Whether this is a regression of the same underlying Chrome-banner-interaction code path, or an unrelated new Notification Center defect, is an open question (see below).

这**不是**长期存在的 macOS 15 Sequoia 那个「点击 Chrome 通知不跳转」的老 bug（那个问题外部已有大量记录，例如 [MacRumors 帖子](https://forums.macrumors.com/threads/chrome-notifications-not-clickable.2432947/)，2024-08 Sequoia 15.1 beta 就有人报告，到 2025-03 依然没解决）；记录者自己此前的测试认为那个老 bug **在 macOS 26 beta2 已经修复**。这里记录的是一个**更严重的新现象**：不只是点击不跳转，而是**点击和右滑都完全没反应**，且横幅永不自动消失。这是否是同一条 Chrome 通知交互代码路径的回归，还是 Notification Center 一个新的独立缺陷，目前还不确定（见下方待定问题）。

## What's ruled out so far / 已排除

- **Not a general Notification Center outage.** Instagram notifications (also delivered through Chrome, `www.instagram.com`) in the same session dismiss/clear normally and are gone from the DB's `delivered`/`displayed` lists — so neither Notification Center nor Chrome's notification pipeline is globally frozen.
- **Not a malformed/contentless payload.** The stuck record decodes to a well-formed notification with title/subtitle/body and a real `https://www.youtube.com/` destination — ruling out "it's stuck because it has nothing to act on."
- **Not the same thing as Chrome's "This site has been updated in the background" placeholder** — that's a separate, expected-behavior notification from silent-push handling (see above), not this bug.

## Mitigation / 缓解

No confirmed fix. Two untested candidates worth trying next time it's stuck (both are safe/reversible — `launchd` respawns them):

```
killall UserNotificationCenter   # the on-screen banner-rendering process
killall NotificationCenter       # the Notification Center list panel
```

未验证是否能清掉卡住的横幅，但都是安全可逆的操作（`launchd` 会自动重启这两个进程），下次卡住时可以试试。

## Open questions / 待定

1. Does this reproduce with **Safari** or other browsers' web-push notifications, or is it Chrome-specific? Note: Safari doesn't proactively prompt for notification permission — a site must call `Notification.requestPermission()` (or the legacy `window.safari.pushNotification.requestPermission()`) from a user gesture on the page itself (see [Apple's Safari Push Notifications guide](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/NotificationProgrammingGuideForWebsites/PushNotifications/PushNotifications.html)); merely being logged into a site doesn't grant it. Check existing grants under **Safari ▸ Settings ▸ Websites ▸ Notifications**. YouTube specifically may not even offer a subscribe/bell UI that triggers this in Safari — that's the site's own feature-detection, not something controllable from Safari's settings.
2. Does it reproduce with a **native macOS alert-style** notification from Chrome (not web-push), to isolate whether the trigger is the web-push delivery path specifically?
3. Is the banner's underlying process actually hung, or is only *this specific notification's* interaction target broken while the rest of Notification Center stays live? (Try swiping/clicking a *different, newer* banner while the stuck one is still on screen — from the DB evidence above, other Chrome notifications in the same session did clear normally, which already leans toward "just this one," not a global hang.)
4. Does `killall UserNotificationCenter` / `killall NotificationCenter` clear the stuck banner and its DB record, and does it recur on the next YouTube notification?
5. Exact **build-to-build window**: only confirmed present on beta4 → beta5 so far; beta1–beta3 not yet retested.
6. Is there anything distinguishing about *this* notification's payload vs. a normal one that clears fine (e.g. the `subt` field, or the `r|Default|p#https://www.youtube.com/#15drvHdY13tY` action-URL encoding) that could point at a parsing edge case?

# ToDesk "repeated logout" is actually a 10-second crash-loop (`ToDesk_Session_Proxy`)
# ToDesk「反复退出登录」真相：ToDesk_Session_Proxy 每 10 秒崩一次的崩溃循环

| | |
|---|---|
| **Status** | 🟡 Mitigated (disabled the daemons) — app-side bug, not Apple framework |
| **macOS** | 27.0 beta (`26A5353q`) |
| **Component** | **ToDesk 4.9.7.1 (build 2017)** — `ToDesk_Session_Proxy` (uses Breakpad) |
| **Report** | ToDesk vendor support (no public GitHub tracker) |

## Symptom / 症状

ToDesk appears to **repeatedly log out and auto-log back in**. Reproduced after updating 4.8.8.1 → 4.9.7.1 (no change).

ToDesk 表现为**频繁登出又自动登入**。从 4.8.8.1 升到 4.9.7.1 后依旧。

## Root cause / 真相

`ToDesk_Session_Proxy` registers for "screen lock / session logout" notifications, then **crashes (Breakpad) ~10s later**. `launchd` `KeepAlive` immediately relaunches it → a **crash-loop every ~10 seconds**, which manifests in-app as the login bouncing.

`ToDesk_Session_Proxy` 注册「屏幕锁定/会话注销通知」后约 10s 崩溃（Breakpad），launchd KeepAlive 立刻拉起重连 → **每 10 秒一轮的崩溃循环**，表现成登录反复掉线。

## Evidence / 证据

- `/Library/Application Support/ToDesk/dumps` accumulated **50,000+ dumps, ~55 GB**.
- Because ToDesk ships its own **Breakpad**, these crashes do **not** appear in `~/Library/Logs/DiagnosticReports` — easy to miss.

## Workaround / 临时规避

Stop the daemons (then clean the dumps):

```bash
sudo launchctl bootout  system/com.youqu.todesk.service
sudo launchctl disable  system/com.youqu.todesk.service
launchctl bootout gui/501/com.youqu.todesk.desktop
launchctl bootout gui/501/com.youqu.todesk.client.startup
# then delete /Library/Application Support/ToDesk/dumps/*
```

⚠️ **Reopening the ToDesk app self-heals/re-registers** (it has a privileged `UninstallerHelper`). So this is "keep it disabled until a compatible build." To use ToDesk again: `launchctl enable` those three labels, then launch.

⚠️ 重开 ToDesk app 会自愈重注册，所以是「先停着等兼容新版」。要再用先 `launchctl enable` 那三个 label 再开。

## Notes / 备注

Likely a beta-triggered crash in the session/notification path; report to ToDesk vendor with a dump sample.

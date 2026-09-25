# CoreMedia `fpSupport_GetVideoRangeForCoreDisplayWithPreference` loop floods `logd`
# CoreMedia 查显示色域死循环刷爆 logd / 多个 WebKit app 后台空转

> 🔗 **Track / 关注此问题:** [#1 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/1)

| | |
|---|---|
| **Status** | 🟡 **still emitting on 27.2 beta2 `26B5091g`, still not decidable** (2026-09-25) — **54** records in a 10-minute window, **WeType / Safari / Mail, 18 each** (release: 74, all DingTalk). The signature exists on this build too; the trigger is app-dependent and the app mix changed again, so the count measures the apps, not the OS. See [`../baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md). Prior: 🟡 **still emitting on release `26A428`, still not decidable** (2026-09-16) — **74** records in a 10-minute window, **all DingTalk** (beta8: 54 from Mail / DingTalk / DuoUpdater / textunderstandingd). The loop's signature exists on the shipped build, but the trigger is app-dependent and the app mix is still uncontrolled, so neither this rise nor beta8's fall measures the OS. See [`baselines/release-26A428/`](../baselines/release-26A428/README.md). Prior: 🟡 **quiet again on beta8 `26A5425a`, and still not creditable as a fix** (2026-09-03) — **54** records in a 10-minute window (~324/h), emitters Mail 20 / DingTalk 16 / DuoUpdater 12 / textunderstandingd 6. WeType and Raycast, beta7's two largest emitters, are **absent**. The trigger is app-dependent, so a lower count under a changed app mix measures the app mix, not the OS — the same non-verdict as beta7. Prior: 🟡 **much quieter on beta7 `26A5421a` — but not creditable as a fix** (2026-08-27). **219** `fpSupport_GetVideoRange` records in the 8-minute post-boot window against beta5's **1,744** in its own 8-minute window, a ~8× drop. The emitter set changed too, though: WeType 1,095 / DingTalk 978 / Raycast 358 / DuoUpdater 78 across the session, against beta5's DingTalk 1,338 / WeType 263 / Mail 136 — Raycast and DuoUpdater are new emitters absent from the beta5 tally. The trigger is app-dependent and the app mix was **not controlled**, so this measures the app mix, not the OS. See *Retest 2026-08-27* below. Prior: 🟡 Mitigated (workaround) — present in beta1 **and** beta2; ⚪ not reproduced in a beta3 `26A5378j` window (conditional trigger) |
| **macOS** | 27.0 beta2 `26A5368g` (also beta1 `26A5353q`) |
| **Component** | Apple **MediaToolbox / CoreMedia** (`com.apple.coremedia`) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, single built-in Liquid Retina XDR display |
| **Report** | Apple Feedback: **`FB23411581`** (filed 2026-06-26, Displays & Graphics → Incorrect/Unexpected Behavior; sysdiagnose + 90s flood capture attached) |

## Symptom / 症状

Shortly after boot (and after launching certain apps), `logd` burns ~20% CPU sustained and several **unrelated WebKit/Electron-based apps** show elevated background CPU **with no UI rendering**. The common cause is a tight loop inside CoreMedia querying the display's HDR video range, logged at *default* level (so `logd` persists every line to disk).

开机后不久，`logd` 持续吃 ~20% CPU，多个**互不相关的 WebKit/Electron app** 在没有任何 UI 渲染的情况下后台 CPU 偏高。根因是 CoreMedia 在死循环查显示器 HDR 色域，且日志是 default 级别（会被 logd 落盘）。

## Evidence / 证据

Identical log line emitted ~16×/sec **per app**, by four unrelated apps at once:

```
<<<< Alt >>>> fpSupport_GetVideoRangeForCoreDisplayWithPreference: displayID 1 reported
potentialHeadRoom=16 wideColorSupported=YES marz=NO almd=NO deviceAllowsHDR=YES
isBuiltinPanel=YES externalPanel=YES prefersHDR10=NO
```

`log show --last 60s` — emitters of this exact signature (≈2400 lines/60s total):

| process | lines/60s | kind |
|---|---|---|
| WeType (微信输入法 / Tencent input method) | 960 | input method, no window |
| DingTalk (钉钉) | 952 | Electron chat |
| Bob (translation app) | 480 | WebKit |
| Mail | 14 | WebKit content |

- **Tell-tale bug**: `externalPanel=YES` is reported even though the machine has **only the internal panel** — the parameters themselves are wrong, pointing at a framework regression, not the apps.
- `logd` cumulative CPU: 2:35 at 13 min uptime (≈20% avg). The flood is **post-boot / app-init transient** — it quiesced to 0 lines/30s by ~21 min uptime, and `logd` dropped back to ~1.6%.


## Retest 2026-08-11 — beta5 `26A5406e` — STILL PRESENT, and it no longer decays / 仍在,且不再衰减

Captured in a **deliberate post-boot window** — the reason this entry sat at ⚪ for three builds is that the earlier retests simply never looked in the first minutes after a boot. This time the machine was rebooted specifically to catch it.

`log show --start <boot>` over the first 8 minutes: **1,744 hits**, emitters exactly as originally documented —

| process | hits | toolkit |
|---|---|---|
| **DingTalk** | 1,338 | Electron |
| WeType | 263 | — |
| Mail | 136 | WebKit content |
| textunderstandingd | 3 | — |

Per-minute rate: `0.7 → 4.2 → 4.1 → 2.5 → 4.6 → 6.3 → 4.2 → 2.1 /s`.

**Two differences from the beta1/beta2 description:**

1. **Lower rate** — ~2–6/s aggregate here, against "~16/sec **per app**" originally. `logd` costs **2.38%** cumulative since boot, against the ~20% originally recorded.
2. **It does not die down.** The original write-up says the loop runs "then dying down after a few minutes". At 8 minutes in it was still emitting 2–6/s with no downward trend. Whatever throttling produced the original decay is either absent or operating on a longer timescale.

**Net: not fixed.** The ⚪ that stood since beta3 was a missed observation window, not evidence of a fix — a distinction this ledger has had to make more than once.

2026-08-11 于 beta5 专门重启后取样:**仍复现**,8 分钟内 1,744 次,发出者与原记录一致(钉钉 1,338 为最大来源)。两点差异:**速率更低**(合计 ~2–6/秒,原为"每个 app ~16/秒"),`logd` 仅 **2.38%**(原 ~20%);但**不再衰减** —— 原文称"几分钟后自行衰减",而 8 分钟后仍稳定在 2–6/秒。**结论:未修复**;此前三个 build 的 ⚪ 是**错过了观测窗口**,不是修复的证据。

## Reproduction / 复现

1. Boot into macOS 27 beta2.
2. Launch any mix of WebKit/Electron apps with a window doing color/HDR queries (input methods, Electron chat apps, WebKit browsers/translators).
3. `sudo log stream --predicate 'eventMessage CONTAINS "fpSupport_GetVideoRangeForCoreDisplay"'` — observe ~16/sec per app, then dying down after a few minutes.

## Workaround / 临时规避

- **Quit the WebKit/Electron apps you aren't using** — the loop only runs in live processes (biggest offender here: DingTalk).
- **Cap the `logd` cost** (reversible, needs root; resets on reboot):
  ```bash
  sudo log config --subsystem com.apple.coremedia --mode "level:off"      # silence
  sudo log config --subsystem com.apple.coremedia --mode "level:default"  # restore
  ```
- It self-settles within minutes of boot, so for many users no action is needed.

## Notes / 备注

- The signature `fpSupport_GetVideoRangeForCoreDisplayWithPreference` is a WebKit/WebProcess display-capability log (also seen historically in Electron apps, e.g. loft-sh/devpod#302), confirming the common path is web-content display/HDR detection.
- The `<<<< Alt >>>>` prefix is CoreMedia's internal subsystem tag — unrelated to the AltTab app.

**Retest 2026-06-26 beta2 26A5368g:** CONFIRMED — uptime 39 min; `log show --last 60s` = 1192 lines of `fpSupport_GetVideoRangeForCoreDisplayWithPreference`, all `externalPanel=YES` (wrong param, machine has only internal panel). Per-app rate: WeType[910] 480/60s (~8/s), DingTalk[2782] 472/60s (~8/s), Bob[1000] 240/60s (~4/s); Mail not emitting this run. logd 0.8% / 3:30 cum at sample. Still active well past boot, not self-settled.

**Retest 2026-07-07 beta3 26A5378j:** ⚪ not reproduced this window — **0** `fpSupport_GetVideoRange…` lines since boot (07:53, ~2.5 h). Conditional signature (needs a WebKit/WebProcess client doing display/HDR capability detection); none of the emitting apps hit the path in this window. "Not reproduced," not "confirmed fixed" — recheck with the WebKit apps active.

## Retest 2026-08-27 — beta7 `26A5421a` — much quieter, but the emitter mix changed too

Measured on the 2026-08-27 13:39:10 boot, three days into the build (beta7 was installed
**2026-08-24 23:33** per `InstallHistory.plist` — the Aug 21 mtime on the system files is the
image build date, not the install date). Raw counts and the capture caveats are in
[`baselines/beta7-26A5421a/`](../baselines/beta7-26A5421a/README.md).

**219** `fpSupport_GetVideoRange` records in the 8-minute post-boot window, against beta5's
**1,744** in its own 8-minute window — a ~8× drop on the same measurement.

That looks like an improvement and is **not claimed as one**, because the emitters are not the
same set:

| | beta5 `26A5406e` (8 min) | **beta7 `26A5421a`** (whole 1 h 50 m session) |
|---|---|---|
| | DingTalk 1,338 | WeType 1,095 |
| | WeType 263 | DingTalk 978 |
| | Mail 136 | Raycast 358 |
| | | DuoUpdater 78, textunderstandingd 15, Mail 11 |

The trigger is app-dependent — this issue's own root-cause section attributes it to WebKit-hosting
apps — so a lower count under a different app mix measures the app mix, not the OS. WeType and
DingTalk swapped ranks, and Raycast and DuoUpdater are new emitters that were not in the beta5
tally at all. Settling this needs the same apps running, which was not controlled here.

2026-08-27 beta7 复测:开机后 8 分钟窗口 **219** 条,对比 beta5 同样窗口的 **1,744** 条,降了约 8 倍。
**但不据此判定改善** —— 发射方构成变了:beta5 是 DingTalk 1,338 / WeType 263 / Mail 136,
本次(整段 1 小时 50 分)是 WeType 1,095 / DingTalk 978 / Raycast 358 / DuoUpdater 78 …
Raycast 和 DuoUpdater 在 beta5 的统计里根本不存在。触发与 app 相关,app 组合没控住,这个数就只测到了 app 组合。

## Re-verification 2026-09-03 — beta8 `26A5425a` — quiet again, still not creditable as a fix

> **Clock position, because it decides what these numbers can be compared to.** beta8
> `26A5425a` was installed **2026-09-02 04:57:15** (`InstallHistory.plist`). Every figure below
> was taken at **T+21h20m** on the 2026-09-02 12:55:26 boot — a **steady-state** window, not the
> post-boot window beta6 (T+9m) and beta7 (T+0→8m) used. Log *volumes* are therefore **not**
> matched pairs with those builds and are not presented as such. Kernel unchanged for a third
> beta: `xnu-13432.1.9~3`. Raw capture: [`baselines/beta8-26A5425a/`](../baselines/beta8-26A5425a/README.md).

**54** records in the 10-minute window (~324/h). Emitters:

| process | records |
|---|---|
| Mail | 20 |
| DingTalk | 16 |
| DuoUpdater | 12 |
| textunderstandingd | 6 |

**WeType (1,095) and Raycast (358), beta7's two largest emitters, are absent entirely.** The
trigger is app-dependent, so a lower count under a changed app mix measures the app mix, not the
OS — the identical reason beta7's 8× drop was not credited. Until the app set is controlled
(the same discipline `tools/ws-idle-baseline.sh` imposes for #3), this issue cannot be closed on
a count.

2026-09-03 beta8 复测:10 分钟 **54** 条(~324/小时),发出者为 Mail 20 / DingTalk 16 /
DuoUpdater 12 / textunderstandingd 6。**beta7 的两个头号发出者 WeType 与 Raycast 这次完全没有出现**。
触发条件依赖 app,因此在 app 组合变化的前提下计数下降**衡量的是 app 组合而非 OS** —— 与 beta7
不予采信的理由完全相同。app 集合未受控之前,本条不能靠计数关闭。

## Re-verification 2026-09-16 — release `26A428` — still emitting, still not decidable

> **Clock position, because it decides what these numbers can be compared to.** The release
> build `26A428` was installed **2026-09-11 04:28:46** (`InstallHistory.plist`). Every figure below
> was taken at **T+6h29m** on the 2026-09-16 11:40:46 boot with ~40 apps running — matched neither
> to beta8's T+21h20m window nor to beta6/beta7's post-boot windows, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.1.9~1` (beta6–beta8: `~3`). Raw capture:
> [`baselines/release-26A428/`](../baselines/release-26A428/README.md).

**74** `fpSupport_GetVideoRange` records in the 10-minute window 18:09–18:19, and an unpinned
predicate re-query agrees at 74. Every one came from **DingTalk**.

| emitter | beta8 (10 min) | **release (10 min)** |
|---|---|---|
| DingTalk | 16 | **74** |
| Mail | 20 | — |
| DuoUpdater | 12 | — |
| textunderstandingd | 6 | — |

DuoUpdater was running and busy during this window (33,142 log records of its own) and emitted none
of these; DingTalk alone did. That fits the app-dependent trigger this issue has always described, and it is also exactly why
the count cannot be credited either way: the emitter set changes from build to build with what the
apps happen to be doing. The signature is **present on release**; whether the OS got better or worse
is not measurable without a controlled app set.

2026-09-16 正式版 `26A428` 复测:10 分钟窗口 **74** 条,**全部来自钉钉**(beta8 为 54 条,来自 Mail/钉钉/
DuoUpdater/textunderstandingd),谓词复查一致。DuoUpdater 当时在运行且很活跃(自身 33,142 条日志),但一条都没发出。
**正式版上该签名仍在**;但触发依赖 app、app 组合仍未受控,数量升降都**不能归因于 OS**。

## Re-verification 2026-09-25 — 27.2 beta2 `26B5091g` — still emitting, still not decidable

> **Clock position, because it decides what these numbers can be compared to.** macOS 27.2 beta2
> `26B5091g` was installed **2026-09-25 07:08:18 UTC** (`InstallHistory.plist`), two minutes after
> the 15:06:19 +0800 boot. The window is **T+1h54m → T+2h04m** with 32 apps running and the
> post-update reindex still active — matched to no earlier window, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.40.162~92` (release: `xnu-13432.1.9~1`). Raw capture:
> [`baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md).

`fpSupport_GetVideoRangeForCoreDisplayWithPreference` in the 10-minute window 17:00:09–17:10:09:
**54** records, the unpinned predicate cross-check agreeing (54).

| emitter | beta8 | release | **27.2 b2** |
|---|---|---|---|
| total | 54 | 74 | **54** |
| by process | Mail / DingTalk / DuoUpdater / textunderstandingd | DingTalk 74 | **WeType 18 / Safari 18 / Mail 18** |

DingTalk was not running this time; WeType and Safari are new emitters. The loop's signature is
present on 27.2 beta2, which rules out "the code path is gone", but with the emitter set changing
every build the count cannot be credited to or against the OS. **The status stays 🟡.**

2026-09-25 27.2 beta2 `26B5091g` 复测:窗口内 54 条,WeType / Safari / Mail 各 18 条(release 为 74 条、全是
钉钉)。签名仍在,但触发取决于 app,且 app 组合又变了,不能归因到系统。仍记 🟡。

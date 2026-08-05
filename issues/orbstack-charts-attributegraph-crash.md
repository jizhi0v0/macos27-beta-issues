# OrbStack crash: SwiftUI Charts → `AttributeGraph` extended-attribute alloc abort
# OrbStack 崩溃：SwiftUI Charts 触发 AttributeGraph 属性分配失败 abort

> 🔗 **Track / 关注此问题:** [#5 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/5)

| | |
|---|---|
| **Status** | 🟢 **Fixed by the vendor in OrbStack 2.2.2** (2026-08-02), confirmed by the author 2026-08-03. Last actually observed on **beta1 only**; never reproduced afterwards, and the reason for that silence was never isolated — see [Resolution](#resolution--结论如何收场) |
| **macOS** | seen on 27.0 beta1 `26A5353q`; resolved app-side while beta4 `26A5388g` was current |
| **Component** | Apple **SwiftUI / AttributeGraph** ↔ OrbStack **2.2.1 (20628)** (non-MAS); fixed in **2.2.2 (20903)** |
| **Hardware** | `Mac15,11`, M3 Max, 36 GB |
| **Report** | Upstream: [orbstack#2526](https://github.com/orbstack/orbstack/issues/2526) · Apple Feedback: `FB________` |

## Symptom / 症状

After OrbStack's GUI has been running for a while (~2h50m, reliably), the app aborts. The crash is inside SwiftUI Charts rendering the usage chart — `AttributeGraph` fails to allocate an extended attribute table and calls `abort()`.

OrbStack GUI 正常运行一段时间后（约 2h50m，稳定复现）崩溃。崩在 SwiftUI Charts 渲染使用率图表时——`AttributeGraph` 扩展属性表分配失败 → `abort()`。

## Evidence / 证据

Crash originates in Apple's `AttributeGraph` / SwiftUI Charts stack, not OrbStack logic. OrbStack author **kdrag0n** (2026-06-13) confirmed it's a SwiftUI/framework bug, could not reproduce it himself, and recommended filing with Apple.

## Workaround / 临时规避

**Don't sit on the charts view for hours.** The specific screen is the sidebar's **General → Activity Monitor** view — its bottom four panels (Total CPU / Memory / Network / Disk) are live SwiftUI Charts time-series that continuously re-render and accumulate AttributeGraph attributes. Switch back to any static list page (Containers / Images / Volumes / Pods / Machines) when done; those don't draw the live charts.

具体界面是左侧栏 **General → Activity Monitor**：底部四块 Total CPU / Memory / Network / Disk 面板是 SwiftUI Charts 实时曲线，持续重绘会累积 AttributeGraph 属性 → 几小时后 abort。看完切回任意静态列表页（Containers/Images/Volumes/Pods/Machines）即可绕过；别把 OrbStack 长期停在 Activity Monitor 这一屏。

## Notes / 备注

- Confirmed still present on beta2 by inference (no SwiftUI Charts fix in beta2 changelog); explicit beta2 reproduction TODO.
- issue #2526 kept open as an anchor to track across betas.

**Retest 2026-06-26 beta2 26A5368g:** HOLD / NO FRESH EVIDENCE — no OrbStack*.ips anywhere in `~/Library/Logs/DiagnosticReports/` or `Retired/`; grep for `AttributeGraph`/`OrbStack`/`Charts` across all reports returned zero hits. Newest crash report on disk is 2026-06-25 (non-OrbStack). The prior beta1 `26A5353q` crash report is no longer on disk (purged). OrbStack 2.2.1 still installed. No crash captured on beta2 — needs fresh repro before filing.

**Live repro attempt 2026-06-26 — NOT REPRODUCED on beta2 (likely fixed):** OrbStack 2.2.1 kept on the **General → Activity Monitor** charts view and monitored for **3h21m** (well past the beta1 ~2h50m crash point). RSS trend (sampled每60s): grew briefly to ~197 MB early, then **fell back and plateaued at ~150–185 MB for the remaining 2.5h** — the opposite of beta1's unbounded `AttributeGraph` growth → alloc-abort. CPU 0% at idle, no crash, no `.ips`. Memory is being reclaimed instead of accumulating unbounded → the SwiftUI Charts / AttributeGraph leak does **not** reproduce on beta2. Caveat: idle CPU was 0% (charts may have been throttled while the window was occluded/backgrounded), so this is "doesn't crash under normal use" rather than a guaranteed code-level fix — but the plateau (vs runaway) is strong evidence. Status → 🟢 likely fixed on beta2.

## Resolution — fixed by OrbStack in 2.2.2, and our beta2 verdict was wrong / 结论:OrbStack 2.2.2 修复,而我们的 beta2 判断是错的

**2026-08-03 — [kdrag0n](https://github.com/orbstack/orbstack/issues/2526#issuecomment-) closed [orbstack#2526](https://github.com/orbstack/orbstack/issues/2526) with "Fixed in v2.2.2."** OrbStack **2.2.2 (20903)** shipped 2026-08-02; its release notes do not name the crash, listing only "Improved macOS 27 beta compatibility" and "Various USB and UI fixes", but the author's statement is explicit. 2.2.2 is installed here and no OrbStack crash report has appeared on disk since.

### Two things in this write-up were wrong / 本文此前有两处错误

**1. "Not reproduced" was recorded as "likely fixed" — but the opposite over-claim is just as unsupported.** The 2026-06-26 retest kept OrbStack on the Activity Monitor charts view for **3h21m**, past the beta1 ~2h50m crash point, saw RSS plateau instead of grow, and concluded 🟢 *likely fixed on beta2*. That verdict rested on a single non-reproducing window, which is not evidence of a fix — and the retest itself had recorded the right caveat, *"idle CPU was 0% (charts may have been throttled while the window was occluded/backgrounded), so this is 'doesn't crash under normal use' rather than a guaranteed code-level fix"*, which the status line then overrode.

**What we can and cannot say, precisely:**

| | |
|---|---|
| Established | Last observed crash: **beta1 `26A5353q`, OrbStack 2.2.1**, 2026-06-10. No OrbStack crash report has appeared on disk since — across beta2, beta3, the beta3 revision and beta4. |
| Established | The vendor shipped a fix in **2.2.2 on 2026-08-02** and closed the upstream issue with "Fixed in v2.2.2", so as of early August he still considered it a live, fixable bug. |
| **Not** established | That the crash **reproduced** on beta2/beta3/beta4. It was never once reproduced after beta1. An earlier revision of this section asserted it "survived beta2, beta3, the beta3 revision and beta4" — that was inferred from the existence of the vendor fix, which does not support it. Retracted. |
| **Not** established | That macOS beta2 fixed it. Equally unsupported, and it is what the original 🟢 claimed. |
| Confound | The workaround was adopted after beta1 — the reporter stopped leaving OrbStack parked on the Activity Monitor view for hours. The crash needs ~2h50m of continuous GUI uptime **on that specific view**, so months of not seeing it is exactly what you would expect from the behaviour change alone, independent of any code change on either side. |

The two candidate explanations for the silence — an OS-side change in beta2, or simply not exercising the trigger any more — were **never separated**, and now cannot be: 2.2.2 is installed and the vendor fix has landed. The defensible statement is narrow: **the crash was last seen on beta1, and the shipped fix is OrbStack's.** Who fixed what in the intervening weeks is not recoverable from what we have.

**"未复现"被写成了"已修复",而反向的过度断言同样没有依据。** 2026-06-26 那次 3h21m 未复现被判为 🟢 beta2 已修复 —— 单次未复现窗口不构成修复证据,当时也已写下正确的保留意见,却被状态行覆盖。**但需要同样明确的是:** 本节此前断言该 bug "活过 beta2/beta3/beta3 修订/beta4",那是从"厂商后来修了"倒推出来的,同样缺乏依据,现予撤回。可确证的只有:最后一次实际崩溃是 **beta1 + 2.2.1(2026-06-10)**,此后再未出现;厂商于 **2026-08-02 在 2.2.2 中修复**并关闭上游 issue,说明其在 8 月初仍视之为真实存在的可修 bug。**混杂因素:** beta1 之后已采用规避手段(不再让 OrbStack 长时间停在 Activity Monitor 页),而该崩溃需要在**该特定界面**上连续运行约 2h50m —— 因此"很久没遇到"完全可以仅由使用习惯改变解释,与双方是否改过代码无关。两种解释**从未被区分开**,现在也无法再区分。可辩护的表述很窄:**该崩溃最后一次出现在 beta1,而最终落地的修复来自 OrbStack。**

**2. "Apple framework regression, no app-side fix" was wrong as a practical claim.** The vendor's own first read matched ours — on 2026-06-13 kdrag0n wrote *"both look like SwiftUI or other framework bugs… There's likely not much we can do here"* and recommended filing with Apple. Seven weeks later he fixed it in the app. Where the crash *bottoms out* (AttributeGraph, an Apple private framework) does not settle who **can** fix it: an app can restructure how it drives SwiftUI Charts so the attribute graph stops growing without bound. "The stack ends in an Apple framework" is an argument about the throw site, not about ownership of the fix — and this issue is the counter-example to treating the two as the same thing. (Contrast [#17](wechat-imageviewer-viewbridge-crash.md), where four unrelated apps across four UI toolkits hit a byte-identical Apple throw site — *that* pattern does implicate the framework, because no app-side commonality survives.)

**2026-08-03,OrbStack 作者 kdrag0n 以「Fixed in v2.2.2」关闭了上游 issue。** 本文此前有两处错误:其一,2026-06-26 那次 3h21m 未复现被写成了"🟢 beta2 已修复",实际上 bug 一路活过 beta2/beta3/beta3 修订/beta4,直到七周后由 OrbStack 在应用侧修掉 —— **单次未复现窗口再长也不构成"已修复"的证据**;当时其实已经写下了正确的保留意见(可能因窗口被遮挡而节流),却被状态行覆盖掉了。其二,"Apple 框架回归、应用侧无解"这个判断在实践层面是错的:崩溃**终止于** Apple 私有框架,并不决定**谁能修** —— 应用可以改变驱动 SwiftUI Charts 的方式,使属性图不再无界增长。作为对照,[#17](wechat-imageviewer-viewbridge-crash.md) 里四个技术栈互不相同的 app 撞上逐字相同的抛点,那才是真正指向框架的形态。

### Apple Feedback / 关于 Feedback

The `FB________` placeholder is retired unfiled. With the vendor fix shipped there is no user-facing bug left to report, and we never captured a reproduction on a build later than beta1 — a Feedback filed now would carry a single beta1 crash report and no repro. If the same `AttributeGraph` alloc-abort signature turns up in another app, that would be the time to file, with the cross-app evidence that makes such a report actionable.

`FB________` 占位符作废、不再提交:厂商已修,无用户可见问题;且我们从未在 beta1 之后的版本上抓到复现,此时提交只能附一份 beta1 崩溃报告而无复现步骤。若该签名日后出现在别的 app 上,再以跨 app 证据提交才有意义。

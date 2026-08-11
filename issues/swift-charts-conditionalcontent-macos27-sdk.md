# Swift Charts: `if/else` in a chart builder fails to build under the macOS 27 SDK
# Swift Charts：chart builder 里的 `if/else` 在 macOS 27 SDK 下编译不过

> 🔗 **Track / 关注此问题:** [#11 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/11)

| | |
|---|---|
| **Status** | 🟢 **Fixed in the macOS 27 SDK shipped with Xcode 27 beta 5 (`27A5237l`)** — verified 2026-08-11 by A/B against the previous toolchain on the same machine (see [Retest](#retest-on-xcode-27-beta-5-27a5237l-2026-08-11--fixed) below). Apple lists radar 174168981 as a **Resolved Issue** in the macOS 27 beta 5 release notes; it was a *Known Issue* through beta 2. Was previously filed here as intentional-by-design SDK behavior — that reading was wrong, see [Correction](#correction-what-we-got-wrong). |
| **Toolchain** | Xcode 27 beta / macOS 27 SDK (building an app that still deploys to macOS 14 / iOS 18). **This is a toolchain property, not an OS property** — the trigger lives in the SDK that ships inside Xcode, so the macOS build you booted is irrelevant. Retest with [`tools/swift-charts-conditionalcontent-repro.sh`](../tools/swift-charts-conditionalcontent-repro.sh). |
| **Component** | Apple **Swift Charts** (`@ChartContentBuilder`) |
| **Report** | **Apple radar `174168981`** — listed in the Xcode 26 / macOS 27 SDK release-notes *Known Issues*. Apple confirms it produces the conformance warning **and the app may crash at runtime when that content loads**. |

## Symptom / 症状

Code that compiled fine on Xcode 25 stops compiling when built with the Xcode 26 / macOS 27 SDK — **without any source change** — if a chart builder contains an `if/else`:

```
error: conformance of '_ConditionalContent<TrueContent, FalseContent>' to 'ChartContent'
       is only available in macOS 27.0 / iOS 27.0 or newer
```

The error points at the `_ConditionalContent` type, not your line, so it's easy to be confused by.

升级到 Xcode 26 / macOS 27 SDK 后，**源码一行没改**，只要 `Chart { ... }` 闭包里写了 `if/else` 就报上面这个错。报错只提 `_ConditionalContent`、不点具体行，容易懵。

## Root cause / 根因

Swift Charts' `@ChartContentBuilder` lowers branches differently, and the macOS 27 SDK added an availability annotation to one of them:

| You write / 你写的 | Lowers to / 编译成 | `ChartContent` conformance |
|---|---|---|
| `if cond { MarkA }` (**no else**) | `Optional<MarkA>` | `extension Optional: ChartContent` — available since **macOS 13** ✅ |
| `if cond { A } else { B }` | `_ConditionalContent<A,B>` | `extension _ConditionalContent: ChartContent` — macOS 27 SDK marks it **`@available(macOS 27 / iOS 27)`** ❌ |

So the new SDK constrains the `_ConditionalContent: ChartContent` conformance to macOS 27+. With a lower deployment target (e.g. macOS 14 / iOS 18), the compiler must guarantee the older OS works → it rejects `if/else` (and `if / else if`) inside chart builders. A **bare `if`** (no `else`) is unaffected because it lowers to `Optional`.

确认方式：读 macOS 27 SDK 里 Swift Charts 的 `.swiftinterface`，`extension _ConditionalContent: ChartContent` 上确有 `@available(macOS 27/iOS 27)`，而 `extension Optional: ChartContent` 是 macOS 13 起就有。

## Reproduction / 复现

Build any target that (a) uses Swift Charts with an `if/else` inside a `Chart {}` / `@ChartContentBuilder` body and (b) deploys below macOS 27 / iOS 27, using the Xcode 26 / macOS 27 SDK.

## Workaround / 临时规避

Rewrite so the builder never emits `_ConditionalContent`:

```swift
// ❌ emits _ConditionalContent → fails
if useStacked { ForEach(stack) { BarMark(...) } }
else          { ForEach(daily) { BarMark(...) } }

// ✅ two unconditional ForEach over ternary-selected data (empty array draws nothing)
ForEach(useStacked ? stack : []) { BarMark(...) }
ForEach(useStacked ? []    : daily) { BarMark(...) }

// ✅ or two mutually-exclusive BARE ifs (each lowers to Optional)
if value != nil { /* mark A */ }
if value == nil { /* mark B */ }

// ✅ or keep one mark and branch on a property via ternary
BarMark(...).foregroundStyle(cond ? .green : .red)
```

Output is byte-for-byte identical. Avoid `if/else` and `if/else if` directly inside chart builders.

### Apple's official workaround (radar 174168981) / Apple 官方解法

Per Apple's Known-Issues note, you can **keep the `if/else`** — just move it out of the `Chart {}` closure into a separate function or computed property annotated `@ChartContentBuilder`:

```swift
Chart(dataPoints, id: \.index) { dataPoint in
    marks(for: dataPoint)
}

@ChartContentBuilder
private func marks(for dataPoint: DataPoint) -> some ChartContent {
    if selectedMetric == "Rate" {
        LineMark(x: .value("X", dataPoint.index), y: .value("Y", dataPoint.rate))
            .foregroundStyle(.blue)
    } else {
        LineMark(x: .value("X", dataPoint.index), y: .value("Y", dataPoint.signal))
            .foregroundStyle(.green)
    }
}
```

把 `if/else` 抽到一个标了 `@ChartContentBuilder` 的独立函数/计算属性里(保留 if/else),Chart 闭包里只调它即可。这是 Apple 官方推荐的解法 —— 比上面"改写成裸 if/ternary"可读性更好,适合分支逻辑复杂时用。两种都能消除 `_ConditionalContent` 触发的报错/运行时崩溃。

## Retest on Xcode 27 beta 5 (`27A5237l`), 2026-08-11 — FIXED / 已修复

A/B on one machine, same source, same OS (macOS 27.0 beta5 `26A5406e`) — **only the Xcode changed**. Run via `DEVELOPER_DIR=… bash tools/swift-charts-conditionalcontent-repro.sh`:

| case | `27A5194q` | `27A5237l` |
|---|---|---|
| **A** `if/else` @ `arm64-apple-macos14.0` | `exit=1` ❌ | **`exit=0`** ✅ |
| **B** control — `if/else` @ `macos27.0` | `exit=0` | `exit=0` |
| **C** control — bare `if` @ `macos14.0` | `exit=0` | `exit=0` |

Only A flipped; both controls held. Matches Apple listing radar 174168981 as Resolved in the macOS 27 beta 5 notes.

### How Apple actually fixed it / 真正的修法

**Not** by removing the availability gate — `@available(… macOS 27.0 …)` above `extension _ConditionalContent : ChartContent` is **still there, untouched**, at line 1120 of the new `Charts.swiftinterface`. The fix reroutes what `@ChartContentBuilder` lowers `if/else` *to*:

```
buildEither<T1,T2>(first:) -> Charts.BuilderConditional<T1,T2>
  27A5194q:  @_disfavoredOverload                                  ← loses overload resolution
  27A5237l:  @available(macOS, introduced: 13.0, obsoleted: 27.0)  ← disfavored dropped, obsoleted added
```

`Charts.BuilderConditional` is Charts' own type and its `ChartContent` conformance has carried `@available(… macOS 13.0 …)` all along (it already existed in the old SDK — 28 references — just outranked by `@_disfavoredOverload`). So a **sub-27 deployment target now resolves to that overload and never forms a `_ConditionalContent` at all**; on macOS 27+ the overload is `obsoleted` and the original `_ConditionalContent` path takes over. A properly back-deployable fix. Charts module version went `5.0.37` → `8.0.82`.

**Practical consequence:** do not read "the macOS 27.0 gate is still in the `.swiftinterface`" as "still broken". Judge by whether the code compiles.

不是删掉可用性门禁 —— `_ConditionalContent : ChartContent` 上那条 `@available(macOS 27.0)` **原封不动还在**。真正的改动是把 `@ChartContentBuilder` 的 `if/else` **改路由**：`buildEither` 去掉 `@_disfavoredOverload`、加上 `obsoleted: 27.0`,于是低于 27 的部署目标改走 Charts 自己的 `BuilderConditional`(其 conformance 从 macOS 13.0 起就有),根本不再生成 `_ConditionalContent`;27+ 上该重载 obsoleted,回落原路径。所以**别拿"门禁还在"当作"没修好"的证据**,以能否编译为准。

## Correction: what we got wrong / 更正

Two claims in earlier revisions of this file were wrong, and they compounded:

1. **"An intentional SDK availability tightening, not a bug; won't change per beta."** Apple did fix it, via radar 174168981. It was a real tracked bug all along — it was listed in Apple's *Known Issues* from the start, which we read as "documented ⇒ intended".
2. **"Verified still present on beta3 SDK, Xcode 27.0 `27A5194q`."** `27A5194q` was **not** a beta3 toolchain. Bundle evidence on this machine (`Contents/Info.plist` mtime `Jun 6`, SDK mtime `Jun 10 00:00:15`, 16 s after `~/Downloads/Xcode_27_beta.xip` finished at `Jun 9 23:59`) puts the install at **2026-06-09/10**, i.e. **Xcode 27 beta 1** — cross-checked against Wayback snapshots of the Xcode release notes (`2026-06-11` still titled *Xcode 27 Beta*, `2026-06-23` titled *Beta 2*). Xcode was never updated after that. The 07-08 compile results were real, but they were measured on a **beta1 toolchain that merely survived into the beta3 OS window** — the beta2/3/4 SDKs were **never tested**, so "still present on beta3 SDK" was never established.

Lesson: this entry's measurement base never actually moved for two months, which is exactly why it looked stable enough to call "by-design". An OS-labelled retest of an SDK-level bug proves nothing.

上面两条旧结论都是错的:(1) 它不是"有意为之的设计",Apple 确实修了;(2) `27A5194q` 不是 beta3 工具链,而是 **beta1**(装机时间 2026-06-09/10,有 bundle 日期与 Wayback 版本号双重佐证),之后两个月没升级过 —— 所以"已在 beta3 SDK 上验证"从未成立,beta2/3/4 的 SDK 一个都没测过。教训:**用 OS 版本给一个 SDK 层的 bug 标复验窗口,等于没测。**

## Retest on OS beta3 `26A5378j` (2026-07-08) — STILL PRESENT (on the beta1 toolchain) / 仍在

Verified with a minimal repro built against **Xcode 27.0 (`27A5194q`), Apple Swift 6.4, macOS 27.0 SDK** — which, per the Correction above, is the **beta1** toolchain, not beta3's:

- `if/else` inside a `Chart {}` body, deploy target `arm64-apple-macos14.0`, **Swift 6 mode → hard `error`**: `conformance of '_ConditionalContent<TrueContent, FalseContent>' to 'ChartContent' is only available in macOS 27.0 or newer`. (Default language mode downgrades it to the same-text *warning* that "is an error in the Swift 6 language mode".)
- **Control 1** — same code, deploy target `arm64-apple-macos27.0` → **compiles clean**. Confirms it's a deployment-target availability tightening, nothing else.
- **Control 2** — a **bare `if`** (no `else`) at target `macos14.0` → **compiles clean** (lowers to `Optional`, whose `ChartContent` conformance has no macOS-27 gate).
- The `.swiftinterface` still carries it: `@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)` directly above `extension _ConditionalContent : ChartContent` (vs `extension Optional : ChartContent` which has no such attribute).

**Net (as written at the time):** persists; the workarounds below remain the answer. Not something a macOS beta bump would change — Apple's fix, if any, would come via a Swift Charts SDK update tied to radar 174168981. *That last sentence turned out to be the right call: the fix arrived exactly that way, in the SDK inside Xcode 27 beta 5.*

## Notes / 备注

- Real example: in the `ClaudeUsageMenuBar` app this hit 3 files (`UsageTrendChartView`, `MenuBarContentView`, `UsageDashboardView`) and blocked **both** the macOS and iOS builds until rewritten (shipped in v0.3.379, 2026-06-26).
- Affects anyone using **Swift Charts + `if/else` branches + a sub-27 deployment target** on an Xcode 27 beta earlier than beta 5. Primarily a compile-time failure; Apple's Known-Issue text also warned the app "might crash at runtime when that content is loaded".
- **If you are still hitting this, upgrade Xcode — not macOS.** The SDK ships inside Xcode, so no macOS beta update will change the outcome, and no macOS version blocks the fix (Xcode 27 beta 5 requires only macOS 26.4 or later).

# Swift Charts: `if/else` in a chart builder fails to build under the macOS 27 SDK
# Swift Charts：chart builder 里的 `if/else` 在 macOS 27 SDK 下编译不过

> 🔗 **Track / 关注此问题:** [#11 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/11)

| | |
|---|---|
| **Status** | 🟢 Closed / by-design — an **intentional macOS 27 SDK availability tightening**, not a tracked bug. Apple-acknowledged **Known Issue** (radar 174168981) with an official workaround; won't change per macOS beta (verified still present on beta3 SDK, Xcode 27.0 `27A5194q`). Kept as reference, tracked *closed* like other explained entries (cf. [#9](telegram-mas-lag.md)). |
| **Toolchain** | Xcode 26 beta / macOS 27 SDK (building an app that still deploys to macOS 14 / iOS 18) |
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

## Retest on beta3 `26A5378j` (2026-07-08) — STILL PRESENT / 仍在

Verified with a minimal repro built against the beta3 toolchain — **Xcode 27.0 (`27A5194q`), Apple Swift 6.4, macOS 27.0 SDK**. Still not fixed (as expected — it's an intentional SDK availability annotation, not a regression):

- `if/else` inside a `Chart {}` body, deploy target `arm64-apple-macos14.0`, **Swift 6 mode → hard `error`**: `conformance of '_ConditionalContent<TrueContent, FalseContent>' to 'ChartContent' is only available in macOS 27.0 or newer`. (Default language mode downgrades it to the same-text *warning* that "is an error in the Swift 6 language mode".)
- **Control 1** — same code, deploy target `arm64-apple-macos27.0` → **compiles clean**. Confirms it's a deployment-target availability tightening, nothing else.
- **Control 2** — a **bare `if`** (no `else`) at target `macos14.0` → **compiles clean** (lowers to `Optional`, whose `ChartContent` conformance has no macOS-27 gate).
- The `.swiftinterface` still carries it: `@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)` directly above `extension _ConditionalContent : ChartContent` (vs `extension Optional : ChartContent` which has no such attribute).

**Net:** persists on beta3 SDK; the workarounds below remain the answer. Not something a macOS beta bump would change — Apple's fix, if any, would come via a Swift Charts SDK update tied to radar 174168981.

## Notes / 备注

- Real example: in the `ClaudeUsageMenuBar` app this hit 3 files (`UsageTrendChartView`, `MenuBarContentView`, `UsageDashboardView`) and blocked **both** the macOS and iOS builds until rewritten (shipped in v0.3.379, 2026-06-26).
- Affects anyone using **Swift Charts + `if/else` branches + a sub-27 deployment target** once they move to the Xcode 26 / macOS 27 SDK. Not a runtime bug — a compile-time availability tightening.

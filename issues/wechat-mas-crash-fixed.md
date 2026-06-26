# WeChat (Mac App Store build) crash on launch — FIXED in 4.1.10
# 微信（Mac App Store 版）启动崩溃 —— 4.1.10 已修复

| | |
|---|---|
| **Status** | 🟢 Fixed |
| **macOS** | 27.0 beta `26A5353q` / beta2 `26A5368g` |
| **Component** | **WeChat 4.1.9** — Mac App Store build |
| **Report** | resolved by vendor update |

## Symptom / 症状

WeChat **4.1.9 (Mac App Store build)** crashed on launch / would not open on macOS 27 beta. The **official-site build of the same version worked**, indicating the MAS sandbox variant was the trigger.

微信 **4.1.9（Mac App Store 版）** 在 macOS 27 beta 上启动崩溃 / 打不开；**官网同版本正常**，说明是 MAS 沙盒变体触发。

## Resolution / 结论

✅ **Fixed in WeChat 4.1.10.** Test machine is now on **4.1.10 (build 268880, MAS)** and launches normally.

✅ 微信 **4.1.10 已修复**。测试机现为 4.1.10（build 268880，MAS 版），可正常启动。

## Workaround (for anyone still on 4.1.9) / 临时规避（仍在 4.1.9 的人）

- Update to **4.1.10+**, or
- Use the **official-site build** instead of the Mac App Store build.

升级到 4.1.10+，或改用官网版而非 App Store 版。

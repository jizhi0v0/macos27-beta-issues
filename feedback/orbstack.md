VERIFICATION: HOLD — no on-disk crash evidence on current build. Retest 2026-06-26 on macOS 27.0 beta2 26A5368g found NO OrbStack*.ips in ~/Library/Logs/DiagnosticReports/ or its Retired/ subfolder. A full-text grep for `AttributeGraph`, `OrbStack`, and `Charts` across every report on disk returned zero hits. The only prior occurrence was inferred/seen on beta1 26A5353q, and no such report remains on disk. OrbStack 2.2.1 is still installed.

# HOLD — needs fresh repro on macOS 27.0 beta2 (26A5368g)

Do NOT file to Apple yet. There is no captured crash report on the current build. Filing now would mean submitting a Feedback with either no attachable `.ips` or an attachment from an older build (beta1 26A5353q) that may already be fixed — a high risk of a wrong/duplicate/non-actionable report. Apple cannot triage a SwiftUI/AttributeGraph abort without a current-build crash log.

## 1-line repro recipe
Launch OrbStack GUI, open the usage/Charts window, and leave it open ~2h50m on beta2 until it aborts; then confirm a new `OrbStack-*.ips` appears in `~/Library/Logs/DiagnosticReports/` and that its OS Version line reads `26A5368g`.

## What to capture before filing
- Fresh `OrbStack-*.ips` whose header `OS Version` = `macOS 27.0 (26A5368g)`.
- Confirm the stack still terminates inside `AttributeGraph` / SwiftUI Charts.
- Then promote this to a full Feedback (Apple area: Developer Tools / SwiftUI; attach the new .ips) and add a workaround note (avoid keeping the Charts window open).

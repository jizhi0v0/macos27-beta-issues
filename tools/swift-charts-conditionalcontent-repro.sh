#!/bin/bash
# Repro / retest for issues/swift-charts-conditionalcontent-macos27-sdk.md (#11).
#
# WHAT THIS TESTS: a *toolchain* property, not an OS property. The trigger lives
# in the macOS 27 SDK's Charts.swiftinterface, which ships with Xcode -- so the
# result depends on which Xcode `xcrun` resolves to, NOT on the macOS build you
# booted. Re-run this after every Xcode beta bump; running it after a *macOS*
# beta bump with the same Xcode will not change anything.
#
# Apple listed radar 174168981 as a Resolved Issue in the macOS 27 beta 5 notes
# (it was a Known Issue through beta 2). As of Xcode 27.0 27A5194q it still
# reproduces here, which is consistent -- that Xcode predates beta 5. The fix,
# if it landed, arrives with a newer Xcode's SDK.
#
# USAGE:
#   bash tools/swift-charts-conditionalcontent-repro.sh
#
# Keep old Xcode betas installed side by side and A/B them:
#   sudo xcode-select -s /Applications/Xcode-beta.app && bash tools/...
#
# VERDICT: only A flipping 1 -> 0 while B and C stay 0 means "fixed". If B or C
# also move, something else changed and the comparison is void.

set -u

SRC=$(mktemp -d)
trap 'rm -rf "$SRC"' EXIT

cat > "$SRC/IfElse.swift" <<'EOF'
import SwiftUI
import Charts

struct P: Identifiable { let id = UUID(); let x: Int; let a: Double; let b: Double }

struct IfElseChart: View {
    let data: [P]
    let useA: Bool
    var body: some View {
        Chart(data) { p in
            if useA {
                LineMark(x: .value("x", p.x), y: .value("y", p.a))
            } else {
                LineMark(x: .value("x", p.x), y: .value("y", p.b))
            }
        }
    }
}
EOF

cat > "$SRC/BareIf.swift" <<'EOF'
import SwiftUI
import Charts

struct Q: Identifiable { let id = UUID(); let x: Int; let a: Double }

struct BareIfChart: View {
    let data: [Q]
    let show: Bool
    var body: some View {
        Chart(data) { p in
            if show {
                LineMark(x: .value("x", p.x), y: .value("y", p.a))
            }
        }
    }
}
EOF

SDK=$(xcrun --sdk macosx --show-sdk-path)

echo "=== toolchain under test ==="
echo "xcode-select: $(xcode-select -p)"
xcodebuild -version 2>/dev/null | tr '\n' ' '; echo
echo "SDK: $SDK"
echo "OS:  $(sw_vers -productVersion) $(sw_vers -buildVersion)   <- not the variable that matters here"
echo

# Swift 6 language mode makes it a hard error; the default mode downgrades the
# same diagnostic to a warning ("this is an error in the Swift 6 language mode"),
# which would make a still-broken SDK look fine to an exit-code check.
check() { # label target file
  xcrun swiftc -sdk "$SDK" -target "$2" -swift-version 6 -typecheck "$SRC/$3" >/dev/null 2>&1
  echo "$1 -> exit=$?"
}

echo "=== typecheck (Swift 6 mode) ==="
check "A  if/else @ macos14.0 (expect 1 = still broken, 0 = FIXED)" arm64-apple-macos14.0 IfElse.swift
check "B  if/else @ macos27.0 (control: deployment-target gate) " arm64-apple-macos27.0 IfElse.swift
check "C  bare if @ macos14.0 (control: lowers to Optional)     " arm64-apple-macos14.0 BareIf.swift
echo

echo "=== mechanism, read from the SDK's Charts.swiftinterface ==="
IFACE="$SDK/System/Library/Frameworks/Charts.framework/Modules/Charts.swiftmodule/arm64e-apple-macos.swiftinterface"
if [ -r "$IFACE" ]; then
  grep -m1 -o "user-module-version [0-9.]*" "$IFACE" | sed 's/^/  Charts /'
  echo "  --- the conformance that used to be blamed (expect it to STILL be gated) ---"
  grep -n -B1 "extension.*_ConditionalContent.*ChartContent" "$IFACE" | sed 's/^/  /'
  echo "  --- what actually decides it: the buildEither overloads ---"
  grep -n -A1 "obsoleted: 27.0)$" "$IFACE" | grep -m2 -B1 "buildEither" | sed 's/^/  /'
  echo
  # Do NOT read the macOS 27.0 gate on _ConditionalContent as "still broken".
  # Verified 2026-08-11: Xcode 27A5237l compiles case A fine while that gate is
  # untouched. Apple fixed this by rerouting the builder, not by removing the
  # gate: @ChartContentBuilder.buildEither now carries
  # @available(macOS, introduced: 13.0, obsoleted: 27.0) and returns Charts'
  # own BuilderConditional (conformance available since macOS 13.0). Below-27
  # deployment targets resolve to that overload and never form a
  # _ConditionalContent; on 27+ the overload is obsoleted and the old
  # _ConditionalContent path takes over. In 27A5194q the same overload existed
  # but was @_disfavoredOverload with no obsoleted:, so it lost overload
  # resolution and the gated path won.
  echo "  The macOS 27.0 gate above is EXPECTED to remain even when fixed."
  echo "  The fix lives in buildEither: obsoleted:27.0 + Charts.BuilderConditional"
  echo "  (available since macOS 13.0) for below-27 deployment targets."
  echo "  Trust the exit codes above, not the presence of that gate."
else
  echo "  (not readable: $IFACE)"
fi

echo
echo "=== full diagnostic for case A ==="
DIAG=$(xcrun swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 6 \
  -typecheck "$SRC/IfElse.swift" 2>&1 | grep -m1 "error:\|warning:")
if [ -n "$DIAG" ]; then
  echo "$DIAG" | sed 's/^/  /'
else
  echo "  (none -- case A produced no diagnostic)"
fi

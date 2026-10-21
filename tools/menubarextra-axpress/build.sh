#!/bin/zsh
# Builds three accessory (LSUIElement) menu-bar apps that differ only in how the
# status item is made, plus the probe and the target/action self-report.
#   MBXWindow  SwiftUI MenuBarExtra, .menuBarExtraStyle(.window)
#   MBXMenu    SwiftUI MenuBarExtra, .menuBarExtraStyle(.menu)
#   MBXAppKit  AppKit NSStatusItem, button target/action -> NSPopover
# Output goes to ./build. Ad-hoc signed; the probe needs Accessibility for the
# terminal it runs from.
set -e
cd "$(dirname "$0")"
mkdir -p build
for spec in MBXWindow:MBX_WINDOW MBXMenu:MBX_MENU MBXAppKit:MBX_APPKIT; do
  N=${spec%%:*}; F=${spec##*:}
  mkdir -p "build/$N.app/Contents/MacOS"
  swiftc -O -parse-as-library -D $F MBX.swift -o "build/$N.app/Contents/MacOS/$N"
  cat > "build/$N.app/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.mbxprobe.$N</string>
<key>CFBundleName</key><string>$N</string>
<key>CFBundleExecutable</key><string>$N</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
  codesign -s - --force "build/$N.app"
done
swiftc -O axpress-probe.swift -o build/axpress-probe
swiftc -O -parse-as-library MBXDiag.swift -o build/mbxdiag
echo "built: $(ls build)"

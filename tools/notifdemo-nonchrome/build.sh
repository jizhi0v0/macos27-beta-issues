#!/bin/bash
# Builds NotifDemo.app (parent) + NotifDemoHelper.app (alerts helper) and
# installs both into ~/Applications.  Run from this directory.
set -euo pipefail
cd "$(dirname "$0")"
OUT="${OUT:-$PWD/build}"
rm -rf "$OUT"; mkdir -p "$OUT"

mkbundle() {  # name  bundleid  lsuielement
  local app="$OUT/$1.app"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$1</string>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>CFBundleName</key><string>$1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><$3/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
}

mkbundle NotifDemoHelper com.jizhi0v0.notifdemo.helper true
mkbundle NotifDemo       com.jizhi0v0.notifdemo        true

# Swift only allows top-level statements in a file literally named main.swift,
# so stage each entry point under that name.
mkdir -p "$OUT/src-helper" "$OUT/src-parent"
cp Log.swift "$OUT/src-helper/"; cp helper.swift "$OUT/src-helper/main.swift"
cp Log.swift "$OUT/src-parent/"; cp parent.swift "$OUT/src-parent/main.swift"

xcrun swiftc -O -target arm64-apple-macos13.0 "$OUT/src-helper/Log.swift" "$OUT/src-helper/main.swift" \
  -o "$OUT/NotifDemoHelper.app/Contents/MacOS/NotifDemoHelper"
xcrun swiftc -O -target arm64-apple-macos13.0 "$OUT/src-parent/Log.swift" "$OUT/src-parent/main.swift" \
  -o "$OUT/NotifDemo.app/Contents/MacOS/NotifDemo"

codesign --force --deep -s - "$OUT/NotifDemoHelper.app"
codesign --force --deep -s - "$OUT/NotifDemo.app"

mkdir -p ~/Applications
rm -rf ~/Applications/NotifDemoHelper.app ~/Applications/NotifDemo.app
cp -R "$OUT/NotifDemoHelper.app" "$OUT/NotifDemo.app" ~/Applications/
echo "installed:"; ls -d ~/Applications/NotifDemo*.app

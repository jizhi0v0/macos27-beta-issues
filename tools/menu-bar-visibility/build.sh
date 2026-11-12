#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
sdk=$(xcrun --sdk macosx --show-sdk-path)
for lifecycle in COCOA SWIFTUI EXTRA; do
  swiftc -O -parse-as-library -sdk "$sdk" -target arm64-apple-macos26.0 \
    -D "$lifecycle" Probe.swift -o "build/probe-$lifecycle"
done
for spec in MBHPlain:COCOA MBHDrop:COCOA MBHSharing:COCOA MBHShot:COCOA MBHSwift:SWIFTUI MBHSwiftShot:SWIFTUI MBHExtra:EXTRA; do
  name=${spec%%:*}
  lifecycle=${spec##*:}
  app="build/$name.app"
  mkdir -p "$app/Contents/MacOS"
  cp "build/probe-$lifecycle" "$app/Contents/MacOS/$name"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.menubarvisibility.$name</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleDisplayName</key><string>$name</string>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>ProbeMode</key><string>$name</string>
</dict></plist>
PLIST
  codesign --force --sign - "$app"
done

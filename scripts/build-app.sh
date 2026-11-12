#!/bin/bash
# Builds build/Loopsmith.app (release, ad-hoc signed). Usage: ./scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.1.0"
APP="build/Loopsmith.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Loopsmith" "$APP/Contents/MacOS/Loopsmith"
if [[ -f "brand/AppIcon.icns" ]]; then
  cp "brand/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Loopsmith</string>
  <key>CFBundleDisplayName</key><string>Loopsmith</string>
  <key>CFBundleIdentifier</key><string>io.github.loopsmith</string>
  <key>CFBundleExecutable</key><string>Loopsmith</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Loopsmith.app"
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Loopsmith.app"
fi

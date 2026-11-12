#!/bin/bash
# Builds build/Loopsmith.app (release, ad-hoc signed).
# Usage: ./scripts/build-app.sh [--universal] [--zip] [--install]
#   --universal  Apple silicon and Intel in one app (what the releases ship)
#   --zip        also writes build/Loopsmith-macos.zip, the release asset
#   --install    copies the app to /Applications and links the `loopsmith` command into ~/.local/bin
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=0 ZIP=0 INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --zip) ZIP=1 ;;
    --install) INSTALL=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# The version lives in Sources/Loopsmith/Entry.swift only.
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/Loopsmith/Entry.swift)"
APP="build/Loopsmith.app"
BUILD=(swift build -c release --disable-sandbox)
if [[ $UNIVERSAL == 1 ]]; then BUILD+=(--arch arm64 --arch x86_64); fi

"${BUILD[@]}"
BIN="$("${BUILD[@]}" --show-bin-path)/Loopsmith"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Loopsmith"
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
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/Loopsmith"))"

if [[ $ZIP == 1 ]]; then
  rm -f build/Loopsmith-macos.zip
  ditto -c -k --keepParent "$APP" build/Loopsmith-macos.zip
  echo "Built build/Loopsmith-macos.zip"
fi

if [[ $INSTALL == 1 ]]; then
  rm -rf "/Applications/Loopsmith.app"
  cp -R "$APP" /Applications/
  mkdir -p "$HOME/.local/bin"
  ln -sf "/Applications/Loopsmith.app/Contents/MacOS/Loopsmith" "$HOME/.local/bin/loopsmith"
  [[ $ZIP == 1 ]] || rm -rf build
  echo "Installed /Applications/Loopsmith.app and the loopsmith command (~/.local/bin/loopsmith)"
fi

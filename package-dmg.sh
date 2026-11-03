#!/bin/bash
set -eu
cd "$(dirname "$0")"
./fetch-vlckit.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/modules"
swift build --disable-sandbox -c release
bin=$(swift build --disable-sandbox -c release --show-bin-path)
mkdir -p .build dist
stage=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
app="$stage/4431 IPTV.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/Player" "$app/Contents/MacOS/Player"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Player</string>
<key>CFBundleIdentifier</key><string>local.heavensal.4431iptv</string>
<key>CFBundleName</key><string>4431 IPTV</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
mkdir -p "$app/Contents/Frameworks" "$app/Contents/Resources"
ditto Vendor/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework "$app/Contents/Frameworks/VLCKit.framework"
cp Vendor/COPYING.txt "$app/Contents/Resources/VLCKit-LICENSE.txt"
codesign --force --sign - "$app/Contents/Frameworks/VLCKit.framework"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -volname '4431 IPTV' -srcfolder "$stage" -format UDZO "$PWD/dist/4431 IPTV.dmg"
hdiutil verify "$PWD/dist/4431 IPTV.dmg"

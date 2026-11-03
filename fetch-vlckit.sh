#!/bin/bash
set -eu
cd "$(dirname "$0")"
if test -f Vendor/VLCKit.xcframework/Info.plist; then exit 0; fi
mkdir -p .build Vendor
temp=$(mktemp -d "$PWD/.build/vlckit.XXXXXX")
archive="$temp/VLCKit.tar.xz"
curl -fL --retry 2 https://download.videolan.org/pub/cocoapods/prod/VLCKit-3.7.3-319ed2c0-79128878.tar.xz -o "$archive"
printf '%s  %s\n' '019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d' "$archive" | shasum -a 256 -c -
tar -xf "$archive" -C "$temp"
mv "$temp/VLCKit - binary package/VLCKit.xcframework" Vendor/

#!/bin/bash
set -eu
cd "$(dirname "$0")"
if test -f Vendor/Sparkle.xcframework/Info.plist; then exit 0; fi
mkdir -p .build Vendor/Sparkle
archive="$PWD/.build/Sparkle-2.10.1.tar.xz"
curl -fL --retry 2 https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o "$archive"
printf '%s  %s\n' '1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27' "$archive" | shasum -a 256 -c -
tar -xf "$archive" -C Vendor/Sparkle
xcodebuild -create-xcframework -framework "$PWD/Vendor/Sparkle/Sparkle.framework" -output "$PWD/Vendor/Sparkle.xcframework"

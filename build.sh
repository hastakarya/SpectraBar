#!/usr/bin/env bash
# Builds build/TouchBarDisplay.app with the Command Line Tools; Xcode is not needed.
set -euo pipefail
cd "$(dirname "$0")"

sdk=$(xcrun --show-sdk-path)
app=build/TouchBarDisplay.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/"
swiftc -O main.swift TrackView.swift Players.swift AudioSpectrum.swift \
  -import-objc-header TouchBarPrivate.h \
  -F "$sdk/System/Library/PrivateFrameworks" -framework DFRFoundation \
  -o "$app/Contents/MacOS/TouchBarDisplay"
codesign --force --sign - "$app"
echo "Built $app"

#!/usr/bin/env bash
# Builds build/TouchBarDisplay.app with the Command Line Tools; Xcode is not needed.
set -euo pipefail
cd "$(dirname "$0")"

sdk=$(xcrun --show-sdk-path)
app=build/TouchBarDisplay.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/"
swiftc -O main.swift TrackView.swift NowPlaying.swift AudioSpectrum.swift SimulatedSpectrum.swift SpectrumStyle.swift \
  -import-objc-header TouchBarPrivate.h \
  -F "$sdk/System/Library/PrivateFrameworks" -framework DFRFoundation \
  -o "$app/Contents/MacOS/TouchBarDisplay"
mkdir -p "$app/Contents/Resources"
clang -O2 -fobjc-arc -dynamiclib -framework Foundation NowPlayingHelper.m \
  -o "$app/Contents/Resources/NowPlayingHelper.dylib"
codesign --force --sign - "$app"
echo "Built $app"

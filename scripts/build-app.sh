#!/usr/bin/env bash
# Builds dist/LagCam.app (ad-hoc signed) and dist/LagCam.zip.
# UNIVERSAL=1 builds an arm64 + x86_64 binary.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/LagCam.app
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0" --build-path ".build/$arch"
  done
  lipo -create -output "$APP/Contents/MacOS/LagCam" \
    .build/arm64/release/LagCam .build/x86_64/release/LagCam
else
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/LagCam" "$APP/Contents/MacOS/LagCam"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"
(cd dist && ditto -c -k --keepParent LagCam.app LagCam.zip)
echo "Built $APP and dist/LagCam.zip"

#!/usr/bin/env bash
# Regenerates the README images in docs/images/ using the app's real effects engine
# and menu UI, drawn on a synthetic demo scene (no camera needed).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=.build/screenshots
mkdir -p "$BUILD"
SOURCES=$(ls Sources/LagCam/*.swift | grep -v LagCamApp.swift)
# shellcheck disable=SC2086
swiftc -O -D SCREENSHOTS -module-name LagCamShots \
  $SOURCES scripts/screenshots/main.swift -o "$BUILD/make-screenshots"
"$BUILD/make-screenshots" docs/images

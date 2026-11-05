#!/bin/bash
# Launches the app in demo mode (sample data, in-memory) on a simulator and screenshots each screen.
# Usage: scripts/screenshots.sh <simulator-udid>
set -euo pipefail
cd "$(dirname "$0")/.."
UDID="$1"
BUNDLE=com.matisse.kakeibo

xcodebuild build -project Kakeibo.xcodeproj -scheme Kakeibo -configuration Debug \
  -destination "id=$UDID" -derivedDataPath simbuild CODE_SIGNING_ALLOWED=NO > simbuild.log 2>&1 \
  || { tail -n 60 simbuild.log; exit 1; }
APP=simbuild/Build/Products/Debug-iphonesimulator/Kakeibo.app

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

rm -rf screenshots
mkdir -p screenshots
shoot() {
  local name="$1" screen="$2"
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -demo -screen "$screen" > /dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "screenshots/$name.png" > /dev/null
  echo "captured $name"
}

xcrun simctl ui "$UDID" appearance light
shoot 01-home home
shoot 02-add-entry add
shoot 03-transactions transactions
shoot 04-accounts accounts
shoot 05-card-detail card
shoot 06-partner partner
shoot 07-review review
shoot 08-categories categories
shoot 09-setup setup
xcrun simctl ui "$UDID" appearance dark
shoot 10-home-dark home
shoot 11-add-entry-dark add

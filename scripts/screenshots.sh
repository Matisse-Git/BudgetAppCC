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
shoot 03b-transaction transaction
shoot 04-budgets budgets
shoot 05-accounts accounts
shoot 05b-accounts-flat accounts-flat
shoot 05c-edit-accounts edit-accounts
shoot 06-card-detail card
shoot 06b-bank-account bank
shoot 06c-card-setup card-setup
shoot 07-partner partner
shoot 08-review review
shoot 09-categories categories
shoot 10-setup setup
shoot 04b-budgets-all budgets-all
xcrun simctl ui "$UDID" appearance dark
shoot 12-home-dark home
shoot 13-budgets-dark budgets
shoot 14-accounts-dark accounts
shoot 15-add-entry-dark add

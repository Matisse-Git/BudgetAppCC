#!/bin/bash
# Builds an unsigned Kakeibo.ipa for sideloading with AltStore / SideStore.
# The app and widget are ad-hoc signed with their entitlements so AltStore
# knows to register the App Group when it re-signs with your Apple ID.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build
mkdir -p build

status=0
xcodebuild build \
  -project Kakeibo.xcodeproj \
  -scheme Kakeibo \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  > build/build-ipa.log 2>&1 || status=$?
grep -E "error:|BUILD (SUCCEEDED|FAILED)" build/build-ipa.log || true
if [ $status -ne 0 ]; then tail -n 80 build/build-ipa.log; exit $status; fi

APP=build/dd/Build/Products/Release-iphoneos/Kakeibo.app
test -d "$APP"

codesign --force --sign - --entitlements KakeiboWidget/KakeiboWidget.entitlements "$APP/PlugIns/KakeiboWidget.appex"
codesign --force --sign - --entitlements Kakeibo/Kakeibo.entitlements "$APP"

mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../Kakeibo.ipa Payload)
ls -lh build/Kakeibo.ipa

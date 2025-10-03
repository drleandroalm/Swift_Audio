#!/usr/bin/env bash
set -euo pipefail

SCHEME="SwiftScribe"

echo "[verify] Cleaning DerivedData..."
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/SwiftScribe-*" || true

echo "[verify] Building macOS app (Debug, arm64)..."
xcodebuild -scheme "$SCHEME" \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

MAC_APP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/SwiftScribe-*/Build/Products/Debug/SwiftScribe.app | tail -n1)
if [[ ! -d "$MAC_APP" ]]; then
  echo "[verify][macOS] ERROR: SwiftScribe.app not found"
  exit 1
fi

MAC_MODELS="$MAC_APP/Contents/Resources/speaker-diarization-coreml"
echo "[verify][macOS] Checking models in: $MAC_MODELS"
[[ -d "$MAC_MODELS/pyannote_segmentation.mlmodelc" ]] || { echo "[verify][macOS] Missing pyannote_segmentation.mlmodelc"; exit 1; }
[[ -f "$MAC_MODELS/pyannote_segmentation.mlmodelc/coremldata.bin" ]] || { echo "[verify][macOS] Missing segmentation coremldata.bin"; exit 1; }
[[ -d "$MAC_MODELS/wespeaker_v2.mlmodelc" ]] || { echo "[verify][macOS] Missing wespeaker_v2.mlmodelc"; exit 1; }
[[ -f "$MAC_MODELS/wespeaker_v2.mlmodelc/coremldata.bin" ]] || { echo "[verify][macOS] Missing embedding coremldata.bin"; exit 1; }
echo "[verify][macOS] OK"

echo "[verify] Finding an available iOS Simulator..."
SIM_NAME=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/{print $1}' | sed 's/^ *//;s/ *$//' | head -n1)
if [[ -z "$SIM_NAME" ]]; then
  echo "[verify][iOS] ERROR: No iPhone simulator available"
  exit 1
fi
echo "[verify] Using simulator: $SIM_NAME"

echo "[verify] Building iOS Simulator app (Debug)..."
xcodebuild -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

IOS_APP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/SwiftScribe-*/Build/Products/Debug-iphonesimulator/SwiftScribe.app | tail -n1)
if [[ ! -d "$IOS_APP" ]]; then
  echo "[verify][iOS] ERROR: SwiftScribe.app (simulator) not found"
  exit 1
fi

IOS_MODELS="$IOS_APP/speaker-diarization-coreml"
echo "[verify][iOS] Checking models in: $IOS_MODELS"
[[ -d "$IOS_MODELS/pyannote_segmentation.mlmodelc" ]] || { echo "[verify][iOS] Missing pyannote_segmentation.mlmodelc"; exit 1; }
[[ -f "$IOS_MODELS/pyannote_segmentation.mlmodelc/coremldata.bin" ]] || { echo "[verify][iOS] Missing segmentation coremldata.bin"; exit 1; }
[[ -d "$IOS_MODELS/wespeaker_v2.mlmodelc" ]] || { echo "[verify][iOS] Missing wespeaker_v2.mlmodelc"; exit 1; }
[[ -f "$IOS_MODELS/wespeaker_v2.mlmodelc/coremldata.bin" ]] || { echo "[verify][iOS] Missing embedding coremldata.bin"; exit 1; }
echo "[verify][iOS] OK"

echo "[verify] All checks passed."

# Optionally run the iOS unit test that verifies bundling in the simulator.
echo "[verify] Running iOS unit test for bundle presence..."
xcodebuild -scheme SwiftScribe-iOS-Tests \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  test >/dev/null
echo "[verify] iOS unit test passed."

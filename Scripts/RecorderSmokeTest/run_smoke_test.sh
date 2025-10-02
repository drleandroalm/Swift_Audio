#!/usr/bin/env bash
set -euo pipefail

SCHEME="SwiftScribe"
DEST="platform=macOS,arch=arm64"
TEST_ID=${TEST_ID:-"ScribeTests/TranscriberSmokeTests"}

echo "[smoke] Building + running smoke test: $TEST_ID"
NSUnbufferedIO=YES xcodebuild -scheme "$SCHEME" -destination "$DEST" -only-testing:"$TEST_ID" test

echo "[smoke] Done. Check xcodebuild output above for PASS/FAIL."

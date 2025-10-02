#!/usr/bin/env bash
set -euo pipefail

# Capture 80s of logs for the SwiftScribe process and print key markers
# Usage: ./Scripts/capture_80s_markers.sh

SCHEME=${SCHEME:-SwiftScribe}
DEST=${DEST:-"platform=macOS,arch=arm64"}
CONFIG=${CONFIG:-Debug}
LOGFILE=${LOGFILE:-/tmp/swiftscribe_80s_$(date +%s).log}
MODELS=${MODELS:-${FLUID_AUDIO_MODELS_PATH:-"$PWD/speaker-diarization-coreml"}}
AUTO_REC=${SS_AUTO_RECORD:-1}

echo "[cap] Building $SCHEME ($CONFIG)…"
xcodebuild -scheme "$SCHEME" -destination "$DEST" -configuration "$CONFIG" build >/dev/null

APP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/SwiftScribe-*/Build/Products/"$CONFIG"/SwiftScribe.app 2>/dev/null | tail -n1)
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "[cap][ERROR] App not found after build" >&2
  exit 1
fi
echo "[cap] App: $APP"

echo "[cap] Starting log stream → $LOGFILE"
: > "$LOGFILE"
# Capture both unified logging and the app's stdout/stderr into the same file
log stream --style compact --predicate 'process == "SwiftScribe"' >> "$LOGFILE" 2>&1 &
LPID=$!
sleep 1

echo "[cap] Launching app binary; capturing for 80s…"
APP_BIN="$APP/Contents/MacOS/SwiftScribe"
# Also append the app's stdout/stderr to the same logfile so print()/AppLogger messages are captured
SS_AUTO_RECORD="$AUTO_REC" FLUID_AUDIO_MODELS_PATH="$MODELS" "$APP_BIN" >> "$LOGFILE" 2>&1 &
APID=$!
sleep 80

echo "[cap] Stopping app and logger…"
kill "$APID" >/dev/null 2>&1 || pkill -x SwiftScribe || true
sleep 1
kill "$LPID" || true
sleep 1

echo "[cap] Matched markers (time‑ordered):"
echo "---"
rg -n -S \
  -e "Primeiro buffer recebido" \
  -e "Nenhum áudio detectado" \
  -e "Motor de gravação iniciado" \
  -e "dispositivo=" \
  -e "Recording session starting" \
  -e "Audio session configured" \
  -e "AVAudioEngine started" \
  -e "First buffer received" \
  -e "No audio detected" \
  -e "Recorder did stop with cause" \
  -e "Diarization manager initialized" \
  "$LOGFILE" || true
echo "---"

echo "[cap] Log saved at: $LOGFILE"

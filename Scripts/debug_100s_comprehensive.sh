#!/usr/bin/env bash
# Comprehensive 100-second debug logging with all subsystems

set -e

TIMESTAMP=$(date +%s)
LOGFILE="/tmp/swiftscribe_debug_100s_${TIMESTAMP}.log"
MODELS_PATH="$PWD/speaker-diarization-coreml"

echo "🔍 Starting 100-second comprehensive debug session"
echo "📄 Log file: $LOGFILE"
echo "⏰ Timestamp: $(date)"
echo ""

# Find app bundle from latest build (exclude Index.noindex)
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "SwiftScribe.app" -type d | grep -v "Intermediates" | grep -v "Index.noindex" | head -n 1)
if [ -z "$APP_PATH" ]; then
    echo "❌ Error: SwiftScribe.app not found in DerivedData"
    echo "Run: xcodebuild -project SwiftScribe.xcodeproj -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' -configuration Debug build"
    exit 1
fi

APP_BINARY="$APP_PATH/Contents/MacOS/SwiftScribe"
echo "📦 App bundle: $APP_PATH"
echo "🎯 Binary: $APP_BINARY"
echo ""

# Verify models
if [ ! -d "$MODELS_PATH" ]; then
    echo "⚠️  Warning: Model path not found: $MODELS_PATH"
else
    echo "✅ Models found at: $MODELS_PATH"
fi

# Start comprehensive log capture (all categories, debug level)
echo "📡 Starting log capture..."
log stream \
    --predicate 'process == "SwiftScribe"' \
    --level debug \
    --style compact > "$LOGFILE" 2>&1 &
LOG_PID=$!

sleep 2  # Give logger time to start

# Launch app with debug environment
echo "🚀 Launching SwiftScribe with auto-record..."
SS_AUTO_RECORD=1 \
FLUID_AUDIO_MODELS_PATH="$MODELS_PATH" \
DEBUG=1 \
"$APP_BINARY" > /tmp/swiftscribe_stdout_${TIMESTAMP}.log 2>&1 &
APP_PID=$!

echo "⏱️  App PID: $APP_PID"
echo "⏱️  Capturing logs for 100 seconds..."
echo ""

# Progress indicator
for i in {1..20}; do
    sleep 5
    if ! kill -0 $APP_PID 2>/dev/null; then
        echo "⚠️  App terminated early at $((i*5)) seconds"
        break
    fi
    echo "   [$((i*5))s] App running..."
done

# Terminate processes
echo ""
echo "🛑 Terminating app..."
kill $APP_PID 2>/dev/null || true
sleep 2
kill -9 $APP_PID 2>/dev/null || true

echo "🛑 Stopping log capture..."
kill $LOG_PID 2>/dev/null || true
sleep 1

echo ""
echo "✅ Log capture complete"
echo "📄 Main log: $LOGFILE"
echo "📄 Stdout/stderr: /tmp/swiftscribe_stdout_${TIMESTAMP}.log"
echo ""
echo "📊 Log statistics:"
wc -l "$LOGFILE" || true
echo ""
echo "🔍 Quick analysis:"
echo "  - Error count: $(grep -c -i "error" "$LOGFILE" || echo 0)"
echo "  - Warning count: $(grep -c -i "warning" "$LOGFILE" || echo 0)"
echo "  - Audio events: $(grep -c "AudioPipeline\|AVAudioEngine" "$LOGFILE" || echo 0)"
echo "  - Speech events: $(grep -c "Speech" "$LOGFILE" || echo 0)"
echo ""
echo "View logs with:"
echo "  less $LOGFILE"
echo "  grep -i error $LOGFILE"
echo "  grep 'AudioPipeline' $LOGFILE"

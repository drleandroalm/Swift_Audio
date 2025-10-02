# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Swift Scribe is an AI-powered speech-to-text transcription application built exclusively for iOS 26/macOS 26+ using Apple's latest frameworks. It provides real-time voice transcription, on-device AI processing, speaker diarization, and intelligent note-taking with complete privacy protection.

## Critical System Requirements

**IMPORTANT**: This project requires bleeding-edge Apple platforms:
- **iOS 26 Beta or newer** (will NOT work on iOS 25 or earlier)
- **macOS 26 Beta or newer** (will NOT work on macOS 25 or earlier)
- **Xcode Beta** with Swift 6.2+ toolchain
- **Apple Developer Account** with beta access

## Essential Development Commands

### Building
```bash
# macOS (ARM64)
xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' build

# iOS Simulator
xcodebuild -scheme SwiftScribe -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Clean build
xcodebuild clean -project SwiftScribe.xcodeproj -scheme SwiftScribe
```

### Testing
```bash
# macOS tests (18 tests, ~1.6s runtime)
xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' test

# iOS Simulator tests
xcodebuild -scheme SwiftScribe-iOS-Tests -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# CLI smoke test (deterministic, avoids XCTest finalize issues)
Scripts/RecorderSmokeCLI/run_cli.sh Audio_Files_Tests/Audio_One_Speaker_Test.wav

# Verify bundled models (CI verification)
Scripts/verify_bundled_models.sh
```

### Debugging & Development Tools
```bash
# Capture 80s of logs with audio markers
Scripts/capture_80s_markers.sh

# Auto-record mode (Debug only)
SS_AUTO_RECORD=1 open -a SwiftScribe.app

# URL trigger (requires setting enabled)
open 'swiftscribe://record'
```

## High-Level Architecture

### Core Component Flow

The application uses a **three-pipeline architecture** where audio processing, speech recognition, and speaker identification run concurrently:

```
Microphone Input
    ↓
AVAudioEngine (dual-engine: recording + playback)
    ↓
Buffer Conversion (native format → 16kHz mono Float32)
    ↓
    ├─→ SpeechTranscriber (Apple Speech framework)
    ├─→ DiarizationManager (FluidAudio speaker separation)
    └─→ AVAudioFile (disk storage)
    ↓
SwiftData Persistence (Memo, Speaker, SpeakerSegment)
    ↓
SwiftUI (real-time updates via @Observable/@Published)
```

### Dual Audio Engine Pattern

**Critical Design**: Two separate `AVAudioEngine` instances prevent conflicts:
- `recordingEngine`: Captures microphone input
- `playbackEngine`: Handles audio file playback

This enables simultaneous recording and playback without audio routing conflicts. Located in `Scribe/Audio/Recorder.swift`.

### Audio Processing Pipeline (Three-Stage Conversion)

**Stage 1 - Tap Installation** (`Recorder.swift:409-440`):
- Install tap at device **native format** (48kHz stereo Bluetooth, 44.1kHz USB, etc.)
- Dynamic buffer sizing: 4096 frames for Bluetooth, 2048 for others
- Disables voice processing to avoid CoreAudio HAL errors

**Stage 2 - Format Conversion** (`Recorder.swift:462-504`, `BufferConversion.swift`):
- Convert to `SpeechAnalyzer.bestAvailableAudioFormat()` (typically 16kHz mono Float32)
- Uses cached `AVAudioConverter` with `.none` primeMethod (prevents timestamp drift)
- Single conversion point to avoid double-conversion errors

**Stage 3 - ML Consumer Distribution**:
- **Transcription**: `SpokenWordTranscriber` streams via `AsyncStream<AnalyzerInput>`
- **Diarization**: `DiarizationManager` converts to `[Float]` arrays for CoreML
- **Storage**: Original buffers written to WAV file

### SwiftData Persistence Strategy

**Entity Relationship Diagram**:
```
Memo (1) ─────< (M) SpeakerSegment (M) >───── (1) Speaker
  │                    │
  │                    └─ embedding: Data (FloatArrayCodec)
  │                    └─ startTime, endTime, confidence
  │
  ├─ text: AttributedString (with audioTimeRange)
  ├─ summary: AttributedString? (AI-generated)
  ├─ url: URL? (audio file)
  └─ @Transient diarizationResult: DiarizationResult?
```

**Key Implementation**: `SpeakerSegment` entities store precise timing + embeddings, enabling:
- Token-level speaker attribution via `audioTimeRange` matching
- Per-speaker analytics (duration, turn counts, percentages)
- Timeline visualization with color-coded segments
- Cross-session speaker persistence

### Real-Time vs Batch Diarization

**Two-Phase Processing** (`DiarizationManager.swift`):

1. **Live Mode** (optional, `enableRealTimeProcessing=true`):
   - Processes audio windows (default 3s, adaptive 1-6s)
   - Runs off-main via `InferenceExecutor.shared.run`
   - Posts `resultNotification` for incremental UI updates
   - Adaptive backpressure: drops oldest samples when buffer exceeds limit

2. **Final Pass** (always runs):
   - Processes entire `fullAudio` buffer at recording stop
   - Guarantees comprehensive attribution (no windowing artifacts)
   - Returns complete `DiarizationResult` with all segments

### Speaker Attribution via AttributedString

**Token-Time Alignment** (`Recorder.swift:763-785`, `MemoModel.swift:203-214`):
```swift
// Iterate through attributed runs with audio timing
memo.text.runs.forEach { run in
    let audioTimeRange = memo.text[run.range].audioTimeRange
    let mid = (audioTimeRange.start.seconds + audioTimeRange.end.seconds) * 0.5

    // Find overlapping diarization segment
    if let segment = segments.first(where: { mid >= $0.startTime && mid < $0.endTime }) {
        // Apply speaker color + metadata
        attributed[run.range].foregroundColor = speaker.displayColor
        attributed[run.range][.speakerIDKey] = segment.speakerId
    }
}
```

**Key Insight**: Uses run **midpoint** rather than range overlap to handle boundary cases cleanly.

## Critical Integration Points

### 1. FluidAudio Vendoring (Offline-Only)

**Location**: `Scribe/Audio/FluidAudio/` (diarization only, ASR excluded)

**Model Resolution Order** (`DiarizationManager.swift:161-215`):
1. `FLUID_AUDIO_MODELS_PATH` environment variable override
2. App bundle resource: `Bundle.main.resourceURL/speaker-diarization-coreml/`
3. Repository checkout: `./speaker-diarization-coreml/`
4. **No remote fallback** - throws clear error if models missing

**Required Models**:
- `pyannote_segmentation.mlmodelc` - Speech activity segmentation
- `wespeaker_v2.mlmodelc` - Speaker embeddings (256-dim)

**Symbol Collision Resolution**: FluidAudio's `Speaker` renamed to `FASpeaker` to avoid conflict with SwiftData `Speaker` model.

### 2. Audio Format Handshake

**Challenge**: Avoid double conversion and format mismatches between recording and transcription.

**Solution** (`Recorder.swift:159-160`, `Transcription.swift:106-125`):
```swift
// Cache analyzer's preferred format during setup (avoids @MainActor conflicts)
self.preferredStreamFormat = await MainActor.run {
    (transcriber as? SpokenWordTranscriber)?.analyzerFormat
}

// Use cached format for conversion
converterTo16k = AVAudioConverter(from: inputFormat, to: preferredStreamFormat!)
```

**Result**: Single conversion path directly to Speech framework requirements.

### 3. Cross-Session Speaker Persistence

**Flow** (`DiarizationManager.swift:388-410`):
```swift
// Before recording starts
func loadKnownSpeakers(from context: ModelContext) async {
    let speakers = try? context.fetch(FetchDescriptor<Speaker>())
    for speaker in speakers where speaker.embedding != nil {
        diarizer.upsertRuntimeSpeaker(
            id: speaker.id,
            embedding: speaker.embedding,
            duration: 0
        )
    }
}
```

**Benefit**: New recordings automatically match against known speakers via cosine distance comparison (threshold 0.65).

### 4. Concurrency & Thread Safety

**Actor Isolation Strategy**:

| Component | Isolation | Rationale |
|-----------|-----------|-----------|
| `SpokenWordTranscriber` | `@MainActor` | Updates `@Published` for SwiftUI |
| `DiarizationManager` (app) | `@MainActor` + `@Observable` | SwiftUI state management |
| `DiarizerManager` (FluidAudio) | None | CPU-bound ML, runs off-main |
| `SpeakerManager` | `DispatchQueue.sync` | Thread-safe in-memory database |
| `Recorder` | `@unchecked Sendable` | Manual sync via `audioQueue` |

**Key Pattern**: `Recorder.audioQueue` (`.userInteractive` QoS) wraps all AVAudioEngine operations to prevent QoS inversions and main-thread blocking.

## Development-Specific Guidance

### Model Warmup (Critical for Smooth UX)

**Problem**: Cold-start ML model loading causes ~2-3s delay on first recording.

**Solution**: Preload models off-main thread before UI interaction (`ModelWarmupService.swift`):
```swift
// Called at app launch and before recording
ModelWarmupService.shared.warmupIfNeeded()
```

**Call Sites**:
- `ScribeApp.init()` - App launch
- `ScribeApp.body.task` - View appears
- `TranscriptView.onAppear` - Before recording UI

### Adaptive Backpressure Controls

**Problem**: Long recordings with real-time diarization can accumulate audio faster than ML inference processes.

**Safeguards** (`DiarizationManager.swift:241-278`):
1. **Buffer limit**: Drops oldest samples when `audioBuffer` exceeds `maxLiveBufferSeconds` (default 8s)
2. **Adaptive window**: Increases processing window when inference takes >80% of window duration
3. **Adaptive pause**: Disables real-time after 3 consecutive drops, resumes after 15s cooldown
4. **UI notifications**: Posts `backpressureNotification` for user feedback

### Known Issue: macOS XCTest Finalize "nilError"

**Problem**: Speech framework throws opaque `nilError` during test teardown when calling `finishTranscribing()` in XCTest context.

**Workarounds**:
- Mark macOS smoke tests with `XCTSkip` by default (`TranscriberSmokeTests.swift`)
- Use CLI smoke tests for deterministic output (`Scripts/RecorderSmokeCLI/`)
- CI relies on CLI tests, not XCTest for Speech pipeline validation

### Swift 6 Type-Checker Relief

**Problem**: `TranscriptView.body` exceeded type-checker complexity limits (2000+ lines).

**Solutions Applied**:
1. **View Splitting**: Extract `LiveRecordingContentView`, `FinishedMemoContentView`, `BannerOverlayView`
2. **AnyView Erasure**: Wrap platform conditionals and mode switches
3. **ViewModifier Extraction**: `RecordingHandlersModifier` centralizes all event handlers
4. **iOS Toolbar Split**: `IOSPrincipalToolbar` builder for complex navigation bar

**Result**: Compile time reduced from 30s+ to <5s.

### Bluetooth Audio HAL Handling

**Problem**: Bluetooth devices with small tap buffers (2048) cause `kAudioUnitErr_CannotDoInCurrentContext` errors.

**Solution** (`Recorder.swift:409-440`):
- Detect Bluetooth via `AVAudioSession.currentRoute` (iOS) or port type (macOS)
- Use **4096 frame buffer** for Bluetooth, **2048 for others**
- Install tap at device native format (stability over format matching)

### URL Scheme Automation

**Registration Required**: Add to `Info.plist` (see README.md for XML snippet)

**Scheme**: `swiftscribe://record` triggers auto-record if `settings.allowURLRecordTrigger` enabled.

**Handler Flow**:
```
ScribeApp.onOpenURL → NotificationCenter.post(.urlTriggeredRecord)
  → TranscriptView.onReceive → recorder.record()
```

**Use Cases**: Automation scripts, Shortcuts integration, external triggers.

## Testing Infrastructure

### Test Suites (18 Tests, ~1.6s Runtime)

**Unit Tests** (`ScribeTests/`):
- `ScribeTests.swift` - AppSettings initialization and configuration
- `DiarizationManagerTests.swift` - Real-time vs batch processing with mock diarizer
- `SwiftDataPersistenceTests.swift` - Speaker/segment persistence and relationships
- `MemoAIFlowTests.swift` - AI content generation with mock generators
- `RecordingFlowTests.swift` - End-to-end recording scenarios (no real audio)

**Integration Tests**:
- `OfflineModelsVerificationTests.swift` - Verifies bundled CoreML models in app bundle
- `TranscriberSmokeTests.swift` - Real Speech pipeline (marked `XCTSkip` on macOS)

**Smoke Tests** (Deterministic):
- `Scripts/RecorderSmokeCLI/run_cli.sh` - Headless transcription pipeline test
- Processes known WAV file, validates output without XCTest flakiness

### CI Verification

**GitHub Actions Workflow** (`.github/workflows/ci.yml`):
1. Build & test macOS target
2. Verify bundled models (`Scripts/verify_bundled_models.sh`)
3. Optional: CLI smoke test with reference audio
4. Build & test iOS Simulator target

**Model Verification**: Ensures `speaker-diarization-coreml/` folder + `coremldata.bin` files present in both macOS and iOS bundles.

## Project Structure

```
Scribe/
├── Audio/                      # Audio capture & diarization
│   ├── Recorder.swift          # Dual AVAudioEngine, 790 lines
│   ├── DiarizationManager.swift # App-level diarization wrapper, 715 lines
│   └── FluidAudio/             # Vendored speaker diarization library
│       ├── Diarizer/           # DiarizerManager, SegmentationProcessor, etc.
│       └── Shared/             # ANEMemoryUtils, AppLogger
├── Transcription/
│   └── Transcription.swift     # SpeechTranscriber integration, 427 lines
├── Models/
│   ├── MemoModel.swift         # SwiftData Memo model, 349 lines
│   ├── SpeakerModels.swift     # Speaker + SpeakerSegment models, 196 lines
│   └── AppSettings.swift       # Observable settings (40+ properties)
├── Views/
│   ├── ContentView.swift       # Navigation split view
│   ├── TranscriptView.swift    # Recording/playback UI, 2060 lines
│   ├── SettingsView.swift      # Settings interface
│   ├── Speaker*.swift          # Enrollment, enhance, rename, verify
│   ├── Components/             # Reusable UI components
│   └── Modifiers/              # Custom view modifiers
├── Helpers/
│   ├── FoundationModelsHelper.swift # On-device AI wrapper
│   ├── ModelWarmupService.swift     # ML preloading
│   ├── BufferConversion.swift       # Audio format conversion
│   ├── MicrophoneSelector.swift     # Cross-platform device selection
│   ├── AudioDevices.swift           # macOS CoreAudio helpers
│   ├── SpeakerIO.swift              # Speaker profile import/export
│   ├── TranscriptExport.swift       # JSON/Markdown export
│   └── WaveformGenerator.swift      # RMS waveform visualization
└── ScribeApp.swift             # App entry point, 42 lines

ScribeTests/                    # Unit & integration tests
Scripts/                        # Build verification & smoke tests
speaker-diarization-coreml/     # Bundled CoreML models (offline)
```

## Framework Dependencies

**Apple Frameworks**:
- **SwiftUI** - Declarative UI with `@Observable` pattern
- **SwiftData** - Object persistence with `@Model` macro
- **Speech** - Real-time transcription (`SpeechAnalyzer`, `SpeechTranscriber`)
- **AVFoundation** - Audio capture, playback, file I/O
- **FoundationModels** - On-device AI text generation (iOS 18+/macOS 15+)

**External Dependencies**:
- **FluidAudio** (vendored, no Swift Package) - Professional speaker diarization
  - Source: `https://github.com/FluidInference/FluidAudio/`
  - Provides `DiarizerManager`, `SpeakerManager`, CoreML model integration

## Key Architectural Strengths

1. **Privacy-First**: All processing on-device (no network calls, fully offline)
2. **Resilience**: Retry logic, format change handling, graceful degradation
3. **Performance**: Zero-copy buffers, adaptive processing, model warmup
4. **Cross-Platform**: Conditional compilation for iOS/macOS differences
5. **Modern Swift**: Swift 6 concurrency, strict sendability, actor isolation
6. **Testability**: Protocol injection, mock diarizers, deterministic tests

## Common Development Tasks

### Adding New AI Features
1. Extend `FoundationModelsHelper.swift` with generation methods
2. Update `MemoModel.swift` to store AI-generated content
3. Modify `TranscriptView.swift` to trigger AI processing

### Extending Speaker Diarization
1. Update `SpeakerModels.swift` for new speaker metadata
2. Modify `DiarizationManager.swift` for additional FluidAudio features
3. Enhance `MemoModel.swift` speaker attribution methods

### UI Enhancements
1. Update both iOS and macOS code paths in views
2. Test navigation and layout on different screen sizes
3. Use `AnyView` erasure for complex conditional UI (trade compile time for runtime overhead)

## Troubleshooting

### Build Issues
- **"No such module 'Speech'"**: Ensure deployment target is iOS 26+/macOS 26+
- **Type-checker timeout**: Split complex views, use `AnyView` for conditionals
- **Missing models error**: Run `Scripts/verify_bundled_models.sh` to check bundle

### Runtime Issues
- **Recording stops at ~13s**: Check model warmup is enabled (`ModelWarmupService`)
- **Bluetooth audio HAL errors**: Verify dynamic buffer sizing (4096 for BT)
- **XCTest finalize crashes**: Use CLI smoke tests instead (`RecorderSmokeCLI`)

### Performance Issues
- **High CPU during recording**: Enable adaptive backpressure, increase processing window
- **UI jank during live diarization**: Disable real-time processing, use final pass only
- **Slow cold-start**: Ensure `ModelWarmupService.warmupIfNeeded()` called at app launch

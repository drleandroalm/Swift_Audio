# Swift Scribe — Next Instance Knowledge (v5)

This document is a comprehensive knowledge base and current project status for a future Codex CLI instance to ramp up and continue work seamlessly. It summarizes architecture, recent fixes, operational flows, test/CI strategy, capture tooling, and practical references to key files. Treat this as your go‑to context brief + playbook.

## Snapshot
- Platforms: iOS 26, macOS 26 (Xcode beta, Swift 6)
- macOS builds on ARM64; iOS validated on iPhone 16/17 Sim.
- Offline‑first diarization with FluidAudio models bundled. No network downloads at runtime.

## Architecture
- Recorder: `Scribe/Audio/Recorder.swift`
  - Separate AVAudioEngines for record/playback, deterministic teardown, watchdog to recover from HAL churn.
  - macOS only: binds the selected input device for the whole session; reasserts on watchdog restarts.
  - Emits OSLog markers in EN + pt‑BR for capture tooling.
- Transcriber: `Scribe/Transcription/Transcription.swift`
  - Apple SpeechAnalyzer + SpokenWordTranscriber with volatile & final transcript publishing.
- Diarization: `Scribe/Audio/DiarizationManager.swift`
  - Streaming + final pass. Heavy diarization calls run fully off the main thread (background queue wrapper).
  - Backpressure controls + adaptive windowing; throttled UI notifications to avoid banner blinking.
- SwiftUI Views: `Scribe/Views/*`
  - TranscriptView deep‑split for Swift 6 stability; handlers consolidated in a modifier.
  - SettingsView exposes diarization + real‑time + backpressure + automation toggles.
- Models & Persistence: SwiftData for `Memo`, `Speaker`, `SpeakerSegment`.

## Offline Models & Packaging
- Models in `speaker-diarization-coreml/` and bundled via folder reference.
- Loader order: `FLUID_AUDIO_MODELS_PATH` → app bundle → repo.
- CI script asserts presence of mlmodelc and coremldata.bin.

## Key Stabilizations (Resolved Bug at ~13–15s)
- Root cause: main‑thread stalls caused by heavy ML init/inference overlapping with SwiftUI updates.
- Fixes:
  - Model warmup off main (App init), reset flows, deterministic teardown.
  - Deep split of TranscriptView to tame Swift 6 type‑checker timeouts.
  - Heavy diarization off main: performCompleteDiarization now runs on a user‑initiated global queue.
  - Device binding (macOS): bind current input device per session; reassert on restarts to mitigate HAL Pause/Resume.
  - OSLog markers (EN + pt‑BR) emitted by Recorder for capture.
  - Backpressure notifications throttled (manager + UI) to avoid blinking warning banner.

## Automation & Headless Triggers
- Auto‑record (Debug only): set `SS_AUTO_RECORD=1` or pass `--headless-record` to route into the recording screen and start automatically.
- URL trigger (macOS): `swiftscribe://record`
  - Enable/disable in Settings → Automação.
  - Note: registering the URL scheme (CFBundleURLTypes) requires Xcode project settings. Handler code exists (`.onOpenURL`) and posts `SSTriggerRecordFromURL`.

## 80s Capture & Markers
- Use `Scripts/capture_80s_markers.sh`:
  - Builds the app, launches the macOS binary directly, streams 80s of OSLog to `/tmp/swiftscribe_80s_<ts>.log`.
  - Honors env: `SS_AUTO_RECORD=1`, `FLUID_AUDIO_MODELS_PATH`.
  - Greps EN/PT markers: “AVAudioEngine started”, “First buffer received”, “No audio detected”, “Recorder did stop…”, “Diarization manager initialized”, “Motor de gravação iniciado”, “Primeiro buffer recebido”, “Nenhum áudio detectado”, `dispositivo=`.

## Tests & CI
- macOS unit tests pass; iOS Simulator bundling tests pass; model packaging verified via `Scripts/verify_bundled_models.sh`.
- Smoke tests: macOS XCTest finalize path is flaky (“nilError”). They are skipped by default on macOS/CI; use the CLI for deterministic coverage.
  - CLI: `Scripts/RecorderSmokeCLI/run_cli.sh <wav>` prints volatile/final transcripts continuously.

## Files Touched for Latest Fixes
- Off‑main diarization & throttled backpressure
  - `Scribe/Audio/DiarizationManager.swift` — added `runOffMain` (global queue), wrapped init/perform calls, throttled backpressure notifications, raised `maxLiveBufferSeconds` default.
- Automation triggers
  - `Scribe/ScribeApp.swift` — `.onOpenURL` handler posting `SSTriggerRecordFromURL` (macOS).
  - `Scribe/Views/ContentView.swift` — observes `SSTriggerRecordFromURL`, navigates to memo and starts recording; also routes on `SS_AUTO_RECORD`/`--headless-record`.
  - `Scribe/Models/AppSettings.swift` — `allowURLRecordTrigger` toggle with persistence.
  - `Scribe/Views/SettingsView.swift` — Automação group toggle.
- Recorder logs & device binding
  - `Scribe/Audio/Recorder.swift` — OSLog markers in pt‑BR, bind/reassert input device for macOS sessions.
- Capture & tools
  - `Scripts/capture_80s_markers.sh` — launches binary with env, scans EN/PT markers.

## Current Status Summary
- Recurrent ~13–15s halt eliminated (rooted in main‑thread pressure and ML init overlap).
- Recording robust on macOS (device binding, watchdog recoveries, voice‑processing disabled); iOS behaves as expected.
- “Alto uso: Reduzindo a latência…” banner no longer blinks; notifications are throttled with a cooldown and appear only during sustained backpressure.
- Deterministic smoke: use the CLI; GUI capture integrates auto‑record and markers.

## Future Suggestions
- Consider adding a URL scheme to the Xcode project (CFBundleURLTypes) to enable the handler fully in release builds.
- Optional CI step: run CLI smoke after unit tests for deterministic pipeline coverage.
- Continue isolating diarizer CPU and transcriber finalize paths from main‑thread; watch Swift Concurrency warnings and adjust with @preconcurrency or value captures.

## Quick Commands
- macOS build: `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' build`
- macOS tests: `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' test`
- iOS tests: `xcodebuild -scheme SwiftScribe-iOS-Tests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
- Verify models (both bundles): `Scripts/verify_bundled_models.sh`
- 80s capture (auto‑record + models): `SS_AUTO_RECORD=1 MODELS=$PWD/speaker-diarization-coreml Scripts/capture_80s_markers.sh`
- CLI smoke: `Scripts/RecorderSmokeCLI/run_cli.sh Docs/Audio_Files_Tests/Audio_One_Speaker_Test.wav`


# Swift Scribe — Next Instance Knowledge (v4)

This v4 knowledge base codifies the current architecture, packaging rules, CI, and testing for Swift Scribe after enabling strict offline model bundling and dual‑platform verification (macOS + iOS Simulator).

## Snapshot
- Platforms: iOS 26, macOS 26 (Xcode beta, Swift 6)
- ARM64 macOS builds are preferred; iOS Simulator validated on iPhone 16 Pro.
- Third‑party: FluidAudio for diarization + embeddings.

## Architecture & Key Modules
- Audio capture/playback: `Scribe/Audio/Recorder.swift` (separate engines, safe teardown).
- Transcription: `Scribe/Transcription/Transcription.swift` (SpeechAnalyzer + SpeechTranscriber; tokens carry `audioTimeRange`).
- Diarization: `Scribe/Audio/DiarizationManager.swift` (streaming windows + final pass; known speaker upsert; enforced offline models).
- Alignment: Tokens → diarization segments → precise coloring and segments.
- Persistence/UI: SwiftData (`Memo`, `Speaker`, `SpeakerSegment`) and SwiftUI (`TranscriptView`, Falantes, Settings) with scrubber + optional waveform.

## Packaging & Models (Offline‑First)
- Models live in `speaker-diarization-coreml/` and are bundled via a folder reference in the app Resources.
- Loader resolution order: `FLUID_AUDIO_MODELS_PATH` → app bundle → repo folder.
- Remote downloads are disabled. If no local models are found, initialization throws a configuration error with guidance.
- Tests verify presence of:
  - `pyannote_segmentation.mlmodelc/coremldata.bin`
  - `wespeaker_v2.mlmodelc/coremldata.bin`

## Export & Entitlements
- macOS transcript/unified export uses `NSSavePanel`.
- macOS speakers export now prefers `NSSavePanel` and falls back to app container Documents with Finder reveal if unavailable/failing.
- Ensure macOS entitlement: “User Selected File Read/Write”.
- `NSMicrophoneUsageDescription` fixed and localized via `InfoPlist.strings` (Base, pt‑BR).

## Runtime Features (Stable)
- Real‑time and final diarization via FluidAudio; token‑time alignment for precise coloring.
- Speaker lifecycle: enroll (multi‑clip + file import on macOS), rename, enhance (fusion), verify (one‑shot + continuous) with global + per‑speaker thresholds.
- Falantes view: cards, context menu (Salvar como conhecido, Renomear, Aprimorar, Verificar), analytics with gradient bars.
- Transcript view: segmented header (Transcrição/Resumo/Falantes), quick actions, compact toolbar, floating scrubber with optional waveform.
- Unified export: combined JSON with transcript + speakers (iOS Files exporter; macOS Save Panel + fallback).

## CI & Verification
- Script: `Scripts/verify_bundled_models.sh`
  - Builds macOS (Debug, arm64) and iOS Simulator app, asserts presence of required models and `coremldata.bin` files in bundles.
  - Runs iOS unit test verifying bundling using scheme `SwiftScribe-iOS-Tests`.
- GitHub Actions: `.github/workflows/ci.yml`
  - Job `macos-tests`: runs macOS unit tests on ARM64.
  - Job `ios-verify-models`: depends on `macos-tests`; executes the verify script ensuring packaging regressions fail PRs.
  - Job `cli-smoke`: depends on `macos-tests`; runs RecorderSmokeCLI on a reference WAV for deterministic transcription coverage.
 - Smoke guidance: macOS `TranscriberSmokeTests` are skipped by default due to XCTest finalize flakiness (`nilError`). Prefer the deterministic `Scripts/RecorderSmokeCLI/run_cli.sh` when you need smoke coverage in automation.

## Stability Fixes (Multi‑Memo Recording)
- Root cause: `Recorder` and `SpokenWordTranscriber` instances were retained across memo switches, so the second “Novo Memorando” reused the previous memo’s transcriber and didn’t stream new audio. Stopping then attempted enhancements on empty content, surfacing “No content to enhance error -2”.
- Fixes:
  - View identity: `TranscriptView(...).id(memo.id)` in `ContentView` to force fresh state per memo.
  - Reinit on memo change: `TranscriptView` listens to `memo.id` and reconstructs `Recorder`, cancels timers, and resets UI helpers; the transcriber is now view‑owned (`@StateObject`) and reset safely between sessions.
  - Deterministic audio teardown: new `Recorder.teardown()` stops engines, removes taps, ends continuations before rebuilding.
  - Safety net: `generateAIEnhancements()` returns early when the transcript is empty (instead of throwing and alerting).
 - Auto‑start guard: recording only auto‑starts on truly blank memos (no text, no URL, default title). Existing content means no auto‑start.
- Lifecycle crispness: when stopping, `TranscriptView` explicitly calls `finishTranscribing()` before `Recorder.stopRecording()` to ensure the recognition pipeline flushes cleanly.
  - Gentle UX: suppress the enhancement alert specifically for the “No content to enhance” error code (-2).

## Stability Fixes (v4.2)
- Resilient recording task: switched to `Task.detached` and removed cancellation checks from the audio loop so transient HAL cancellations can’t abort capture.
- Stop orchestration now awaits the recorder task (`await Task.value`) after `stopRecording()`, guaranteeing deterministic teardown before generating summaries.
- Input flow telemetry: `Recorder.hasReceivedAudio` toggles on first buffer from the tap; exposed to the UI for guardrails and troubleshooting.
- Watchdog restarts capture if no buffer arrives within ~3s: the recorder tears down and reconfigures the engine/tap without finishing the stream, handling HAL misconfigurations automatically.
- Voice-processing IO is disabled explicitly on macOS input nodes to avoid AUVoiceProcessing instantiation errors (`-10877`) when the factory is unavailable.
- Stop guard window: ignore stop presses only within the first 2s after start; allow stop afterwards even if no buffers have arrived yet (double-tap confirms).
- iOS compile stability: simplified view switching (`AnyView`) in `TranscriptView` to avoid type‑checker timeouts in Swift 6.
- Memo URL publication deferred until the recording file is created, preventing `AVAudioFile` read attempts from waveform generation before the file exists (eliminates ExtAudioFile `2003334207`).

## v4.3 — Recording Robustness & Device Selection (macOS)
- Input Device Picker (macOS) via `AudioDeviceManager` (CoreAudio); UI in Settings → “Entrada de áudio (macOS)”.
- Recorder prefers built‑in mic on session setup; user selection takes precedence.
- First‑buffer notification + UI indicator (“Aguardando áudio…” → “Mic pronto”).
- Watchdog logging includes active device name during restarts.

## Headless Verification & CLI
- XCTest smoke tests `TranscriberSmokeTests` with pre‑conversion to analyzer format and finalize fallback assertions.
- Runner: `Scripts/RecorderSmokeTest/run_smoke_test.sh` (set `TEST_ID`).
- Standalone CLI: `Scripts/RecorderSmokeCLI` prints volatile/final lines; bypasses XCTest finalize quirks.

## Headless Launch & Auto-Record (Debug)
- Auto-record flag: set `SS_AUTO_RECORD=1` to route the app directly into a new memo and start recording on launch (Debug only).
- Launch argument: pass `--headless-record` to trigger the same behavior without environment variables.
- Device binding (macOS): the recorder binds the current default input device at session start and reasserts it on watchdog restarts to mitigate HAL Pause/Resume behavior.

## Xcode 26.1 Settings Alignment
- Applied: `SWIFT_STRICT_CONCURRENCY=complete`, Debug `SWIFT_COMPILATION_MODE=singlefile`, Release `SWIFT_COMPILATION_MODE=wholemodule`, `SWIFT_OPTIMIZATION_LEVEL` (`-Onone`/`-O`), `CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED=YES`, App Release `STRIP_INSTALLED_PRODUCT=YES`.
- Still recommended to click “Update to recommended settings” once in Xcode to sync template defaults.

## Runtime Log Capture & Patterns
- Capture: use `Scripts/capture_80s_markers.sh` (builds app, launches the binary with env vars, records 80s via `log stream`).
- Env vars honored during capture:
  - `SS_AUTO_RECORD=1` forces auto‑start on launch (Debug only).
  - `FLUID_AUDIO_MODELS_PATH` points warmup to the local models folder to avoid bundle‑only lookups.
- Markers scanned (en): “AVAudioEngine started”, “Recording session starting”, “No audio detected”, “Recorder did stop with cause”, “Diarization manager initialized”.
- Markers scanned (pt‑BR): “Motor de gravação iniciado”, “Primeiro buffer recebido”, “Nenhum áudio detectado”, `dispositivo=`.
- On hosts with HAL churn (PauseIO/ResumeIO), pick Built‑in Mic in Settings and retry.

- One‑shot 80s capture script:
  - `./Scripts/capture_80s_markers.sh`
  - Builds Debug (macOS), launches the app, captures 80s of logs, and prints only matched markers:
    - “Motor de gravação iniciado” (engine start)
    - “Primeiro buffer recebido” (first input buffer)
    - “Nenhum áudio detectado” (watchdog restart)
    - `dispositivo=` (device name at restart)
  - Saves full capture to `/tmp/swiftscribe_80s_<timestamp>.log` for deeper analysis.

## Current Issues & Next Steps
- Intermittent early buffer starvation (timer stall): mitigated with device picker, built‑in preference, watchdog, and indicator; consider per‑session device binding next.
- XCTest finalize “nilError”: retain smoke fallbacks and prefer CLI for deterministic checks.

## File Index
- New: `Scribe/Helpers/AudioDevices.swift`, `Scripts/RecorderSmokeCLI/*`.
- New (SwiftUI refactor): `Scribe/Views/Components/LiveRecordingContentView.swift`, `Scribe/Views/Components/FinishedMemoContentView.swift`, `Scribe/Views/Components/BannerOverlayView.swift`, `Scribe/Views/Components/IOSPrincipalToolbar.swift`, `Scribe/Views/Modifiers/RecordingHandlersModifier.swift`.
- Updated: `Scribe/Audio/Recorder.swift`, `Scribe/Views/TranscriptView.swift`, `Scribe/Transcription/Transcription.swift`, `ScribeTests/ScribeTests.swift`, `Scripts/RecorderSmokeTest/run_smoke_test.sh`, project build settings.

## Live Updates Improvements (v4.1)
- Transcriber observation switched to `ObservableObject` with `@Published` `volatileTranscript` and `finalizedTranscript` for ultra‑smooth live updates in SwiftUI.
- The view now owns the transcriber via `@StateObject`, ensuring consistent identity and predictable lifecycle.
- Recording loop made cancellable; on stop we cancel the loop and respect `Task.checkCancellation()` inside it, eliminating post‑stop backlog processing.
- Recording timer runs in `.common` run‑loop mode to avoid stalling at 00:00 during UI interactions.
- Diarization notifications update UI on the next main‑thread tick to prevent “Modifying state during view update” warnings.

## v4.4 — SwiftUI Type-Checking Stability
- Deep split of `TranscriptView` to avoid Swift 6 type-checker timeouts on macOS builds.
- Introduced dedicated subviews for the main branches and overlays, and a consolidated `RecordingHandlersModifier` to centralize event handling.
- Separated iOS principal toolbar into its own builder to keep platform code paths lean.
- iOS build fix: guard `AudioDeviceManager` usage behind `#if os(macOS)` in `Recorder.handleNoAudioDetected()`.

## iOS Unit Tests
- Target: `ScribeTests_iOS` (shared scheme `SwiftScribe-iOS-Tests`).
- Mirrors the macOS bundle presence test; runs in simulator.

## Troubleshooting
- Save Panel issues: verify entitlement; speakers export has sandbox fallback.
- AVAudio detach/stop warnings: playback timer invalidates before teardown (implemented).
- Missing models: ensure `speaker-diarization-coreml/` is included; remote downloads are disabled by design.

## Changelog (since v3)
- Speakers export via Save Panel (with fallback) on macOS.
- Enforced offline model usage (no remote downloads).
- Fixed/Localized microphone usage description.
- Safer playback timer invalidation.
- Added iOS test target and scheme; CI verifies bundling on macOS + iOS.

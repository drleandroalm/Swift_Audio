# Swift Scribe — iOS Next Instance Guide

This guide equips a future Codex CLI instance to continue iOS development with feature parity to the macOS app. It captures current iOS status, differences vs. macOS, integration points, and a prioritized task list.

## Current iOS Status (Parity Snapshot)
- Recording + Transcription (SpeechAnalyzer/SpeechTranscriber) — parity with macOS
- Diarization (FluidAudio): live windows + full-final pass; token-time alignment — parity
- Falantes view: analytics panel, colorized transcript, speaker legend — parity
- Enrollment: multi-clip capture, mic level + progress; import audio via Files — delivered
- Verification: one-shot + continuous (auto) with threshold; Files import — delivered
- Rename: sheet action from legend — delivered
- Import/Export speakers — delivered on iOS via Files (.json)

## Bundling & CI
- Offline models are bundled with the iOS app from `speaker-diarization-coreml/`; no downloads at runtime.
- Use `Scripts/verify_bundled_models.sh` to build for iOS Simulator and assert model presence in `SwiftScribe.app/speaker-diarization-coreml/` (both `pyannote_segmentation.mlmodelc` and `wespeaker_v2.mlmodelc`).
- CI workflow `.github/workflows/ci.yml` runs the verification on Apple Silicon with latest Xcode.
 - A dedicated iOS unit test target `ScribeTests_iOS` mirrors the macOS bundle check and is runnable via the shared scheme `SwiftScribe-iOS-Tests`.

## Platform Differences & Considerations
- Audio session: iOS requires `AVAudioSession` category `.playAndRecord` and permissions strings in Info.plist (Microphone usage).
- File access: iOS uses `.fileImporter`/`.fileExporter` (UTType.json) instead of panels.
- UI: 
  - Toolbar placements differ; iOS uses compact header chips with icon-only actions.
  - Modals use `.sheet` with native presentation; ensure safe areas and keyboard avoidance.
- Performance testing: prioritize device runs for live diarization latency.

## Key iOS Entry Points
- Recording pipeline: `Scribe/Audio/Recorder.swift:1` — iOS path already present in `setUpAudioSession()`.
- Transcription: `Scribe/Transcription/Transcription.swift:1` — same across platforms.
- Diarization manager: `Scribe/Audio/DiarizationManager.swift:1` — cross-platform logic.
- Speaker views: `Scribe/Views/TranscriptView.swift:1` — iOS header contains actions for Inscrever/Exportar/Importar.
- Enrollment sheet: `Scribe/Views/SpeakerEnrollmentView.swift:1` — uses mic capture; iOS import via Files.
- Verification sheet: `Scribe/Views/SimilarityVerificationView.swift:1` — continuous mode + threshold.
- Enhancement sheet: `Scribe/Views/SpeakerEnhanceView.swift:1` — re-fuses embeddings.
- JSON IO: `Scribe/Helpers/SpeakerIO.swift:1`, `Scribe/Helpers/SpeakersDocument.swift:1`.

## iOS Parity Checklist
1) Live diarization chips and timeline — verify performance on device
2) Token-time precise colorization toggle — functional on iOS
3) Falantes analytics panel — functional and performant
4) Enrollment: multi-clip + Files import — completed
5) Verification: continuous + threshold — completed
6) Enhancement: add clips to existing speakers — completed
7) Import/Export speakers via Files — completed
8) Settings: presets, real-time window, toggles — parity
9) Offline models: ensure bundling and resolution order works on iOS build

## Testing on iOS
- Unit + UI tests: can extend ScribeTests with iOS scheme; prefer deterministic tests not relying on microphone.
- Manual QA: 
  - Verify continuous verification indicator responsiveness
  - Confirm import/export roundtrips (create JSON on device, import back)
  - Validate enhancement flow improves similarity for same speaker across sessions

## Deployment Notes
- Ensure `NSMicrophoneUsageDescription` is present and localized.
- Verify entitlements align with on-device Foundation Models and SpeechAnalyzer.
- Device testing on iOS 26 beta; confirm performance, battery impact minimal with default window sizes.

## Next Work Items (iOS)
- Add Files integration for transcript export with speaker tags (JSON/Markdown)
- Add drag-and-drop import for iPadOS, plus share sheet support
- Add per-speaker threshold presets and a global threshold in Settings
- Live UI polish: activity indicators during model loading; reduce jitter in chips during continuous verification
- Device telemetry (local-only) for timing metrics to inform presets

## Troubleshooting (iOS)
- No audio:
  - Check microphone permission and category; verify device mute
- Continuous verification unstable:
  - Raise threshold to 0.85 and use ≥1s windows in noisy environments
- Import fails:
  - Validate JSON structure and UTType.json; check app sandbox permissions

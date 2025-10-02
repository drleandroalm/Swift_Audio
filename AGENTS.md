# Repository Guidelines

This guide orients contributors and agent tooling to Swift Scribe’s offline‑first diarization app. Keep changes minimal, surgical, and aligned with the constraints below.

## Project Structure & Module Organization
- App code: `Scribe/` (FileSystem Synchronized Root Group). Anything under `Scribe/` is built into the `SwiftScribe` app target.
- Vendored FluidAudio: `Scribe/Audio/FluidAudio/`
  - App target includes only: `Diarizer/*`, `Shared/{ANEMemoryUtils,ANEMemoryOptimizer,AppLogger,SystemInfo}.swift`, `ModelNames.swift`, `FluidAudioSwift.swift`.
  - ASR/VAD live in `Disabled_FluidAudio/**` and build into `FluidAudio-ASR` (static library) not linked by the app.
- CoreML models are folder‑referenced at `speaker-diarization-coreml/`.

## Build, Test, and Development Commands
- Open in Xcode: `open SwiftScribe.xcodeproj`
- Build macOS (ARM64):
  `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' build`
  Add `ONLY_ACTIVE_ARCH=YES ARCHS=arm64` if an x86_64 slice appears.
- macOS tests: `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' test`
- iOS sim tests: `xcodebuild -scheme SwiftScribe -destination 'platform=iOS Simulator,name=iPhone 16' test`

## Coding Style & Naming Conventions
- Swift 6, four‑space indentation, trailing closures; follow Apple API Design Guidelines.
- In vendored diarizer, `Speaker` is renamed `FASpeaker` to avoid conflicts. Do not add new public symbols unless the app needs them.

## Testing Guidelines
- Tests must pass offline. Ensure these exist in the app bundle:
  - `pyannote_segmentation.mlmodelc/coremldata.bin`
  - `wespeaker_v2.mlmodelc/coremldata.bin`
- Model resolution may use only: `FLUID_AUDIO_MODELS_PATH`, app bundle `speaker-diarization-coreml/`, or repo `speaker-diarization-coreml/`.

## Commit & Pull Request Guidelines
- Commits: focused, imperative subjects ≈ ≤60 chars (e.g., `Integrate FluidAudio`).
- PRs: include user‑facing impact, test evidence, linked issues, and screenshots/clips for UI changes. Note any beta/OS dependencies.

## Security & Configuration Tips
- Copy `Configuration/SampleCode.xcconfig` to a local `.xcconfig` with your team ID to generate unique bundle IDs.
- Do not commit secrets or customer audio. Verify microphone entitlements and privacy strings. For macOS exports needing Save Panels, enable “User Selected File Read/Write”.

## Architecture Notes (Audio & Inputs)
- Input tap at device’s native format; reuse `AVAudioConverter` to 16 kHz mono Float32. Bluetooth inputs use buffer 4096; others 2048.
- Smart Microphone Selector (`Scribe/Helpers/MicrophoneSelector.swift`): default to OS mic; supports manual override (CoreAudio IDs on macOS; `AVAudioSession.availableInputs()` on iOS).

## Offline‑Only Rule (Critical)
- The app must not download models or call `DownloadUtils` in the app module. Any download helpers belong only in the `FluidAudio-ASR` library target.


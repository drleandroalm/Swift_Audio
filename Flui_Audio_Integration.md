# FluidAudio Source Integration (No Packages)

This document details every change performed to integrate FluidAudio as a first‑class, vendored source within Swift Scribe (no Swift Package dependency), and to keep the project fully offline-first. It also documents the optional separate Xcode target created to keep ASR code available in-repo but out of the app module.

## Goals

- Vendor FluidAudio source into the project (no package manager).
- Keep diarization fully offline: no downloads; models loaded locally only.
- Avoid symbol conflicts (especially `Speaker`) and strict-concurrency breakages.
- Maintain macOS 26 and iOS 26 deployment targets.
- Keep ASR sources accessible but not compiled into the app, via a separate static library target `FluidAudio-ASR`.

---

## What Was Integrated

- FluidAudio core sources from `FluidAudio_Update/Sources/FluidAudio` were embedded under:
  - `Scribe/Audio/FluidAudio/`
    - Diarizer: `Diarizer/*`
    - Shared: `Shared/{ANEMemoryUtils, ANEMemoryOptimizer, AppLogger, SystemInfo}.swift`
    - Model names: `ModelNames.swift`
    - Offline loader glue retained: `Diarizer/DiarizerModels.swift`
    - A compatibility file: `FluidAudioSwift.swift`

- ASR and VAD sources were moved out of the app module to avoid compile/link conflicts and unnecessary concurrency migrations:
  - Moved to: `Disabled_FluidAudio/ASR/**` and `Disabled_FluidAudio/VAD/**`
  - Support files moved alongside ASR:
    - `Disabled_FluidAudio/AudioConverter.swift`
    - `Disabled_FluidAudio/MLModel+Prediction.swift`

---

## Xcode Project Changes

1) Removed the Swift Package dependency on FluidAudio
- File: `SwiftScribe.xcodeproj/project.pbxproj`
- Changes:
  - Removed `XCRemoteSwiftPackageReference "FluidAudio"` and `XCSwiftPackageProductDependency` records.
  - Removed the package from `packageReferences` and the Frameworks build phase.

2) Added a new static library target: `FluidAudio-ASR`
- File: `SwiftScribe.xcodeproj/project.pbxproj`
- Target name: `FluidAudio-ASR` (product `libFluidAudioASR.a`)
- Purpose: keep ASR sources available in-repo, compiled as an independent static library, not linked into the app.
- Sources included:
  - `Disabled_FluidAudio/ASR/**` (TDT decoder, streaming ASR, managers)
  - `Disabled_FluidAudio/AudioConverter.swift`
  - `Disabled_FluidAudio/MLModel+Prediction.swift`
  - Shared files referenced by ASR and added to the ASR target as sources (not linked to the app):
    - `Scribe/Audio/FluidAudio/Shared/AppLogger.swift`
    - `Scribe/Audio/FluidAudio/Shared/ASRConstants.swift`
    - `Scribe/Audio/FluidAudio/Shared/ANEMemoryUtils.swift`
- Build settings:
  - `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
  - `MACOSX_DEPLOYMENT_TARGET = 26.0`
  - `SWIFT_VERSION = 6.0`
  - Not linked to the app target.

3) Deployment targets
- Confirmed and retained:
  - Project and app targets: `iOS 26`, `macOS 26`.
  - New `FluidAudio-ASR` target uses the same deployment targets.

---

## Source and API Adjustments (App Module)

1) Removed `import FluidAudio` from app sources/tests
- Files:
  - `Scribe/Audio/DiarizationManager.swift`
  - `Scribe/Audio/Recorder.swift`
  - `Scribe/Models/AppSettings.swift`
  - `Scribe/Models/MemoModel.swift`
  - `Scribe/Views/{TranscriptView,SpeakerEnhanceView,SpeakerEnrollmentView,SimilarityVerificationView}.swift`
  - `ScribeTests/*.swift`
- Rationale: FluidAudio is now embedded in the same module; direct `import` of the old package is not needed.

2) Resolved `Speaker` name collision
- Vendored diarizer’s `Speaker` conflicted with SwiftData model `Speaker`.
- Change:
  - Renamed all occurrences of FluidAudio’s type to `FASpeaker` across `Scribe/Audio/FluidAudio/Diarizer/*`.
  - App code continues to use its own `Speaker` SwiftData model (no import/rename required there).

3) Enforced offline models, no downloads
- Diarizer model resolution (in `Scribe/Audio/DiarizationManager.swift`) was already offline-first, and remains so:
  - Resolution order: `FLUID_AUDIO_MODELS_PATH` → app bundle resource `speaker-diarization-coreml/` → repo path `speaker-diarization-coreml/` → else throws configuration error.
  - We do not call any `download` method; `DiarizerModels.load(localSegmentationModel:localEmbeddingModel:)` is used.
- `DownloadUtils.swift` remains compiled only to satisfy references in `DiarizerModels` but is not invoked by the app.

4) Strict-concurrency and stability tweaks
- `Scribe/Audio/FluidAudio/Shared/AppLogger.swift`
  - `defaultSubsystem` changed to `static let` to avoid global mutable state warnings.
- `Scribe/Audio/FluidAudio/ASR/TDT/TdtHypothesis.swift` (before ASR was moved out of the app)
  - Dropped `Sendable` conformance to avoid non-Sendable state errors; ASR now lives in its own target.
- `Scribe/Audio/FluidAudio/DownloadUtils.swift`
  - Made internal-only, removed `public` surface, added `Sendable` conformance to config, and marked logger as `nonisolated(unsafe)` (informational only). Not used by the app.

5) Replaced `AudioConverter` usage in app views with local conversion helpers
- Files:
  - `Scribe/Views/SpeakerEnrollmentView.swift`
  - `Scribe/Views/SpeakerEnhanceView.swift`
  - `Scribe/Views/SimilarityVerificationView.swift`
- Change:
  - Removed the dependency on FluidAudio’s `AudioConverter` class.
  - Implemented local helpers that convert `AVAudioPCMBuffer` → 16kHz mono `Float` arrays using `AVAudioConverter`, with safe one-shot input blocks.
  - This keeps enrollment/enhancement/verification paths independent and reduces cross-module surface.

6) Trimmed app module surface (kept what diarization needs)
- Removed ASR and VAD folders from the app build to reduce warnings and surface area:
  - `Scribe/Audio/FluidAudio/ASR/**` → moved to `Disabled_FluidAudio/ASR/**`.
  - `Scribe/Audio/FluidAudio/VAD/**` → moved to `Disabled_FluidAudio/VAD/**`.
  - `Scribe/Audio/FluidAudio/Shared/{AudioConverter.swift, MLModel+Prediction.swift}` → moved to `Disabled_FluidAudio/*`.

7) Smart Microphone Selector + 16 kHz conversion pipeline

- Implemented `Scribe/Helpers/MicrophoneSelector.swift`:
  - Default: mimic OS default input; on macOS prefer built‑in when available.
  - Manual override (Settings → Microfone): toggle to enable + picker of available inputs; when enabled, fully bypasses the smart selector.
  - macOS uses CoreAudio device IDs; iOS uses AVAudioSession.availableInputs + setPreferredInput.
- Recorder capture pipeline:
  - Install tap at the device’s native format (stability, esp. on Bluetooth). Convert each buffer to 16 kHz mono Float32 via a reusable AVAudioConverter; use converted buffers for ML and on‑disk storage.
  - Bluetooth inputs receive larger tap buffers (4096) to reduce HAL overload; other inputs use 2048.

---

## Tests and Build Verification

- macOS build (ARM64): OK
  - `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' build`

- macOS tests: OK
  - `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' test`
  - Executed 20 tests; 0 failures.

- The new `FluidAudio-ASR` library target is present but not linked to the app scheme. It compiles on demand and keeps ASR available for future use without impacting the app.

---

## Offline-First Guarantees (No Downloads)

- The app never calls any download path; diarizer model loading strictly uses local `.mlmodelc` from `speaker-diarization-coreml/`.
- `DiarizationManager` throws a clear configuration error if models are not found.
- Model bundling is unchanged: folder reference `speaker-diarization-coreml` is included in the app resources per `project.pbxproj` Resources phase.

---

## Deployment Targets

- App target:
  - `MACOSX_DEPLOYMENT_TARGET = 26.0`
  - `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- Project-level defaults and the new `FluidAudio-ASR` target use the same values.

---

## Rationale and Tradeoffs

- Embedding only the diarizer (and shared) code in the app keeps the build lean, removes strict-concurrency friction from unrelated modules, and ensures focus on offline diarization.
- Keeping ASR in a separate target preserves the codebase for future extensions/CLIs without affecting the app.
- Minor warnings remain (e.g., future “any Protocol” wording) but do not affect correctness; they can be addressed later to further polish the vendored code.

---

## Future Enhancements (Optional)

- If desired, move `DownloadUtils.swift` to the `FluidAudio-ASR` target to fully exclude networking symbols from the app module. This would require splitting `DiarizerModels` into an offline-only file used by the app (removing the `download` functions).
- Add an Xcode scheme for `FluidAudio-ASR` to build it in CI for smoke coverage (not linked to the app).
- Add a small compile-time check/test asserting the presence of `coremldata.bin` files in the app bundle for both models (pyannote_segmentation and wespeaker_v2).

---

## Summary

- FluidAudio is now a definite, vendored part of the project (no package).
- App relies purely on offline, bundled models; no downloads or runtime network dependency for diarization.
- Symbol conflicts resolved (`FASpeaker`), and concurrency issues avoided by keeping ASR out of the app module.
- New `FluidAudio-ASR` static library target keeps ASR available for future use, without impacting app stability.

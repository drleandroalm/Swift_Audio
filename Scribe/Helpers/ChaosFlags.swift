import Foundation

/// Chaos Engineering Flags for Resilience Testing
/// Controls fault injection during test execution
///
/// **IMPORTANT**: Only active in DEBUG builds when CHAOS_ENABLED=1 environment variable is set
/// Automatically disabled in RELEASE builds via conditional compilation
///
/// Usage in tests:
/// ```swift
/// ChaosFlags.forceBufferOverflow = true
/// defer { ChaosFlags.reset() }
/// // ... run test ...
/// ```
///
/// Environment control:
/// ```bash
/// CHAOS_ENABLED=1 xcodebuild test -scheme SwiftScribe
/// ```
#if DEBUG
@available(macOS 13.0, iOS 16.0, *)
struct ChaosFlags {

    // MARK: - Master Control

    /// Global chaos enable/disable switch
    /// Set via CHAOS_ENABLED=1 environment variable
    /// All chaos injection is no-op when this is false
    static var chaosEnabled: Bool {
        ProcessInfo.processInfo.environment["CHAOS_ENABLED"] == "1"
    }

    /// Verbose logging for chaos injection events
    /// Helps debug which injection points are being triggered
    static var verboseLogging: Bool = false

    // MARK: - Audio Pipeline Chaos (6 scenarios)

    /// Force audio format mismatch (e.g., 48kHz stereo when 16kHz mono expected)
    /// Tests: Format conversion recovery, error handling
    /// Expected: App converts format or degrades gracefully
    static var forceFormatMismatch: Bool = false

    /// Inject oversized buffers (10x normal capacity)
    /// Tests: Buffer size validation, memory safety
    /// Expected: App rejects oversized buffers without crashing
    static var forceBufferOverflow: Bool = false

    /// Simulate first buffer timeout (block for 11s, watchdog fires at 10s)
    /// Tests: Watchdog recovery, tap reinstallation
    /// Expected: Watchdog triggers, tap reinstalled, recording continues
    static var simulateFirstBufferTimeout: Bool = false

    /// Force AVAudioConverter creation to fail
    /// Tests: Converter error handling, fallback paths
    /// Expected: App logs error and attempts recovery
    static var forceConverterFailure: Bool = false

    /// Inject audio route change during recording (simulate headphone disconnect)
    /// Tests: Engine reconfiguration, route change handling
    /// Expected: Engine restarts with new route
    static var injectRouteChangeDuringRecording: Bool = false

    /// Corrupt audio buffers with NaN/Inf values
    /// Tests: Audio validation, corrupted data handling
    /// Expected: Invalid buffers dropped, recording continues
    static var corruptAudioBuffers: Bool = false

    // MARK: - ML Model Chaos (6 scenarios)

    /// Simulate missing pyannote_segmentation.mlmodelc
    /// Tests: Model loading error handling, graceful degradation
    /// Expected: Continue recording without diarization
    static var simulateMissingSegmentationModel: Bool = false

    /// Simulate missing wespeaker_v2.mlmodelc
    /// Tests: Embedding model error handling
    /// Expected: Continue recording without speaker embeddings
    static var simulateMissingEmbeddingModel: Bool = false

    /// Force model loading to timeout (30s delay)
    /// Tests: Timeout handling, user feedback
    /// Expected: Error message, fallback to no diarization
    static var forceModelLoadTimeout: Bool = false

    /// Inject invalid/corrupted speaker embeddings (NaN values)
    /// Tests: Embedding validation, similarity computation safety
    /// Expected: Invalid embeddings rejected, use fallback speaker ID
    static var injectInvalidEmbeddings: Bool = false

    /// Force ANE memory allocation to fail
    /// Tests: ANE fallback to CPU, automatic degradation
    /// Expected: Fall back to standard allocation, log warning
    static var forceANEAllocationFailure: Bool = false

    /// Override to force CPU fallback even when ANE available
    /// Tests: CPU-only path validation
    /// Expected: CPU processing works correctly
    static var forceCPUFallback: Bool = false

    // MARK: - Speech Framework Chaos (5 scenarios)

    /// Force locale to be unavailable (request invalid locale "zz-ZZ")
    /// Tests: Locale fallback chain, error handling
    /// Expected: Fall back through pt-BR → pt-PT → pt → current locale
    static var forceLocaleUnavailable: Bool = false

    /// Simulate Speech model download failure
    /// Tests: Offline fallback, error messaging
    /// Expected: Clear error to user, graceful abort
    static var simulateModelDownloadFailure: Bool = false

    /// Inject empty/nil transcription results
    /// Tests: Empty result handling, UI update safety
    /// Expected: UI doesn't crash, shows appropriate state
    static var injectEmptyTranscriptionResults: Bool = false

    /// Force SpeechAnalyzer format mismatch
    /// Tests: Format handshake recovery
    /// Expected: Fall back to compatible format
    static var forceAnalyzerFormatMismatch: Bool = false

    /// Simulate recognition timeout (hang for 30s)
    /// Tests: Timeout detection, user cancellation
    /// Expected: Timeout after threshold, allow user to stop
    static var simulateRecognitionTimeout: Bool = false

    // MARK: - SwiftData Chaos (4 scenarios)

    /// Make ModelContext.save() throw errors
    /// Tests: Save error handling, retry logic, data loss prevention
    /// Expected: Retry 3 times, preserve data in memory, alert user
    static var simulateSaveFailure: Bool = false

    /// Create concurrent write conflicts (10 simultaneous writes)
    /// Tests: Concurrency isolation, data race prevention
    /// Expected: All writes succeed without corruption
    static var forceConcurrentWriteConflict: Bool = false

    /// Corrupt SwiftData relationships (orphan segments)
    /// Tests: Relationship integrity validation
    /// Expected: Detect orphans, clean up or reassign
    static var corruptRelationships: Bool = false

    /// Simulate disk full / storage exhaustion
    /// Tests: Disk space error handling
    /// Expected: Clear error message, prevent partial writes
    static var simulateStorageExhaustion: Bool = false

    // MARK: - System Resource Chaos (4 scenarios)

    /// Allocate 500MB during recording to trigger memory pressure
    /// Tests: Memory pressure handling, adaptive backpressure
    /// Expected: Adaptive backpressure kicks in, drops old buffers
    static var simulateMemoryPressure: Bool = false

    /// Fill temporary directory to simulate disk exhaustion
    /// Tests: Disk space error handling, temp file cleanup
    /// Expected: Clean error, clean up temp files
    static var forceDiskSpaceExhaustion: Bool = false

    /// Simulate CPU throttling (busy-wait on background thread)
    /// Tests: Performance degradation handling
    /// Expected: Adaptive window sizing, reduce real-time processing
    static var simulateCPUThrottling: Bool = false

    /// Force microphone permission denial
    /// Tests: Permission error handling, user guidance
    /// Expected: Clear error message with Settings link
    static var forcePermissionDenial: Bool = false

    // MARK: - Concurrency Chaos (4 scenarios)

    /// Inject artificial race conditions (random delays in critical sections)
    /// Tests: Lock/actor isolation effectiveness
    /// Expected: No crashes, correct synchronization
    static var forceRaceConditions: Bool = false

    /// Create deadlock scenario (circular actor dependencies)
    /// Tests: Deadlock detection, timeout mechanisms
    /// Expected: Timeout after 5s, log warning
    static var injectDeadlockScenario: Bool = false

    /// Violate actor isolation (access @MainActor from background)
    /// Tests: Actor isolation enforcement
    /// Expected: Runtime error or safe serialization
    static var violateActorIsolation: Bool = false

    /// Force task cancellation at critical moments
    /// Tests: Cancellation handling, resource cleanup
    /// Expected: Graceful cancellation, no resource leaks
    static var forceTaskCancellation: Bool = false

    // MARK: - Chaos Scenario Enum

    /// All supported chaos scenarios
    enum ChaosScenario: String, CaseIterable {
        // Audio Pipeline
        case bufferOverflow = "BufferOverflow"
        case formatMismatch = "FormatMismatch"
        case firstBufferTimeout = "FirstBufferTimeout"
        case converterFailure = "ConverterFailure"
        case routeChangeDuringRecording = "RouteChangeDuringRecording"
        case corruptAudioBuffers = "CorruptAudioBuffers"

        // ML Model
        case missingSegmentationModel = "MissingSegmentationModel"
        case missingEmbeddingModel = "MissingEmbeddingModel"
        case modelLoadTimeout = "ModelLoadTimeout"
        case invalidEmbeddings = "InvalidEmbeddings"
        case aneAllocationFailure = "ANEAllocationFailure"
        case cpuFallback = "CPUFallback"

        // Speech Framework
        case localeUnavailable = "LocaleUnavailable"
        case modelDownloadFailure = "ModelDownloadFailure"
        case emptyTranscriptionResults = "EmptyTranscriptionResults"
        case analyzerFormatMismatch = "AnalyzerFormatMismatch"
        case recognitionTimeout = "RecognitionTimeout"

        // SwiftData
        case saveFailure = "SaveFailure"
        case concurrentWriteConflict = "ConcurrentWriteConflict"
        case corruptRelationships = "CorruptRelationships"
        case storageExhaustion = "StorageExhaustion"

        // System Resources
        case memoryPressure = "MemoryPressure"
        case diskSpaceExhaustion = "DiskSpaceExhaustion"
        case cpuThrottling = "CPUThrottling"
        case permissionDenial = "PermissionDenial"

        // Concurrency
        case raceConditions = "RaceConditions"
        case deadlockScenario = "DeadlockScenario"
        case actorIsolationViolation = "ActorIsolationViolation"
        case taskCancellation = "TaskCancellation"

        /// Human-readable category for the scenario
        var category: String {
            switch self {
            case .bufferOverflow, .formatMismatch, .firstBufferTimeout,
                 .converterFailure, .routeChangeDuringRecording, .corruptAudioBuffers:
                return "Audio Pipeline"
            case .missingSegmentationModel, .missingEmbeddingModel, .modelLoadTimeout,
                 .invalidEmbeddings, .aneAllocationFailure, .cpuFallback:
                return "ML Model"
            case .localeUnavailable, .modelDownloadFailure, .emptyTranscriptionResults,
                 .analyzerFormatMismatch, .recognitionTimeout:
                return "Speech Framework"
            case .saveFailure, .concurrentWriteConflict, .corruptRelationships,
                 .storageExhaustion:
                return "SwiftData"
            case .memoryPressure, .diskSpaceExhaustion, .cpuThrottling,
                 .permissionDenial:
                return "System Resources"
            case .raceConditions, .deadlockScenario, .actorIsolationViolation,
                 .taskCancellation:
                return "Concurrency"
            }
        }
    }

    // MARK: - Helper Methods

    /// Enable a specific chaos scenario (sets corresponding flag to true)
    static func enableScenario(_ scenario: ChaosScenario) {
        guard chaosEnabled else {
            print("[Chaos] Cannot enable scenario - CHAOS_ENABLED=0")
            return
        }

        reset() // Clear all flags first

        switch scenario {
        // Audio Pipeline
        case .bufferOverflow:
            forceBufferOverflow = true
        case .formatMismatch:
            forceFormatMismatch = true
        case .firstBufferTimeout:
            simulateFirstBufferTimeout = true
        case .converterFailure:
            forceConverterFailure = true
        case .routeChangeDuringRecording:
            injectRouteChangeDuringRecording = true
        case .corruptAudioBuffers:
            corruptAudioBuffers = true

        // ML Model
        case .missingSegmentationModel:
            simulateMissingSegmentationModel = true
        case .missingEmbeddingModel:
            simulateMissingEmbeddingModel = true
        case .modelLoadTimeout:
            forceModelLoadTimeout = true
        case .invalidEmbeddings:
            injectInvalidEmbeddings = true
        case .aneAllocationFailure:
            forceANEAllocationFailure = true
        case .cpuFallback:
            forceCPUFallback = true

        // Speech Framework
        case .localeUnavailable:
            forceLocaleUnavailable = true
        case .modelDownloadFailure:
            simulateModelDownloadFailure = true
        case .emptyTranscriptionResults:
            injectEmptyTranscriptionResults = true
        case .analyzerFormatMismatch:
            forceAnalyzerFormatMismatch = true
        case .recognitionTimeout:
            simulateRecognitionTimeout = true

        // SwiftData
        case .saveFailure:
            simulateSaveFailure = true
        case .concurrentWriteConflict:
            forceConcurrentWriteConflict = true
        case .corruptRelationships:
            corruptRelationships = true
        case .storageExhaustion:
            simulateStorageExhaustion = true

        // System Resources
        case .memoryPressure:
            simulateMemoryPressure = true
        case .diskSpaceExhaustion:
            forceDiskSpaceExhaustion = true
        case .cpuThrottling:
            simulateCPUThrottling = true
        case .permissionDenial:
            forcePermissionDenial = true

        // Concurrency
        case .raceConditions:
            forceRaceConditions = true
        case .deadlockScenario:
            injectDeadlockScenario = true
        case .actorIsolationViolation:
            violateActorIsolation = true
        case .taskCancellation:
            forceTaskCancellation = true
        }

        if verboseLogging {
            print("[Chaos] Enabled scenario: \(scenario.rawValue) (\(scenario.category))")
        }
    }

    /// Reset all chaos flags to false
    static func reset() {
        // Audio Pipeline
        forceFormatMismatch = false
        forceBufferOverflow = false
        simulateFirstBufferTimeout = false
        forceConverterFailure = false
        injectRouteChangeDuringRecording = false
        corruptAudioBuffers = false

        // ML Model
        simulateMissingSegmentationModel = false
        simulateMissingEmbeddingModel = false
        forceModelLoadTimeout = false
        injectInvalidEmbeddings = false
        forceANEAllocationFailure = false
        forceCPUFallback = false

        // Speech Framework
        forceLocaleUnavailable = false
        simulateModelDownloadFailure = false
        injectEmptyTranscriptionResults = false
        forceAnalyzerFormatMismatch = false
        simulateRecognitionTimeout = false

        // SwiftData
        simulateSaveFailure = false
        forceConcurrentWriteConflict = false
        corruptRelationships = false
        simulateStorageExhaustion = false

        // System Resources
        simulateMemoryPressure = false
        forceDiskSpaceExhaustion = false
        simulateCPUThrottling = false
        forcePermissionDenial = false

        // Concurrency
        forceRaceConditions = false
        injectDeadlockScenario = false
        violateActorIsolation = false
        forceTaskCancellation = false

        if verboseLogging {
            print("[Chaos] All flags reset")
        }
    }

    /// Check if any chaos flag is currently enabled
    static var anyChaosActive: Bool {
        guard chaosEnabled else { return false }

        return forceFormatMismatch || forceBufferOverflow || simulateFirstBufferTimeout ||
               forceConverterFailure || injectRouteChangeDuringRecording || corruptAudioBuffers ||
               simulateMissingSegmentationModel || simulateMissingEmbeddingModel ||
               forceModelLoadTimeout || injectInvalidEmbeddings || forceANEAllocationFailure ||
               forceCPUFallback || forceLocaleUnavailable || simulateModelDownloadFailure ||
               injectEmptyTranscriptionResults || forceAnalyzerFormatMismatch ||
               simulateRecognitionTimeout || simulateSaveFailure || forceConcurrentWriteConflict ||
               corruptRelationships || simulateStorageExhaustion || simulateMemoryPressure ||
               forceDiskSpaceExhaustion || simulateCPUThrottling || forcePermissionDenial ||
               forceRaceConditions || injectDeadlockScenario || violateActorIsolation ||
               forceTaskCancellation
    }
}

#else
// RELEASE build - all chaos flags disabled
@available(macOS 13.0, iOS 16.0, *)
struct ChaosFlags {
    static let chaosEnabled = false
    static let verboseLogging = false

    static var forceFormatMismatch: Bool { false }
    static var forceBufferOverflow: Bool { false }
    static var simulateFirstBufferTimeout: Bool { false }
    static var forceConverterFailure: Bool { false }
    static var injectRouteChangeDuringRecording: Bool { false }
    static var corruptAudioBuffers: Bool { false }
    static var simulateMissingSegmentationModel: Bool { false }
    static var simulateMissingEmbeddingModel: Bool { false }
    static var forceModelLoadTimeout: Bool { false }
    static var injectInvalidEmbeddings: Bool { false }
    static var forceANEAllocationFailure: Bool { false }
    static var forceCPUFallback: Bool { false }
    static var forceLocaleUnavailable: Bool { false }
    static var simulateModelDownloadFailure: Bool { false }
    static var injectEmptyTranscriptionResults: Bool { false }
    static var forceAnalyzerFormatMismatch: Bool { false }
    static var simulateRecognitionTimeout: Bool { false }
    static var simulateSaveFailure: Bool { false }
    static var forceConcurrentWriteConflict: Bool { false }
    static var corruptRelationships: Bool { false }
    static var simulateStorageExhaustion: Bool { false }
    static var simulateMemoryPressure: Bool { false }
    static var forceDiskSpaceExhaustion: Bool { false }
    static var simulateCPUThrottling: Bool { false }
    static var forcePermissionDenial: Bool { false }
    static var forceRaceConditions: Bool { false }
    static var injectDeadlockScenario: Bool { false }
    static var violateActorIsolation: Bool { false }
    static var forceTaskCancellation: Bool { false }

    enum ChaosScenario: String, CaseIterable {
        case bufferOverflow = "BufferOverflow"
        case formatMismatch = "FormatMismatch"
        case firstBufferTimeout = "FirstBufferTimeout"
        case converterFailure = "ConverterFailure"
        case routeChangeDuringRecording = "RouteChangeDuringRecording"
        case corruptAudioBuffers = "CorruptAudioBuffers"
        case missingSegmentationModel = "MissingSegmentationModel"
        case missingEmbeddingModel = "MissingEmbeddingModel"
        case modelLoadTimeout = "ModelLoadTimeout"
        case invalidEmbeddings = "InvalidEmbeddings"
        case aneAllocationFailure = "ANEAllocationFailure"
        case cpuFallback = "CPUFallback"
        case localeUnavailable = "LocaleUnavailable"
        case modelDownloadFailure = "ModelDownloadFailure"
        case emptyTranscriptionResults = "EmptyTranscriptionResults"
        case analyzerFormatMismatch = "AnalyzerFormatMismatch"
        case recognitionTimeout = "RecognitionTimeout"
        case saveFailure = "SaveFailure"
        case concurrentWriteConflict = "ConcurrentWriteConflict"
        case corruptRelationships = "CorruptRelationships"
        case storageExhaustion = "StorageExhaustion"
        case memoryPressure = "MemoryPressure"
        case diskSpaceExhaustion = "DiskSpaceExhaustion"
        case cpuThrottling = "CPUThrottling"
        case permissionDenial = "PermissionDenial"
        case raceConditions = "RaceConditions"
        case deadlockScenario = "DeadlockScenario"
        case actorIsolationViolation = "ActorIsolationViolation"
        case taskCancellation = "TaskCancellation"

        var category: String { "" }
    }

    static func enableScenario(_ scenario: ChaosScenario) {}
    static func reset() {}
    static var anyChaosActive: Bool { false }
}
#endif

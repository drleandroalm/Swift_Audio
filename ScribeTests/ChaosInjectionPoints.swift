import AVFoundation
import Foundation
import SwiftData
import XCTest
@testable import SwiftScribe

/// Chaos Injection Points for Resilience Testing
/// Provides helper methods to inject faults at critical production code paths
///
/// **Architecture**:
/// - Test-side file (ScribeTests/)
/// - Production code calls these methods at strategic points
/// - No-op in RELEASE builds (ChaosFlags.chaosEnabled always false)
/// - Minimal LOC impact on production (<10 lines total)
///
/// **Usage Pattern**:
/// ```swift
/// // In Recorder.swift (production code):
/// if let chaosBuffer = ChaosInjector.injectBufferChaos(buffer) {
///     buffer = chaosBuffer
/// }
/// ```
@available(macOS 13.0, iOS 16.0, *)
enum ChaosInjector {

    // MARK: - Audio Pipeline Injection Points

    /// Inject chaos into audio buffer processing
    /// Called from: Recorder.swift (tap callback, ~line 462)
    ///
    /// Scenarios:
    /// - BufferOverflow: Return oversized buffer (10x capacity)
    /// - CorruptAudioBuffers: Inject NaN/Inf values into samples
    ///
    /// Returns: Chaos-injected buffer or nil (use original buffer)
    static func injectBufferChaos(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.forceBufferOverflow {
            ChaosMetrics.current.oversizedBuffersInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Injecting oversized buffer (10x capacity)")
            }
            return createOversizedBuffer(originalBuffer: buffer)
        }

        if ChaosFlags.corruptAudioBuffers {
            ChaosMetrics.current.corruptedBuffersInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Corrupting audio buffer with NaN values")
            }
            return corruptBuffer(buffer)
        }

        return nil
    }

    /// Inject chaos into tap installation
    /// Called from: Recorder.swift (installTap, ~line 409)
    ///
    /// Scenarios:
    /// - RouteChangeDuringRecording: Simulate route change notification
    ///
    /// Throws: Error if chaos requires tap installation to fail
    static func injectTapInstallationChaos() throws {
        guard ChaosFlags.chaosEnabled else { return }

        if ChaosFlags.injectRouteChangeDuringRecording {
            if ChaosFlags.verboseLogging {
                print("[Chaos] Simulating route change during recording")
            }
            // Post route change notification after small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                #if os(iOS)
                NotificationCenter.default.post(
                    name: AVAudioSession.routeChangeNotification,
                    object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue]
                )
                #else
                NotificationCenter.default.post(
                    name: .AVAudioEngineConfigurationChange,
                    object: nil
                )
                #endif
            }
        }
    }

    /// Inject chaos into watchdog timeout value
    /// Called from: Recorder.swift (firstBufferMonitor, ~line 187)
    ///
    /// Scenarios:
    /// - FirstBufferTimeout: Return 0.1s timeout (forces immediate timeout)
    ///
    /// Returns: Chaos timeout value or nil (use default 10s)
    static func injectWatchdogTimeoutChaos() -> TimeInterval? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.simulateFirstBufferTimeout {
            ChaosMetrics.current.watchdogTimeoutsForced += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing watchdog timeout (0.1s instead of 10s)")
            }
            return 0.1 // Force immediate timeout
        }

        return nil
    }

    /// Inject chaos into AVAudioConverter creation
    /// Called from: BufferConversion.swift (convertBuffer, ~line 29)
    ///
    /// Scenarios:
    /// - ConverterFailure: Throw error during converter creation
    ///
    /// Throws: Error if converter creation should fail
    static func injectConverterCreationChaos() throws {
        guard ChaosFlags.chaosEnabled else { return }

        if ChaosFlags.forceConverterFailure {
            ChaosMetrics.current.converterFailuresInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing AVAudioConverter creation failure")
            }
            throw BufferConverter.Error.failedToCreateConverter
        }
    }

    /// Inject chaos into audio format selection
    /// Called from: Recorder.swift (format handshake, ~line 160)
    ///
    /// Scenarios:
    /// - FormatMismatch: Return incompatible format (48kHz stereo when 16kHz mono expected)
    ///
    /// Returns: Chaos format or nil (use analyzer's preferred format)
    static func injectFormatMismatchChaos() -> AVAudioFormat? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.forceFormatMismatch {
            ChaosMetrics.current.formatMismatchesInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing format mismatch (48kHz stereo)")
            }
            // Return 48kHz stereo (incompatible with typical 16kHz mono requirement)
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48000,
                channels: 2,
                interleaved: false
            )
        }

        return nil
    }

    // MARK: - ML Model Injection Points

    /// Inject chaos into diarization model loading
    /// Called from: DiarizationManager.swift (resolveDiarizerModels, ~line 161)
    ///
    /// Scenarios:
    /// - MissingSegmentationModel: Throw "model not found" error for segmentation
    /// - MissingEmbeddingModel: Throw "model not found" error for embedding
    /// - ModelLoadTimeout: Block for 30s to exceed timeout
    ///
    /// Throws: Error if model loading should fail
    static func injectModelLoadingChaos() async throws {
        guard ChaosFlags.chaosEnabled else { return }

        if ChaosFlags.simulateMissingSegmentationModel {
            ChaosMetrics.current.missingModelsInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Simulating missing segmentation model")
            }
            throw NSError(
                domain: "DiarizerError",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Model not found: pyannote_segmentation.mlmodelc"]
            )
        }

        if ChaosFlags.simulateMissingEmbeddingModel {
            ChaosMetrics.current.missingModelsInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Simulating missing embedding model")
            }
            throw NSError(
                domain: "DiarizerError",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Model not found: wespeaker_v2.mlmodelc"]
            )
        }

        if ChaosFlags.forceModelLoadTimeout {
            ChaosMetrics.current.modelTimeoutsInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing model load timeout (30s delay)")
            }
            try await Task.sleep(nanoseconds: 30_000_000_000) // 30s
        }
    }

    /// Inject chaos into speaker embedding validation
    /// Called from: DiarizationManager.swift (embedding processing)
    ///
    /// Scenarios:
    /// - InvalidEmbeddings: Replace valid embedding with NaN values
    ///
    /// Returns: Chaos embedding or nil (use original embedding)
    static func injectEmbeddingChaos(_ embedding: [Float]) -> [Float]? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.injectInvalidEmbeddings {
            ChaosMetrics.current.invalidEmbeddingsInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Injecting invalid embedding (NaN values)")
            }
            return Array(repeating: Float.nan, count: embedding.count)
        }

        return nil
    }

    /// Inject chaos into ANE optimization decision
    /// Called from: DiarizationManager.swift (ANE allocation, ~line 83)
    ///
    /// Scenarios:
    /// - ANEAllocationFailure: Force allocation failure
    /// - CPUFallback: Override to force CPU-only processing
    ///
    /// Returns: Chaos decision (true/false) or nil (use FeatureFlags default)
    static func injectANEOptimizationChaos() -> Bool? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.forceANEAllocationFailure {
            ChaosMetrics.current.aneFailuresInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing ANE allocation failure (fallback to CPU)")
            }
            return false // Force fallback to CPU
        }

        if ChaosFlags.forceCPUFallback {
            ChaosMetrics.current.cpuFallbacksForced += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing CPU-only processing (disable ANE)")
            }
            return false // Disable ANE
        }

        return nil
    }

    // MARK: - Speech Framework Injection Points

    /// Inject chaos into locale selection
    /// Called from: Transcription.swift (setUpTranscriber, ~line 79)
    ///
    /// Scenarios:
    /// - LocaleUnavailable: Return invalid locale to trigger fallback chain
    ///
    /// Returns: Chaos locale or nil (use default pt-BR)
    static func injectLocaleChaos() -> Locale? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.forceLocaleUnavailable {
            ChaosMetrics.current.localeFailuresInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing unavailable locale (zz-ZZ)")
            }
            return Locale(identifier: "zz-ZZ") // Invalid locale
        }

        return nil
    }

    /// Inject chaos into Speech model availability check
    /// Called from: Transcription.swift (ensureModel, ~line 96)
    ///
    /// Scenarios:
    /// - ModelDownloadFailure: Throw network error during model check
    ///
    /// Throws: Error if model availability check should fail
    static func injectModelAvailabilityChaos() throws {
        guard ChaosFlags.chaosEnabled else { return }

        if ChaosFlags.simulateModelDownloadFailure {
            ChaosMetrics.current.modelDownloadFailuresInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Simulating Speech model download failure")
            }
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                userInfo: [NSLocalizedDescriptionKey: "Model download failed: No internet connection"]
            )
        }
    }

    /// Inject chaos into transcription result processing
    /// Called from: Transcription.swift (result handling, ~line 133)
    ///
    /// Scenarios:
    /// - EmptyTranscriptionResults: Return nil to simulate empty result
    ///
    /// Returns: Chaos result (nil = empty) or unmodified result
    static func injectTranscriptionResultChaos<T>(_ result: T?) -> T? {
        guard ChaosFlags.chaosEnabled else { return result }

        if ChaosFlags.injectEmptyTranscriptionResults {
            ChaosMetrics.current.emptyResultsInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Injecting empty transcription result")
            }
            return nil
        }

        return result
    }

    /// Inject chaos into SpeechAnalyzer format selection
    /// Called from: Transcription.swift (analyzerFormat, ~line 106)
    ///
    /// Scenarios:
    /// - AnalyzerFormatMismatch: Return incompatible format
    ///
    /// Returns: Chaos format or nil (use best available format)
    static func injectAnalyzerFormatChaos() -> AVAudioFormat? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.forceAnalyzerFormatMismatch {
            ChaosMetrics.current.analyzerFormatMismatchesInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing analyzer format mismatch")
            }
            // Return incompatible format (96kHz mono)
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 96000,
                channels: 1,
                interleaved: false
            )
        }

        return nil
    }

    // MARK: - SwiftData Injection Points

    /// Inject chaos into ModelContext save operations
    /// Called from: MemoModel.swift or wherever context.save() is called
    ///
    /// Scenarios:
    /// - SaveFailure: Throw error during save
    ///
    /// Throws: Error if save should fail
    static func injectSwiftDataSaveChaos() throws {
        guard ChaosFlags.chaosEnabled else { return }

        if ChaosFlags.simulateSaveFailure {
            ChaosMetrics.current.saveFailuresInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing SwiftData save failure")
            }
            throw NSError(
                domain: "SwiftDataError",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save context"]
            )
        }
    }

    /// Inject chaos into concurrent write operations
    /// Called from: Test code when testing concurrent writes
    ///
    /// Scenarios:
    /// - ConcurrentWriteConflict: Create artificial race condition
    ///
    /// Returns: Random delay duration (ms) to inject race conditions, or nil
    static func injectConcurrentWriteChaos() -> UInt64? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.forceConcurrentWriteConflict {
            let randomDelay = UInt64.random(in: 1_000_000...100_000_000) // 1-100ms
            if ChaosFlags.verboseLogging {
                print("[Chaos] Injecting race condition delay: \(randomDelay / 1_000_000)ms")
            }
            return randomDelay
        }

        return nil
    }

    // MARK: - System Resource Injection Points

    /// Inject chaos into memory allocation (simulate memory pressure)
    /// Called from: Test setup before recording starts
    ///
    /// Scenarios:
    /// - MemoryPressure: Allocate 500MB to trigger pressure
    ///
    /// Returns: Memory ballast array or nil
    static func injectMemoryPressureChaos() -> [UInt8]? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.simulateMemoryPressure {
            ChaosMetrics.current.memoryPressureInjected = true
            if ChaosFlags.verboseLogging {
                print("[Chaos] Simulating memory pressure (allocating 500MB)")
            }
            return Array(repeating: 0, count: 500 * 1024 * 1024) // 500MB
        }

        return nil
    }

    /// Inject chaos into permission checks
    /// Called from: Recorder.swift (isAuthorized check, ~line 120)
    ///
    /// Scenarios:
    /// - PermissionDenial: Return false to simulate denied permission
    ///
    /// Returns: Chaos permission result or nil (use real permission)
    static func injectPermissionChaos() -> Bool? {
        guard ChaosFlags.chaosEnabled else { return nil }

        if ChaosFlags.forcePermissionDenial {
            ChaosMetrics.current.permissionDenialsInjected += 1
            if ChaosFlags.verboseLogging {
                print("[Chaos] Forcing permission denial")
            }
            return false
        }

        return nil
    }

    // MARK: - Helper Methods

    /// Create oversized buffer (10x normal capacity)
    private static func createOversizedBuffer(originalBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let oversizedCapacity = originalBuffer.frameCapacity * 10

        guard let oversizedBuffer = AVAudioPCMBuffer(
            pcmFormat: originalBuffer.format,
            frameCapacity: oversizedCapacity
        ) else {
            return nil
        }

        // Copy original samples and fill rest with zeros
        oversizedBuffer.frameLength = oversizedCapacity

        if let originalData = originalBuffer.floatChannelData,
           let oversizedData = oversizedBuffer.floatChannelData {
            for channel in 0..<Int(originalBuffer.format.channelCount) {
                // Copy original frames
                memcpy(
                    oversizedData[channel],
                    originalData[channel],
                    Int(originalBuffer.frameLength) * MemoryLayout<Float>.size
                )
                // Fill rest with zeros
                let remainingFrames = Int(oversizedCapacity - originalBuffer.frameLength)
                memset(
                    oversizedData[channel].advanced(by: Int(originalBuffer.frameLength)),
                    0,
                    remainingFrames * MemoryLayout<Float>.size
                )
            }
        }

        return oversizedBuffer
    }

    /// Corrupt buffer by injecting NaN values
    private static func corruptBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData else { return buffer }

        for channel in 0..<Int(buffer.format.channelCount) {
            // Corrupt 10% of samples with NaN
            let corruptionRate = 0.1
            for frame in 0..<Int(buffer.frameLength) {
                if Double.random(in: 0...1) < corruptionRate {
                    channelData[channel][frame] = Float.nan
                }
            }
        }

        return buffer
    }
}

// MARK: - Chaos Metrics Tracking

/// Tracks chaos injection events and resilience metrics during test execution
@available(macOS 13.0, iOS 16.0, *)
class ChaosMetrics {
    static let current = ChaosMetrics()

    // Audio Pipeline Metrics
    var oversizedBuffersInjected: Int = 0
    var oversizedBuffersRejected: Int = 0
    var corruptedBuffersInjected: Int = 0
    var corruptedBuffersDropped: Int = 0
    var watchdogTimeoutsForced: Int = 0
    var watchdogRecoveriesObserved: Int = 0
    var converterFailuresInjected: Int = 0
    var converterFallbacksObserved: Int = 0
    var formatMismatchesInjected: Int = 0
    var formatConversionsSuccessful: Int = 0

    // ML Model Metrics
    var missingModelsInjected: Int = 0
    var modelLoadGracefulDegradations: Int = 0
    var modelTimeoutsInjected: Int = 0
    var invalidEmbeddingsInjected: Int = 0
    var invalidEmbeddingsRejected: Int = 0
    var aneFailuresInjected: Int = 0
    var aneFallbacksObserved: Int = 0
    var cpuFallbacksForced: Int = 0

    // Speech Framework Metrics
    var localeFailuresInjected: Int = 0
    var localeFallbacksObserved: Int = 0
    var modelDownloadFailuresInjected: Int = 0
    var emptyResultsInjected: Int = 0
    var emptyResultsHandledGracefully: Int = 0
    var analyzerFormatMismatchesInjected: Int = 0

    // SwiftData Metrics
    var saveFailuresInjected: Int = 0
    var saveRetriesObserved: Int = 0
    var concurrentWriteConflictsDetected: Int = 0

    // System Resource Metrics
    var memoryPressureInjected: Bool = false
    var adaptiveBackpressureTriggered: Bool = false
    var permissionDenialsInjected: Int = 0

    // Resilience Metrics
    var crashCount: Int = 0
    var recoveryTimeMs: Double = 0
    var userImpact: UserImpact = .unknown

    enum UserImpact: String {
        case unknown = "unknown"
        case transparent = "transparent"  // User doesn't notice
        case degraded = "degraded"        // Feature disabled but app works
        case broken = "broken"            // App crashes or data lost
    }

    /// Calculate resilience score (0-100)
    /// Higher is better: 100 = perfect resilience, 0 = complete failure
    func calculateResilienceScore() -> Double {
        var score: Double = 100.0

        // Crashes are catastrophic (-50 points each)
        score -= Double(crashCount) * 50.0

        // Recovery time penalty (>1s = -10, >5s = -20, >10s = -30)
        if recoveryTimeMs > 10000 {
            score -= 30
        } else if recoveryTimeMs > 5000 {
            score -= 20
        } else if recoveryTimeMs > 1000 {
            score -= 10
        }

        // User impact penalty
        switch userImpact {
        case .broken:
            score -= 40
        case .degraded:
            score -= 15
        case .transparent:
            score -= 0
        case .unknown:
            score -= 5
        }

        // Successful recoveries earn points back
        score += Double(watchdogRecoveriesObserved) * 5
        score += Double(converterFallbacksObserved) * 5
        score += Double(aneFallbacksObserved) * 5
        score += Double(localeFallbacksObserved) * 5
        score += Double(emptyResultsHandledGracefully) * 5

        return max(0, min(100, score)) // Clamp to 0-100
    }

    /// Reset all metrics
    func reset() {
        oversizedBuffersInjected = 0
        oversizedBuffersRejected = 0
        corruptedBuffersInjected = 0
        corruptedBuffersDropped = 0
        watchdogTimeoutsForced = 0
        watchdogRecoveriesObserved = 0
        converterFailuresInjected = 0
        converterFallbacksObserved = 0
        formatMismatchesInjected = 0
        formatConversionsSuccessful = 0
        missingModelsInjected = 0
        modelLoadGracefulDegradations = 0
        modelTimeoutsInjected = 0
        invalidEmbeddingsInjected = 0
        invalidEmbeddingsRejected = 0
        aneFailuresInjected = 0
        aneFallbacksObserved = 0
        cpuFallbacksForced = 0
        localeFailuresInjected = 0
        localeFallbacksObserved = 0
        modelDownloadFailuresInjected = 0
        emptyResultsInjected = 0
        emptyResultsHandledGracefully = 0
        analyzerFormatMismatchesInjected = 0
        saveFailuresInjected = 0
        saveRetriesObserved = 0
        concurrentWriteConflictsDetected = 0
        memoryPressureInjected = false
        adaptiveBackpressureTriggered = false
        permissionDenialsInjected = 0
        crashCount = 0
        recoveryTimeMs = 0
        userImpact = .unknown
    }
}

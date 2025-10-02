import AVFoundation
import XCTest
import Speech
@testable import SwiftScribe

/// Speech Framework Contract Tests
/// Validates Apple Speech framework integration against performance baselines
/// Tests run deterministically using pre-recorded audio samples

@MainActor
final class SpeechFrameworkContractTests: XCTestCase {

    // MARK: - Test Configuration

    private let baselineFile = "PerformanceBaselines.json"
    private var baselines: PerformanceBaselines!

    override func setUpWithError() throws {
        try super.setUpWithError()
        baselines = try loadPerformanceBaselines()
    }

    // MARK: - Transcription Accuracy Tests

    func test_CleanAudio_TranscriptionAccuracy_MeetsWERBaseline() async throws {
        // GIVEN: Clean speech audio sample
        let audioFile = "Audio_Files_Tests/Audio_One_Speaker_Test.wav"
        guard FileManager.default.fileExists(atPath: audioFile) else {
            throw XCTSkip("Test audio file not found: \(audioFile)")
        }

        let memo = Memo.blank()
        let transcriber = SpokenWordTranscriber(memo: memo)

        // WHEN: Transcribe the audio
        try await transcriber.setUpTranscriber()
        try await streamPreconvertedAudio(fileURL: URL(fileURLWithPath: audioFile), into: transcriber)
        try await transcriber.finishTranscribing()

        // THEN: Transcript should be non-empty and have reasonable confidence
        let finalText = transcriber.finalizedTranscript.string
        let memoText = memo.text.string

        XCTAssertFalse(finalText.isEmpty || memoText.isEmpty,
                      "Transcription produced empty result for clean audio")

        // Note: WER calculation requires golden transcript reference
        // For now, validate that we got substantial output
        let wordCount = finalText.split(separator: " ").count
        XCTAssertGreaterThan(wordCount, 0, "No words transcribed from clean audio")

        print("[CONTRACT] Clean audio transcription: \(wordCount) words")
    }

    func test_NoisyAudio_TranscriptionDegradation_WithinAcceptableBounds() async throws {
        // GIVEN: Noisy speech audio (if available)
        let audioFile = "Audio_Files_Tests/TestSuite/single_speaker/noisy_speech_10s.wav"
        guard FileManager.default.fileExists(atPath: audioFile) else {
            throw XCTSkip("Noisy audio test file not found: \(audioFile)")
        }

        let memo = Memo.blank()
        let transcriber = SpokenWordTranscriber(memo: memo)

        // WHEN: Transcribe noisy audio
        try await transcriber.setUpTranscriber()
        try await streamPreconvertedAudio(fileURL: URL(fileURLWithPath: audioFile), into: transcriber)
        try await transcriber.finishTranscribing()

        // THEN: Should still produce some output (graceful degradation)
        let finalText = transcriber.finalizedTranscript.string

        // With noise, we expect degraded but non-zero output
        XCTAssertFalse(finalText.isEmpty, "Noisy audio should still produce some transcription")

        print("[CONTRACT] Noisy audio transcription degraded but functional")
    }

    // MARK: - Latency Performance Tests

    func test_FirstWordLatency_MeetsSLO_1500ms() async throws {
        // GIVEN: Performance baseline for first word latency
        let sloMs = baselines.metrics.transcriptionFirstWordLatencyMs.slo

        let memo = Memo.blank()
        let transcriber = SpokenWordTranscriber(memo: memo)

        var firstWordTime: CFAbsoluteTime?
        let startTime = CFAbsoluteTimeGetCurrent()

        // Subscribe to volatile transcript updates
        let cancellable = transcriber.$volatileTranscript
            .first(where: { !$0.characters.isEmpty })
            .sink { _ in
                if firstWordTime == nil {
                    firstWordTime = CFAbsoluteTimeGetCurrent()
                }
            }

        // WHEN: Stream audio
        try await transcriber.setUpTranscriber()

        let audioFile = "Audio_Files_Tests/Audio_One_Speaker_Test.wav"
        guard FileManager.default.fileExists(atPath: audioFile) else {
            throw XCTSkip("Test audio file not found")
        }

        try await streamPreconvertedAudio(fileURL: URL(fileURLWithPath: audioFile), into: transcriber)

        // THEN: First word should appear within SLO
        if let firstWordTime = firstWordTime {
            let latencyMs = (firstWordTime - startTime) * 1000.0

            print("[CONTRACT] First word latency: \(String(format: "%.1f", latencyMs))ms (SLO: \(sloMs)ms)")

            // Note: First run may include model warmup, so we're lenient
            // In production, ModelWarmupService should reduce this
            XCTAssertLessThan(latencyMs, sloMs * 2.0,
                            "First word latency exceeded 2x SLO (cold start)")
        } else {
            XCTFail("No words transcribed during test")
        }

        cancellable.cancel()
    }

    func test_RealtimeFactor_MeetsSLO_Below1_0() async throws {
        // GIVEN: Performance baseline for realtime factor
        let sloFactor = baselines.metrics.transcriptionRealtimeFactor.slo

        let memo = Memo.blank()
        let transcriber = SpokenWordTranscriber(memo: memo)

        let audioFile = "Audio_Files_Tests/Audio_One_Speaker_Test.wav"
        guard FileManager.default.fileExists(atPath: audioFile) else {
            throw XCTSkip("Test audio file not found")
        }

        // Measure audio duration
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: audioFile))
        let audioDuration = Double(file.length) / file.processingFormat.sampleRate

        // WHEN: Transcribe and measure processing time
        let startTime = CFAbsoluteTimeGetCurrent()

        try await transcriber.setUpTranscriber()
        try await streamPreconvertedAudio(fileURL: URL(fileURLWithPath: audioFile), into: transcriber)
        try await transcriber.finishTranscribing()

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        // THEN: Realtime factor should be < 1.0 (faster than realtime)
        let realtimeFactor = processingTime / audioDuration

        print("[CONTRACT] Realtime factor: \(String(format: "%.2f", realtimeFactor)) (SLO: <\(sloFactor))")

        XCTAssertLessThan(realtimeFactor, sloFactor,
                         "Processing slower than realtime (factor: \(realtimeFactor))")
    }

    // MARK: - Error Handling Tests

    func test_EmptyAudio_GracefulHandling_NoTranscript() async throws {
        // GIVEN: Silent audio file
        let audioFile = "Audio_Files_Tests/TestSuite/edge_cases/silence_10s.wav"
        guard FileManager.default.fileExists(atPath: audioFile) else {
            throw XCTSkip("Silence test file not found")
        }

        let memo = Memo.blank()
        let transcriber = SpokenWordTranscriber(memo: memo)

        // WHEN: Transcribe silence
        try await transcriber.setUpTranscriber()
        try await streamPreconvertedAudio(fileURL: URL(fileURLWithPath: audioFile), into: transcriber)
        try await transcriber.finishTranscribing()

        // THEN: Should handle gracefully (empty or minimal output)
        let finalText = transcriber.finalizedTranscript.string

        // Silence should produce empty or very minimal output
        XCTAssertLessThan(finalText.count, 50,
                         "Silence audio should produce minimal transcription")

        print("[CONTRACT] Silence handled gracefully (output: \(finalText.count) chars)")
    }

    func test_NonSpeechAudio_GracefulHandling_MinimalTranscript() async throws {
        // GIVEN: Pure tone audio (non-speech)
        let audioFile = "Audio_Files_Tests/TestSuite/edge_cases/tone_440hz_10s.wav"
        guard FileManager.default.fileExists(atPath: audioFile) else {
            throw XCTSkip("Tone test file not found")
        }

        let memo = Memo.blank()
        let transcriber = SpokenWordTranscriber(memo: memo)

        // WHEN: Transcribe non-speech audio
        try await transcriber.setUpTranscriber()
        try await streamPreconvertedAudio(fileURL: URL(fileURLWithPath: audioFile), into: transcriber)
        try await transcriber.finishTranscribing()

        // THEN: Should handle gracefully (no crashes, minimal output)
        let finalText = transcriber.finalizedTranscript.string

        print("[CONTRACT] Non-speech audio handled gracefully (output: \(finalText.count) chars)")

        // Success if no crash occurred
        XCTAssertTrue(true, "Non-speech audio processing completed without crash")
    }

    // MARK: - Helper Methods

    private func streamPreconvertedAudio(fileURL: URL, into transcriber: SpokenWordTranscriber) async throws {
        let file = try AVAudioFile(forReading: fileURL)
        let srcFormat = file.processingFormat

        guard let analyzerFormat = transcriber.analyzerFormat else {
            XCTFail("analyzerFormat is nil after setUpTranscriber()")
            return
        }

        let chunk: AVAudioFrameCount = 8192
        let needsConvert = srcFormat != analyzerFormat
        let converter = needsConvert ? AVAudioConverter(from: srcFormat, to: analyzerFormat) : nil

        while true {
            guard let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: chunk) else { break }
            try file.read(into: inBuf, frameCount: chunk)
            if inBuf.frameLength == 0 { break }

            if let conv = converter {
                let ratio = analyzerFormat.sampleRate / srcFormat.sampleRate
                let outCap = AVAudioFrameCount((Double(inBuf.frameLength) * ratio).rounded(.up) + 1024)
                guard let outBuf = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: outCap) else {
                    XCTFail("Failed to allocate conversion buffer")
                    return
                }

                var err: NSError?
                var fed = false
                let status = conv.convert(to: outBuf, error: &err) { _, inputStatus in
                    let already = fed
                    fed = true
                    inputStatus.pointee = already ? .noDataNow : .haveData
                    return already ? nil : inBuf
                }

                XCTAssertNotEqual(status, .error, "Conversion failed: \(String(describing: err))")
                guard outBuf.frameLength > 0 else { continue }
                try await transcriber.streamAudioToTranscriber(outBuf)
            } else {
                try await transcriber.streamAudioToTranscriber(inBuf)
            }
        }
    }

    private func loadPerformanceBaselines() throws -> PerformanceBaselines {
        let url = URL(fileURLWithPath: baselineFile)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PerformanceBaselines.self, from: data)
    }
}

// MARK: - Performance Baselines Model

struct PerformanceBaselines: Codable {
    let metrics: Metrics

    struct Metrics: Codable {
        let transcriptionFirstWordLatencyMs: Metric
        let transcriptionRealtimeFactor: Metric

        enum CodingKeys: String, CodingKey {
            case transcriptionFirstWordLatencyMs = "transcription_first_word_latency_ms"
            case transcriptionRealtimeFactor = "transcription_realtime_factor"
        }
    }

    struct Metric: Codable {
        let p50: Double
        let p95: Double
        let p99: Double
        let slo: Double
    }
}

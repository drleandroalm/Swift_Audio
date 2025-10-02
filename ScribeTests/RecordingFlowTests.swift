import AVFoundation
import SwiftData
import XCTest
@testable import SwiftScribe

@MainActor
final class RecordingFlowTests: XCTestCase {
    func testLongRecordingProcessingHandlesFiveMinutesOfAudio() async throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )
        let transcriber = MockTranscriber(analyzerFormat: format)

        let expectedSegment = TimedSpeakerSegment(
            speakerId: "falante-1",
            embedding: [0.1, 0.2, 0.3],
            startTimeSeconds: 0,
            endTimeSeconds: 5 * 60,
            qualityScore: 0.9
        )
        let diarizer = CountingDiarizer(result: DiarizationResult(segments: [expectedSegment]))
        let manager = DiarizationManager(
            config: DiarizerConfig(),
            isEnabled: true,
            enableRealTimeProcessing: false,
            diarizer: diarizer
        )

        let iterations = 300 // 300 seconds = 5 minutes
        let buffer = try XCTUnwrap(makeBuffer(durationSeconds: 1, sampleRate: 16_000))

        for _ in 0..<iterations {
            try await transcriber.streamAudioToTranscriber(buffer)
            await manager.processAudioBuffer(buffer)
        }

        let result = await manager.finishProcessing()

        XCTAssertEqual(transcriber.streamedBuffers, iterations)
        XCTAssertEqual(diarizer.performCalls, 1)
        XCTAssertEqual(diarizer.totalSamples, iterations * Int(buffer.frameLength))
        XCTAssertEqual(result?.segments.first?.speakerId, expectedSegment.speakerId)

        let secondFinish = await manager.finishProcessing()
        XCTAssertNil(secondFinish)
    }

    func testDiarizationDisabledSkipsProcessingAndPersistsMemo() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let memo = Memo(title: "Desativado", text: AttributedString(""))
        context.insert(memo)

        let transcriber = MockTranscriber(analyzerFormat: nil)
        let diarizer = CountingDiarizer(result: DiarizationResult(segments: []))
        let manager = DiarizationManager(
            config: DiarizerConfig(),
            isEnabled: false,
            enableRealTimeProcessing: true,
            diarizer: diarizer
        )

        let buffer = try XCTUnwrap(makeBuffer(durationSeconds: 2, sampleRate: 16_000))

        for _ in 0..<10 {
            try await transcriber.streamAudioToTranscriber(buffer)
            await manager.processAudioBuffer(buffer)
        }

        let result = await manager.finishProcessing()

        XCTAssertNil(result)
        XCTAssertEqual(diarizer.performCalls, 0)
        XCTAssertFalse(memo.hasSpeakerData)
        XCTAssertTrue(memo.speakerSegments.isEmpty)
        XCTAssertEqual(transcriber.streamedBuffers, 10)
    }

    func testAdjustingAppSettingsReplacesDiarizerConfiguration() async {
        let settings = AppSettings()
        let initialConfig = settings.diarizationConfig()

        let initialDiarizer = ConfigAwareDiarizer(config: initialConfig)
        let manager = DiarizationManager(
            config: initialConfig,
            isEnabled: settings.diarizationEnabled,
            enableRealTimeProcessing: settings.enableRealTimeProcessing,
            diarizer: initialDiarizer
        )

        XCTAssertEqual(initialDiarizer.capturedConfig.clusteringThreshold, initialConfig.clusteringThreshold)

        settings.setClusteringThreshold(0.55)
        settings.setMinSegmentDuration(1.2)
        settings.setMaxSpeakers(4)
        settings.setEnableRealTimeProcessing(true)

        let updatedConfig = settings.diarizationConfig()
        let updatedDiarizer = ConfigAwareDiarizer(config: updatedConfig)

        manager.replaceDiarizerForTesting(
            updatedDiarizer,
            config: updatedConfig,
            isEnabled: settings.diarizationEnabled,
            enableRealTimeProcessing: settings.enableRealTimeProcessing
        )

        let buffer = makeBuffer(durationSeconds: 1, sampleRate: 16_000)
        if let buffer {
            await manager.processAudioBuffer(buffer)
            _ = await manager.finishProcessing()
        }

        XCTAssertEqual(updatedDiarizer.capturedConfig.clusteringThreshold, 0.55)
        XCTAssertEqual(updatedDiarizer.capturedConfig.minSpeechDuration, updatedConfig.minSpeechDuration)
        XCTAssertGreaterThanOrEqual(updatedDiarizer.performCalls, 1)
        XCTAssertEqual(manager.config.clusteringThreshold, 0.55)
        XCTAssertTrue(manager.enableRealTimeProcessing)
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Memo.self,
            Speaker.self,
            SpeakerSegment.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeBuffer(durationSeconds: Double, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        let frameCapacity = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }

        buffer.frameLength = frameCapacity
        if let channel = buffer.floatChannelData?.pointee {
            for frame in 0..<Int(buffer.frameLength) {
                channel[frame] = sinf(Float(frame) * 0.01)
            }
        }

        return buffer
    }
}

// MARK: - Test Doubles

private final class MockTranscriber: SpokenWordTranscribing {
    private(set) var streamedBuffers = 0
    private(set) var setupCalls = 0
    private(set) var finishCalls = 0
    private let analyzerFormatOverride: AVAudioFormat?

    init(analyzerFormat: AVAudioFormat?) {
        self.analyzerFormatOverride = analyzerFormat
    }

    func setUpTranscriber() async throws {
        setupCalls += 1
    }

    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        streamedBuffers += 1
    }

    func finishTranscribing() async throws {
        finishCalls += 1
    }
    
    func reset() {}
}

private final class CountingDiarizer: DiarizerManaging {
    private let result: DiarizationResult
    private let validation: AudioValidationResult
    private(set) var performCalls = 0
    private(set) var totalSamples = 0

    init(
        result: DiarizationResult,
        validation: AudioValidationResult = AudioValidationResult(isValid: true, durationSeconds: 0)
    ) {
        self.result = result
        self.validation = validation
    }

    func initialize(models: DiarizerModels) {}

    func performCompleteDiarization(_ samples: [Float], sampleRate: Int) throws -> DiarizationResult {
        performCalls += 1
        totalSamples += samples.count
        return result
    }

    func validateAudio(_ audio: [Float]) -> AudioValidationResult {
        validation
    }

    func upsertRuntimeSpeaker(id: String, embedding: [Float], duration: Float) {}
}

private final class ConfigAwareDiarizer: DiarizerManaging {
    let capturedConfig: DiarizerConfig
    private(set) var performCalls = 0

    init(config: DiarizerConfig) {
        self.capturedConfig = config
    }

    func initialize(models: DiarizerModels) {}

    func performCompleteDiarization(_ samples: [Float], sampleRate: Int) throws -> DiarizationResult {
        performCalls += 1
        let placeholderSegment = TimedSpeakerSegment(
            speakerId: "falante",
            embedding: [0, 0, 0],
            startTimeSeconds: 0,
            endTimeSeconds: Float(samples.count) / Float(sampleRate),
            qualityScore: 0.0
        )
        return DiarizationResult(segments: [placeholderSegment])
    }

    func validateAudio(_ audio: [Float]) -> AudioValidationResult {
        AudioValidationResult(isValid: true, durationSeconds: Float(audio.count))
    }

    func upsertRuntimeSpeaker(id: String, embedding: [Float], duration: Float) {}
}

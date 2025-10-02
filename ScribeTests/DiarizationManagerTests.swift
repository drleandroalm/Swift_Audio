import AVFoundation
import XCTest
@testable import SwiftScribe

@MainActor
final class DiarizationManagerTests: XCTestCase {
    func testProcessAudioBufferTriggersRealTimeProcessingAndStoresResult() async throws {
        let expectedSegment = TimedSpeakerSegment(
            speakerId: "falante-1",
            embedding: [0.1, 0.2, 0.3],
            startTimeSeconds: 0,
            endTimeSeconds: 2,
            qualityScore: 0.95
        )
        let expectedResult = DiarizationResult(segments: [expectedSegment])
        let diarizer = StubDiarizer(result: expectedResult)

        let manager = DiarizationManager(
            config: DiarizerConfig(chunkDuration: 10, chunkOverlap: 0),
            isEnabled: true,
            enableRealTimeProcessing: true,
            diarizer: diarizer
        )

        let buffer = try XCTUnwrap(makeBuffer(durationSeconds: 10))

        await manager.processAudioBuffer(buffer)

        XCTAssertEqual(diarizer.performCalls, 1)
        XCTAssertEqual(manager.lastResult?.segments.first?.speakerId, expectedSegment.speakerId)
        XCTAssertEqual(manager.processingProgress, 1.0, accuracy: 0.0001)
        XCTAssertFalse(manager.isProcessing)
    }

    func testFinishProcessingRunsWhenRealTimeIsDisabled() async throws {
        let expectedSegment = TimedSpeakerSegment(
            speakerId: "falante-2",
            embedding: [0.4, 0.5, 0.6],
            startTimeSeconds: 1,
            endTimeSeconds: 3,
            qualityScore: 0.87
        )
        let expectedResult = DiarizationResult(segments: [expectedSegment])
        let diarizer = StubDiarizer(result: expectedResult)

        let manager = DiarizationManager(
            config: DiarizerConfig(chunkDuration: 10, chunkOverlap: 0),
            isEnabled: true,
            enableRealTimeProcessing: false,
            diarizer: diarizer
        )

        let buffer = try XCTUnwrap(makeBuffer(durationSeconds: 5))
        await manager.processAudioBuffer(buffer)

        XCTAssertNil(manager.lastResult)
        XCTAssertEqual(diarizer.performCalls, 0)

        let finalResult = await manager.finishProcessing()

        XCTAssertNotNil(finalResult)
        XCTAssertEqual(diarizer.performCalls, 1)
        XCTAssertEqual(finalResult?.segments.count, 1)
    }

    func testProcessAudioBufferRespectsDisabledState() async throws {
        let diarizer = StubDiarizer(result: DiarizationResult(segments: []))
        let manager = DiarizationManager(
            config: DiarizerConfig(),
            isEnabled: false,
            enableRealTimeProcessing: true,
            diarizer: diarizer
        )

        let buffer = try XCTUnwrap(makeBuffer(durationSeconds: 10))
        await manager.processAudioBuffer(buffer)

        XCTAssertEqual(diarizer.performCalls, 0)
        let result = await manager.finishProcessing()
        XCTAssertNil(result)
    }

    func testValidateAudioDelegatesToDiarizer() async throws {
        let validation = AudioValidationResult(isValid: true, durationSeconds: 12, issues: [])
        let diarizer = StubDiarizer(result: DiarizationResult(segments: []), validationResult: validation)
        let manager = DiarizationManager(
            config: DiarizerConfig(),
            isEnabled: true,
            enableRealTimeProcessing: false,
            diarizer: diarizer
        )

        let validated = await manager.validateAudio([0.1, 0.2, 0.3])

        XCTAssertEqual(validated?.durationSeconds, 12)
        XCTAssertTrue(validated?.isValid ?? false)
    }

    private func makeBuffer(durationSeconds: Double, sampleRate: Double = 16000) -> AVAudioPCMBuffer? {
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
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(buffer.frameLength) {
                channelData[0][frame] = sinf(Float(frame) * 0.01)
            }
        }

        return buffer
    }
}

private final class StubDiarizer: DiarizerManaging {
    private let result: DiarizationResult
    private let validationResult: AudioValidationResult
    private(set) var performCalls = 0

    init(
        result: DiarizationResult,
        validationResult: AudioValidationResult = AudioValidationResult(isValid: true, durationSeconds: 1)
    ) {
        self.result = result
        self.validationResult = validationResult
    }

    func initialize(models: DiarizerModels) {}

    func performCompleteDiarization(_ samples: [Float], sampleRate: Int) throws -> DiarizationResult {
        performCalls += 1
        return result
    }

    func validateAudio(_ audio: [Float]) -> AudioValidationResult {
        validationResult
    }

    func upsertRuntimeSpeaker(id: String, embedding: [Float], duration: Float) {}
}

import XCTest
import SwiftData
@testable import SwiftScribe

@MainActor
final class EnrollmentFlowTests: XCTestCase {
    func test_EnrollSpeakerFromMultipleClips_AveragesEmbeddings() async throws {
        // Embedding size used by FluidAudio SpeakerManager
        let dim = 256
        let ones = [Float](repeating: 1.0, count: dim)
        let threes = [Float](repeating: 3.0, count: dim)

        let diarizer = MultiClipMockDiarizer(mapping: [100: ones, 200: threes])
        let manager = DiarizationManager(config: DiarizerConfig(), isEnabled: true, enableRealTimeProcessing: false, diarizer: diarizer)

        // In-memory SwiftData container
        let container = try ModelContainer(for: Memo.self, Speaker.self, SpeakerSegment.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        // Two clips whose lengths map to different embeddings
        let clipA = [Float](repeating: 0.01, count: 100)
        let clipB = [Float](repeating: 0.02, count: 200)

        let speaker = try await manager.enrollSpeaker(fromClips: [clipA, clipB], name: "Teste", in: context)

        let embedding = try XCTUnwrap(speaker.embedding)
        XCTAssertEqual(embedding.count, dim)
        // Average of ones and threes is twos
        XCTAssertEqual(embedding.first, 2.0, accuracy: 0.0001)
    }

    func test_RenameSpeaker_UpdatesSwiftData() async throws {
        // Prepare diarizer that returns a single embedding for any clip
        let dim = 256
        let ones = [Float](repeating: 1.0, count: dim)
        let diarizer = MultiClipMockDiarizer(mapping: [100: ones])
        let manager = DiarizationManager(config: DiarizerConfig(), isEnabled: true, enableRealTimeProcessing: false, diarizer: diarizer)

        let container = try ModelContainer(for: Memo.self, Speaker.self, SpeakerSegment.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let clip = [Float](repeating: 0.01, count: 100)
        let speaker = try await manager.enrollSpeaker(from: clip, name: "Original", in: context)
        try await manager.renameSpeaker(id: speaker.id, to: "Renomeado", in: context)

        let fetched = try context.fetch(FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == speaker.id })).first
        XCTAssertEqual(fetched?.name, "Renomeado")
    }

    func test_Similarity_IdenticalEmbeddings_ReturnsHighConfidence() async throws {
        let dim = 256
        let ones = [Float](repeating: 1.0, count: dim)
        let diarizer = MultiClipMockDiarizer(mapping: [100: ones])
        let manager = DiarizationManager(config: DiarizerConfig(), isEnabled: true, enableRealTimeProcessing: false, diarizer: diarizer)

        let container = try ModelContainer(for: Memo.self, Speaker.self, SpeakerSegment.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        // Enroll speaker with ones embedding
        let clip = [Float](repeating: 0.0, count: 100)
        let sp = try await manager.enrollSpeaker(from: clip, name: "Alvo", in: context)

        let score = try await manager.similarity(of: clip, to: sp)
        XCTAssertGreaterThan(score, 0.95)
    }
}

private final class MultiClipMockDiarizer: DiarizerManaging {
    private let mapping: [Int: [Float]]
    init(mapping: [Int: [Float]]) { self.mapping = mapping }

    func initialize(models: DiarizerModels) {}

    func performCompleteDiarization(_ samples: [Float], sampleRate: Int) throws -> DiarizationResult {
        // Choose embedding by sample length key (or default)
        let key = samples.count
        let emb = mapping[key] ?? mapping.values.first ?? [Float](repeating: 0.5, count: 256)
        let seg = TimedSpeakerSegment(speakerId: "1", embedding: emb, startTimeSeconds: 0, endTimeSeconds: 1, qualityScore: 1)
        return DiarizationResult(segments: [seg])
    }

    func validateAudio(_ audio: [Float]) -> AudioValidationResult { AudioValidationResult(isValid: true, durationSeconds: Float(audio.count)) }

    func upsertRuntimeSpeaker(id: String, embedding: [Float], duration: Float) {}
}


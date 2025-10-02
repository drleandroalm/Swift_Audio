import SwiftData
import XCTest
@testable import SwiftScribe

private typealias AppSpeaker = SwiftScribe.Speaker
private typealias AppSpeakerSegment = SwiftScribe.SpeakerSegment

@MainActor
final class SwiftDataPersistenceTests: XCTestCase {
    func testUpdateWithDiarizationResultPersistsSpeakersAndSegments() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let memo = Memo(title: "Reunião", text: AttributedString("Segmento de teste."))
        context.insert(memo)

        let segment = TimedSpeakerSegment(
            speakerId: "speaker-1",
            embedding: [0.11, 0.22, 0.33],
            startTimeSeconds: 0,
            endTimeSeconds: 2,
            qualityScore: 0.85
        )

        let result = DiarizationResult(segments: [segment])

        memo.updateWithDiarizationResult(result, in: context)
        try context.save()

        XCTAssertTrue(memo.hasSpeakerData)
        XCTAssertEqual(memo.speakerSegments.count, 1)

        let storedSegments = try context.fetch(FetchDescriptor<AppSpeakerSegment>())
        XCTAssertEqual(storedSegments.count, 1)
        XCTAssertEqual(storedSegments.first?.speakerId, "speaker-1")
        XCTAssertTrue(storedSegments.first?.memo === memo)

        let storedSpeakers = try context.fetch(FetchDescriptor<AppSpeaker>())
        XCTAssertEqual(storedSpeakers.count, 1)
        XCTAssertEqual(storedSpeakers.first?.name, "Falante 1")
        XCTAssertEqual(storedSpeakers.first?.embedding ?? [], segment.embedding)
    }

    func testSpeakersHelperReturnsPersistedSpeakers() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let memo = Memo(title: "Treinamento", text: AttributedString("Falante A e B"))
        context.insert(memo)

        let segmentA = TimedSpeakerSegment(
            speakerId: "speaker-a",
            embedding: [0.1, 0.2],
            startTimeSeconds: 0,
            endTimeSeconds: 1,
            qualityScore: 0.9
        )
        let segmentB = TimedSpeakerSegment(
            speakerId: "speaker-b",
            embedding: [0.3, 0.4],
            startTimeSeconds: 1,
            endTimeSeconds: 2,
            qualityScore: 0.8
        )

        let result = DiarizationResult(segments: [segmentA, segmentB])
        memo.updateWithDiarizationResult(result, in: context)

        let speakers = memo.speakers(in: context)
        let speakerIds = Set(speakers.map { $0.id })

        XCTAssertEqual(speakerIds, ["speaker-a", "speaker-b"])
    }

    func testFindOrCreateSpeakerReusesExistingInstance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let created = AppSpeaker.findOrCreate(withId: "speaker-x", in: context)
        created.name = "Falante Único"
        try context.save()

        let fetched = AppSpeaker.findOrCreate(withId: "speaker-x", in: context)
        XCTAssertEqual(fetched.name, "Falante Único")
        XCTAssertTrue(created === fetched)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Memo.self,
            Speaker.self,
            SpeakerSegment.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

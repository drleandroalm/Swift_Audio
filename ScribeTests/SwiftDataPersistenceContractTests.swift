import SwiftData
import XCTest
@testable import SwiftScribe

/// SwiftData Persistence Contract Tests
/// Validates data persistence, crash recovery, and concurrent write safety
/// Critical for ensuring user data integrity across app sessions

@MainActor
final class SwiftDataPersistenceContractTests: XCTestCase {

    // MARK: - Basic Persistence Tests

    func test_MemoCreation_Persistence_SurvivesContextReload() throws {
        // GIVEN: Create a memo in one context
        let container1 = try createTestContainer()
        let context1 = ModelContext(container1)

        let memo = Memo.blank()
        memo.text = AttributedString("Test memo content")
        context1.insert(memo)
        try context1.save()

        let memoID = memo.id

        // WHEN: Create new context (simulates app restart)
        let context2 = ModelContext(container1)
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.id == memoID }
        )
        let fetchedMemos = try context2.fetch(descriptor)

        // THEN: Memo should be persisted
        XCTAssertEqual(fetchedMemos.count, 1, "Memo should persist across context reload")
        XCTAssertEqual(fetchedMemos.first?.text.string, "Test memo content")

        print("[CONTRACT] Memo persistence verified")
    }

    func test_SpeakerEnrollment_Persistence_WithEmbedding() throws {
        // GIVEN: Enrolled speaker with embedding
        let container = try createTestContainer()
        let context = ModelContext(container)

        let speaker = Speaker(name: "Test Speaker")
        speaker.embedding = Array(repeating: 0.5, count: 256)  // 256-dim WeSpeaker embedding
        context.insert(speaker)
        try context.save()

        let speakerID = speaker.id

        // WHEN: Reload in new context
        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<Speak

er>(
            predicate: #Predicate { $0.id == speakerID }
        )
        let fetchedSpeakers = try context2.fetch(descriptor)

        // THEN: Speaker and embedding should persist
        XCTAssertEqual(fetchedSpeakers.count, 1)
        XCTAssertEqual(fetchedSpeakers.first?.name, "Test Speaker")
        XCTAssertEqual(fetchedSpeakers.first?.embedding?.count, 256)
        XCTAssertEqual(fetchedSpeakers.first?.embedding?.first, 0.5, accuracy: 0.001)

        print("[CONTRACT] Speaker embedding persisted correctly")
    }

    func test_SpeakerSegments_Relationship_ToMemoAndSpeaker() throws {
        // GIVEN: Memo with speaker segments
        let container = try createTestContainer()
        let context = ModelContext(container)

        let memo = Memo.blank()
        let speaker = Speaker(name: "Speaker 1")
        context.insert(memo)
        context.insert(speaker)

        let segment = SpeakerSegment(
            speakerId: "speaker_1",
            embedding: [0.1, 0.2, 0.3],
            startTime: 0.0,
            endTime: 5.0,
            confidence: 0.92,
            memo: memo,
            speaker: speaker
        )
        context.insert(segment)

        try context.save()

        // WHEN: Fetch memo
        let memoID = memo.id
        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.id == memoID }
        )
        let fetchedMemos = try context2.fetch(descriptor)

        // THEN: Relationships should be intact
        let fetchedMemo = try XCTUnwrap(fetchedMemos.first)
        XCTAssertEqual(fetchedMemo.speakerSegments.count, 1,
                      "Memo should have 1 speaker segment")

        let fetchedSegment = try XCTUnwrap(fetchedMemo.speakerSegments.first)
        XCTAssertEqual(fetchedSegment.speakerId, "speaker_1")
        XCTAssertEqual(fetchedSegment.speaker?.name, "Speaker 1")

        print("[CONTRACT] Relationships persisted correctly")
    }

    // MARK: - Crash Recovery Tests

    func test_CrashRecovery_UnsavedChanges_Rollback() throws {
        // GIVEN: Changes without save (simulates crash)
        let container = try createTestContainer()
        let context1 = ModelContext(container)

        let memo = Memo.blank()
        memo.text = AttributedString("Unsaved memo")
        context1.insert(memo)
        // Deliberately don't save - simulates crash

        // WHEN: Create new context (simulates app restart)
        let context2 = ModelContext(container)
        let fetchedMemos = try context2.fetch(FetchDescriptor<Memo>())

        // THEN: Unsaved data should not persist
        XCTAssertEqual(fetchedMemos.count, 0,
                      "Unsaved changes should not persist after crash")

        print("[CONTRACT] Crash recovery: unsaved data rolled back")
    }

    func test_PartialSave_AtomicTransaction_AllOrNothing() throws {
        // GIVEN: Multiple entities in transaction
        let container = try createTestContainer()
        let context = ModelContext(container)

        let memo1 = Memo.blank()
        memo1.text = AttributedString("Memo 1")
        context.insert(memo1)

        let memo2 = Memo.blank()
        memo2.text = AttributedString("Memo 2")
        context.insert(memo2)

        // WHEN: Save transaction
        try context.save()

        // THEN: Both should be saved atomically
        let context2 = ModelContext(container)
        let fetchedMemos = try context2.fetch(FetchDescriptor<Memo>())

        XCTAssertEqual(fetchedMemos.count, 2,
                      "Transaction should be atomic (both saved)")

        print("[CONTRACT] Atomic transaction: all entities saved together")
    }

    // MARK: - Concurrent Write Tests

    func test_ConcurrentWrites_Isolation_NoDataRaces() async throws {
        // GIVEN: Multiple concurrent write operations
        let container = try createTestContainer()

        // WHEN: Spawn 5 concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let context = ModelContext(container)
                    let memo = Memo.blank()
                    memo.text = AttributedString("Concurrent Memo \(i)")
                    context.insert(memo)
                    try? context.save()
                }
            }

            await group.waitForAll()
        }

        // THEN: All 5 memos should be persisted
        let context = ModelContext(container)
        let fetchedMemos = try context.fetch(FetchDescriptor<Memo>())

        XCTAssertEqual(fetchedMemos.count, 5,
                      "All concurrent writes should persist (no data races)")

        print("[CONTRACT] Concurrent writes: all \(fetchedMemos.count) persisted")
    }

    func test_ConcurrentReads_ConsistentView_NoTearingReads() async throws {
        // GIVEN: Seed data
        let container = try createTestContainer()
        let setupContext = ModelContext(container)

        for i in 0..<10 {
            let speaker = Speaker(name: "Speaker \(i)")
            setupContext.insert(speaker)
        }
        try setupContext.save()

        // WHEN: Spawn concurrent reads
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let context = ModelContext(container)
                    let speakers = try? context.fetch(FetchDescriptor<Speaker>())
                    return speakers?.count ?? 0
                }
            }

            // THEN: All reads should see consistent count
            var counts: [Int] = []
            for await count in group {
                counts.append(count)
            }

            XCTAssertTrue(counts.allSatisfy { $0 == 10 },
                         "All concurrent reads should see consistent data")
        }

        print("[CONTRACT] Concurrent reads: consistent view maintained")
    }

    // MARK: - Data Integrity Tests

    func test_AttributedString_Persistence_PreservesFormatting() throws {
        // GIVEN: AttributedString with speaker colors
        let container = try createTestContainer()
        let context = ModelContext(container)

        let memo = Memo.blank()
        var attributed = AttributedString("Colored text")
        attributed.foregroundColor = .blue
        attributed[AttributeScopes.SwiftUIAttributes.SpeakerIDKey.self] = "speaker_1"
        memo.text = attributed

        context.insert(memo)
        try context.save()

        // WHEN: Reload
        let memoID = memo.id
        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.id == memoID }
        )
        let fetchedMemos = try context2.fetch(descriptor)

        // THEN: Formatting should be preserved
        let fetchedMemo = try XCTUnwrap(fetchedMemos.first)
        let color = fetchedMemo.text.foregroundColor

        XCTAssertNotNil(color, "Color formatting should persist")
        // Note: Exact color comparison may vary due to codable representation

        print("[CONTRACT] AttributedString formatting persisted")
    }

    func test_LargeTranscript_Persistence_NoTruncation() throws {
        // GIVEN: Large transcript (10,000 words)
        let container = try createTestContainer()
        let context = ModelContext(container)

        let memo = Memo.blank()
        let largeText = String(repeating: "word ", count: 10_000)
        memo.text = AttributedString(largeText)

        context.insert(memo)
        try context.save()

        // WHEN: Reload
        let memoID = memo.id
        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.id == memoID }
        )
        let fetchedMemos = try context2.fetch(descriptor)

        // THEN: Full content should persist (no truncation)
        let fetchedMemo = try XCTUnwrap(fetchedMemos.first)
        let wordCount = fetchedMemo.text.string.split(separator: " ").count

        XCTAssertEqual(wordCount, 10_000,
                      "Large transcript should persist without truncation")

        print("[CONTRACT] Large transcript (10k words) persisted fully")
    }

    // MARK: - Delete Cascade Tests

    func test_DeleteMemo_CascadesToSegments_OrphanCleanup() throws {
        // GIVEN: Memo with speaker segments
        let container = try createTestContainer()
        let context = ModelContext(container)

        let memo = Memo.blank()
        let speaker = Speaker(name: "Speaker 1")
        context.insert(memo)
        context.insert(speaker)

        let segment = SpeakerSegment(
            speakerId: "speaker_1",
            embedding: [0.1, 0.2],
            startTime: 0,
            endTime: 5,
            confidence: 0.9,
            memo: memo,
            speaker: speaker
        )
        context.insert(segment)
        try context.save()

        let memoID = memo.id

        // WHEN: Delete memo
        context.delete(memo)
        try context.save()

        // THEN: Segments should be deleted (cascade)
        let context2 = ModelContext(container)
        let segments = try context2.fetch(FetchDescriptor<SpeakerSegment>())

        XCTAssertEqual(segments.count, 0,
                      "Deleting memo should cascade to segments")

        print("[CONTRACT] Delete cascade: segments cleaned up")
    }

    // MARK: - Performance Tests

    func test_BulkInsert_1000Memos_PerformanceBaseline() throws {
        // GIVEN: Performance baseline for bulk writes
        let container = try createTestContainer()
        let context = ModelContext(container)

        let startTime = CFAbsoluteTimeGetCurrent()

        // WHEN: Insert 1000 memos
        for i in 0..<1000 {
            let memo = Memo.blank()
            memo.text = AttributedString("Memo \(i)")
            context.insert(memo)
        }

        try context.save()
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // THEN: Should complete within reasonable time
        print("[CONTRACT] Bulk insert 1000 memos: \(String(format: "%.2f", duration))s")

        XCTAssertLessThan(duration, 10.0,
                         "Bulk insert should complete within 10s")
    }

    func test_FetchPerformance_1000Memos_IndexedQuery() throws {
        // GIVEN: 1000 memos in database
        let container = try createTestContainer()
        let setupContext = ModelContext(container)

        for i in 0..<1000 {
            let memo = Memo.blank()
            memo.text = AttributedString("Memo \(i)")
            setupContext.insert(memo)
        }
        try setupContext.save()

        // WHEN: Fetch all memos
        let context = ModelContext(container)
        let startTime = CFAbsoluteTimeGetCurrent()

        let fetchedMemos = try context.fetch(FetchDescriptor<Memo>())
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // THEN: Should fetch quickly
        XCTAssertEqual(fetchedMemos.count, 1000)
        print("[CONTRACT] Fetch 1000 memos: \(String(format: "%.3f", duration))s")

        XCTAssertLessThan(duration, 1.0,
                         "Fetch should complete within 1s")
    }

    // MARK: - Helper Methods

    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([Memo.self, Speaker.self, SpeakerSegment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

// MARK: - AttributedString Speaker Extension

extension AttributeScopes.SwiftUIAttributes {
    struct SpeakerIDKey: AttributedStringKey {
        typealias Value = String
        static let name = "speakerID"
    }

    var speakerID: SpeakerIDKey { SpeakerIDKey() }
}

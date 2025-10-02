import Foundation
import SwiftData

struct TranscriptExport {
    struct SegmentJSON: Codable {
        let speakerId: String
        let speakerName: String
        let start: Double
        let end: Double
        let confidence: Float
        let text: String
    }

    struct TranscriptJSON: Codable {
        let title: String
        let createdAt: Date
        let duration: Double?
        let segments: [SegmentJSON]
    }

    static func jsonData(for memo: Memo, context: ModelContext) -> Data? {
        let segments = memo.speakerSegments.sorted { $0.startTime < $1.startTime }
        let allSpeakers = (try? context.fetch(FetchDescriptor<Speaker>())) ?? []
        let dict = Dictionary(uniqueKeysWithValues: allSpeakers.map { ($0.id, $0) })
        let mapped: [SegmentJSON] = segments.map { seg in
            let sp = dict[seg.speakerId]
            return SegmentJSON(
                speakerId: seg.speakerId,
                speakerName: sp?.name ?? seg.speakerId,
                start: seg.startTime,
                end: seg.endTime,
                confidence: seg.confidence,
                text: seg.text
            )
        }
        let payload = TranscriptJSON(title: memo.title, createdAt: memo.createdAt, duration: memo.duration, segments: mapped)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(payload)
    }

    static func markdownData(for memo: Memo, context: ModelContext) -> Data? {
        var md = "# \(memo.title)\n\n"
        if let duration = memo.duration { md += String(format: "Duração: %.0f s\n\n", duration) }
        let formatted = memo.formattedTranscriptWithSpeakers(context: context)
        md += String(formatted.characters)
        return md.data(using: .utf8)
    }

    // Unified export of speakers + transcript in a single JSON payload
    static func combinedJSONData(for memo: Memo, context: ModelContext) -> Data? {
        let speakers = (try? context.fetch(FetchDescriptor<Speaker>())) ?? []
        let spPayload: [[String: Any]] = speakers.map { s in
            [
                "id": s.id,
                "name": s.name,
                "color": s.name.hashValue & 1 == 0 ? "blue" : "green", // lightweight hint only
                "embedding": s.embedding ?? []
            ]
        }
        let transcriptData = jsonData(for: memo, context: context)
        let transcript: Any = {
            if let d = transcriptData, let obj = try? JSONSerialization.jsonObject(with: d) {
                return obj
            } else { return [:] }
        }()
        let dict: [String: Any] = [
            "memoId": UUID().uuidString,
            "title": memo.title,
            "createdAt": memo.createdAt.timeIntervalSince1970,
            "speakers": spPayload,
            "transcript": transcript
        ]
        return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
    }
}

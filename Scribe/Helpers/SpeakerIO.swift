import Foundation
import SwiftData

struct SpeakerProfile: Codable {
    let id: String
    let name: String
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    let embedding: [Float]?
    let createdAt: Date
}

enum SpeakerIOError: LocalizedError {
    case exportFailed
    case importFailed
    case invalidData

    var errorDescription: String? {
        switch self {
        case .exportFailed: return "Falha ao exportar perfis de falantes"
        case .importFailed: return "Falha ao importar perfis de falantes"
        case .invalidData: return "Dados inválidos"
        }
    }
}

@MainActor
enum SpeakerIO {
    static func encodeSpeakers(context: ModelContext) throws -> Data {
        let speakers = try context.fetch(FetchDescriptor<Speaker>())
        let profiles: [SpeakerProfile] = speakers.map {
            SpeakerProfile(
                id: $0.id,
                name: $0.name,
                colorRed: $0.colorRed,
                colorGreen: $0.colorGreen,
                colorBlue: $0.colorBlue,
                embedding: $0.embedding,
                createdAt: $0.createdAt
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(profiles)
    }
    static func exportSpeakers(context: ModelContext, to url: URL) throws {
        let data = try encodeSpeakers(context: context)
        try data.write(to: url, options: .atomic)
    }

    static func importSpeakers(context: ModelContext, from url: URL, diarizationManager: DiarizationManager?) throws {
        let data = try Data(contentsOf: url)
        try importSpeakers(data: data, context: context, diarizationManager: diarizationManager)
    }

    static func importSpeakers(data: Data, context: ModelContext, diarizationManager: DiarizationManager?) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profiles = try decoder.decode([SpeakerProfile].self, from: data)

        for p in profiles {
            // Upsert in SwiftData
            let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == p.id })
            if let existing = try context.fetch(descriptor).first {
                existing.name = p.name
                existing.colorRed = p.colorRed
                existing.colorGreen = p.colorGreen
                existing.colorBlue = p.colorBlue
                existing.embedding = p.embedding
            } else {
                let new = Speaker(id: p.id, name: p.name)
                new.colorRed = p.colorRed
                new.colorGreen = p.colorGreen
                new.colorBlue = p.colorBlue
                new.embedding = p.embedding
                context.insert(new)
            }

            // Update runtime diarizer if available
            if let emb = p.embedding, let mgr = diarizationManager {
                mgr.upsertRuntimeSpeaker(id: p.id, embedding: emb, duration: 0)
            }
        }
    }
}

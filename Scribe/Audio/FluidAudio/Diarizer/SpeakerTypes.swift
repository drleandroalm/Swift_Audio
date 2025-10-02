import Foundation

/// FASpeaker profile representation for tracking speakers across audio
/// This represents a speaker's identity, not a specific segment
@available(macOS 13.0, iOS 16.0, *)
final class FASpeaker: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var currentEmbedding: [Float]
    var duration: Float = 0
    var createdAt: Date
    var updatedAt: Date
    var updateCount: Int = 1
    var rawEmbeddings: [RawEmbedding] = []

    init(
        id: String? = nil,
        name: String? = nil,
        currentEmbedding: [Float],
        duration: Float = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        let now = Date()
        self.id = id ?? UUID().uuidString
        self.name = name ?? self.id
        self.currentEmbedding = currentEmbedding
        self.duration = duration
        self.createdAt = createdAt ?? now
        self.updatedAt = updatedAt ?? now
        self.updateCount = 1
        self.rawEmbeddings = []
    }

    /// Convert to SendableSpeaker format for cross-boundary usage.
    func toSendable() -> SendableSpeaker {
        return SendableSpeaker(from: self)
    }

    /// Update main embedding with new segment data using exponential moving average
    func updateMainEmbedding(
        duration: Float,
        embedding: [Float],
        segmentId: UUID,
        alpha: Float = 0.9
    ) {

        // Validate embedding quality
        let embeddingMagnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        guard embeddingMagnitude > 0.1 else { return }

        // Add to raw embeddings
        let rawEmbedding = RawEmbedding(
            segmentId: segmentId,
            embedding: embedding,
            timestamp: Date()
        )
        addRawEmbedding(rawEmbedding)

        // Update main embedding using exponential moving average
        if currentEmbedding.count == embedding.count {
            for i in 0..<currentEmbedding.count {
                currentEmbedding[i] = alpha * currentEmbedding[i] + (1 - alpha) * embedding[i]
            }
        }

        // Update metadata
        self.duration += duration
        self.updatedAt = Date()
        self.updateCount += 1
    }

    /// Add a raw embedding with FIFO queue management
    func addRawEmbedding(_ embedding: RawEmbedding) {
        // Validate embedding quality
        let embeddingMagnitude = sqrt(embedding.embedding.map { $0 * $0 }.reduce(0, +))
        guard embeddingMagnitude > 0.1 else { return }

        // Maintain max of 50 raw embeddings (FIFO)
        if rawEmbeddings.count >= 50 {
            rawEmbeddings.removeFirst()
        }

        rawEmbeddings.append(embedding)
        recalculateMainEmbedding()
    }

    /// Remove a raw embedding by segment ID
    @discardableResult
    func removeRawEmbedding(segmentId: UUID) -> RawEmbedding? {
        guard let index = rawEmbeddings.firstIndex(where: { $0.segmentId == segmentId }) else {
            return nil
        }

        let removed = rawEmbeddings.remove(at: index)
        recalculateMainEmbedding()
        return removed
    }

    /// Recalculate main embedding as average of all raw embeddings
    func recalculateMainEmbedding() {
        guard !rawEmbeddings.isEmpty,
            let firstEmbedding = rawEmbeddings.first,
            !firstEmbedding.embedding.isEmpty
        else { return }

        let embeddingSize = firstEmbedding.embedding.count
        var averageEmbedding = [Float](repeating: 0.0, count: embeddingSize)

        // Calculate average of all raw embeddings
        var validCount = 0
        for raw in rawEmbeddings {
            if raw.embedding.count == embeddingSize {
                for i in 0..<embeddingSize {
                    averageEmbedding[i] += raw.embedding[i]
                }
                validCount += 1
            }
        }

        // Divide by count to get average
        if validCount > 0 {
            let count = Float(validCount)
            for i in 0..<embeddingSize {
                averageEmbedding[i] /= count
            }

            self.currentEmbedding = averageEmbedding
            self.updatedAt = Date()
        }
    }

    /// Merge another speaker into this one
    func mergeWith(_ other: FASpeaker, keepName: String? = nil) {
        // Merge raw embeddings
        var allEmbeddings = rawEmbeddings + other.rawEmbeddings

        // Keep only the most recent 50 embeddings
        if allEmbeddings.count > 50 {
            allEmbeddings = Array(
                allEmbeddings
                    .sorted { $0.timestamp > $1.timestamp }
                    .prefix(50)
            )
        }

        rawEmbeddings = allEmbeddings

        // Update duration
        duration += other.duration

        // Update name if specified
        if let keepName = keepName {
            name = keepName
        }

        // Recalculate main embedding
        recalculateMainEmbedding()

        updatedAt = Date()
        updateCount += other.updateCount
    }

    static func == (lhs: FASpeaker, rhs: FASpeaker) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Raw embedding tracking for speaker evolution over time
@available(macOS 13.0, iOS 16.0, *)
struct RawEmbedding: Codable, Sendable {
    let segmentId: UUID
    let embedding: [Float]
    let timestamp: Date

    init(segmentId: UUID = UUID(), embedding: [Float], timestamp: Date = Date()) {
        self.segmentId = segmentId
        self.embedding = embedding
        self.timestamp = timestamp
    }
}

/// Sendable speaker data for cross-async boundary usage
@available(macOS 13.0, iOS 16.0, *)
struct SendableSpeaker: Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let duration: Float
    let mainEmbedding: [Float]
    let createdAt: Date
    let updatedAt: Date

    /// Label for display
    var label: String {
        if name.isEmpty {
            return "Speaker #\(id)"
        } else {
            return name
        }
    }

    init(id: Int, name: String, duration: Float, mainEmbedding: [Float], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.duration = duration
        self.mainEmbedding = mainEmbedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Convenience init from FluidAudio's FASpeaker type
    init(from speaker: FASpeaker) {
        // Try to parse as integer first, otherwise use hash of UUID
        if let numericId = Int(speaker.id) {
            self.id = numericId
        } else {
            // For UUID strings, use a stable hash
            self.id = abs(speaker.id.hashValue)
        }
        self.name = speaker.name
        self.duration = speaker.duration
        self.mainEmbedding = speaker.currentEmbedding
        self.createdAt = speaker.createdAt
        self.updatedAt = speaker.updatedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SendableSpeaker, rhs: SendableSpeaker) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name
    }
}

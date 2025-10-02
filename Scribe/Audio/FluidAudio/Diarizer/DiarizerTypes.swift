import Foundation

// MARK: - Diarization Pipeline Types
// This file contains types used in the diarization processing pipeline
// For speaker profile types, see SpeakerTypes.swift

struct DiarizerConfig: Sendable {
    /// Threshold for clustering speaker embeddings (0.5-0.9). Lower = more speakers.
    var clusteringThreshold: Float = 0.7

    /// Minimum speech segment duration in seconds. Shorter segments are discarded.
    var minSpeechDuration: Float = 1.0

    /// Minimum segment duration for updating speaker embeddings (seconds).
    var minEmbeddingUpdateDuration: Float = 2.0

    /// Minimum silence gap (seconds) before splitting same speaker's segments.
    var minSilenceGap: Float = 0.5

    /// Expected number of speakers (-1 for automatic).
    var numClusters: Int = -1

    /// Minimum active frames for valid speech detection.
    var minActiveFramesCount: Float = 10.0

    /// Enable debug logging.
    var debugMode: Bool = false

    /// Duration of audio chunks for processing (seconds).
    var chunkDuration: Float = 10.0

    /// Overlap between chunks (seconds).
    var chunkOverlap: Float = 0.0

    static let `default` = DiarizerConfig()

    init(
        clusteringThreshold: Float = 0.7,
        minSpeechDuration: Float = 1.0,
        minEmbeddingUpdateDuration: Float = 2.0,
        minSilenceGap: Float = 0.5,
        numClusters: Int = -1,
        minActiveFramesCount: Float = 10.0,
        debugMode: Bool = false,
        chunkDuration: Float = 10.0,
        chunkOverlap: Float = 0.0
    ) {
        self.clusteringThreshold = clusteringThreshold
        self.minSpeechDuration = minSpeechDuration
        self.minEmbeddingUpdateDuration = minEmbeddingUpdateDuration
        self.minSilenceGap = minSilenceGap
        self.numClusters = numClusters
        self.minActiveFramesCount = minActiveFramesCount
        self.debugMode = debugMode
        self.chunkDuration = chunkDuration
        self.chunkOverlap = chunkOverlap
    }
}

struct PipelineTimings: Sendable, Codable {
    let modelDownloadSeconds: TimeInterval
    let modelCompilationSeconds: TimeInterval
    let audioLoadingSeconds: TimeInterval
    let segmentationSeconds: TimeInterval
    let embeddingExtractionSeconds: TimeInterval
    let speakerClusteringSeconds: TimeInterval
    let postProcessingSeconds: TimeInterval
    let totalInferenceSeconds: TimeInterval
    let totalProcessingSeconds: TimeInterval

    init(
        modelDownloadSeconds: TimeInterval = 0,
        modelCompilationSeconds: TimeInterval = 0,
        audioLoadingSeconds: TimeInterval = 0,
        segmentationSeconds: TimeInterval = 0,
        embeddingExtractionSeconds: TimeInterval = 0,
        speakerClusteringSeconds: TimeInterval = 0,
        postProcessingSeconds: TimeInterval = 0
    ) {
        self.modelDownloadSeconds = modelDownloadSeconds
        self.modelCompilationSeconds = modelCompilationSeconds
        self.audioLoadingSeconds = audioLoadingSeconds
        self.segmentationSeconds = segmentationSeconds
        self.embeddingExtractionSeconds = embeddingExtractionSeconds
        self.speakerClusteringSeconds = speakerClusteringSeconds
        self.postProcessingSeconds = postProcessingSeconds
        self.totalInferenceSeconds =
            segmentationSeconds + embeddingExtractionSeconds + speakerClusteringSeconds
        self.totalProcessingSeconds =
            modelDownloadSeconds + modelCompilationSeconds + audioLoadingSeconds
            + segmentationSeconds + embeddingExtractionSeconds + speakerClusteringSeconds
            + postProcessingSeconds
    }

    var stagePercentages: [String: Double] {
        guard totalProcessingSeconds > 0 else {
            return [:]
        }

        return [
            "Model Download": (modelDownloadSeconds / totalProcessingSeconds) * 100,
            "Model Compilation": (modelCompilationSeconds / totalProcessingSeconds) * 100,
            "Audio Loading": (audioLoadingSeconds / totalProcessingSeconds) * 100,
            "Segmentation": (segmentationSeconds / totalProcessingSeconds) * 100,
            "Embedding Extraction": (embeddingExtractionSeconds / totalProcessingSeconds) * 100,
            "Speaker Clustering": (speakerClusteringSeconds / totalProcessingSeconds) * 100,
            "Post Processing": (postProcessingSeconds / totalProcessingSeconds) * 100,
        ]
    }

    var bottleneckStage: String {
        let stages = [
            ("Model Download", modelDownloadSeconds),
            ("Model Compilation", modelCompilationSeconds),
            ("Audio Loading", audioLoadingSeconds),
            ("Segmentation", segmentationSeconds),
            ("Embedding Extraction", embeddingExtractionSeconds),
            ("Speaker Clustering", speakerClusteringSeconds),
            ("Post Processing", postProcessingSeconds),
        ]

        return stages.max(by: { $0.1 < $1.1 })?.0 ?? "Unknown"
    }
}

struct DiarizationResult: Sendable {
    let segments: [TimedSpeakerSegment]

    /// FASpeaker database with embeddings (only populated when debugMode is enabled)
    let speakerDatabase: [String: [Float]]?

    /// Performance timings (only populated when debugMode is enabled)
    let timings: PipelineTimings?

    init(
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]? = nil,
        timings: PipelineTimings? = nil
    ) {
        self.segments = segments
        self.speakerDatabase = speakerDatabase
        self.timings = timings
    }
}

/// Represents a segment of speech from a specific speaker with timing information
/// This is used for diarization results - "who spoke when"
/// For speaker profiles, see FASpeaker struct in SpeakerTypes.swift
struct TimedSpeakerSegment: Sendable, Identifiable {
    let id = UUID()
    let speakerId: String
    let embedding: [Float]
    let startTimeSeconds: Float
    let endTimeSeconds: Float
    let qualityScore: Float

    var durationSeconds: Float {
        endTimeSeconds - startTimeSeconds
    }

    init(
        speakerId: String, embedding: [Float], startTimeSeconds: Float, endTimeSeconds: Float,
        qualityScore: Float
    ) {
        self.speakerId = speakerId
        self.embedding = embedding
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.qualityScore = qualityScore
    }
}

struct ModelPaths: Sendable {
    let segmentationPath: URL
    let embeddingPath: URL

    init(segmentationPath: URL, embeddingPath: URL) {
        self.segmentationPath = segmentationPath
        self.embeddingPath = embeddingPath
    }
}

struct AudioValidationResult: Sendable {
    let isValid: Bool
    let durationSeconds: Float
    let issues: [String]

    init(isValid: Bool, durationSeconds: Float, issues: [String] = []) {
        self.isValid = isValid
        self.durationSeconds = durationSeconds
        self.issues = issues
    }
}

enum DiarizerError: Error, LocalizedError {
    case notInitialized
    case modelDownloadFailed
    case modelCompilationFailed
    case embeddingExtractionFailed
    case invalidAudioData
    case processingFailed(String)
    case memoryAllocationFailed
    case invalidArrayBounds

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Diarization system not initialized. Call initialize() first."
        case .modelDownloadFailed:
            return "Failed to download required models."
        case .modelCompilationFailed:
            return "Failed to compile CoreML models."
        case .embeddingExtractionFailed:
            return "Failed to extract speaker embedding from audio."
        case .invalidAudioData:
            return "Invalid audio data provided."
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .memoryAllocationFailed:
            return "Failed to allocate ANE-aligned memory."
        case .invalidArrayBounds:
            return "Array bounds exceeded for zero-copy view."
        }
    }
}

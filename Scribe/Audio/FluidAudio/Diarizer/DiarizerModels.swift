@preconcurrency import CoreML
import Foundation
import OSLog

enum CoreMLDiarizer {
    typealias SegmentationModel = MLModel
    typealias EmbeddingModel = MLModel
}

@available(macOS 13.0, iOS 16.0, *)
struct DiarizerModels: Sendable {

    /// Required model names for Diarizer
    static let requiredModelNames = ModelNames.Diarizer.requiredModels

    let segmentationModel: CoreMLDiarizer.SegmentationModel
    let embeddingModel: CoreMLDiarizer.EmbeddingModel
    let downloadDuration: TimeInterval
    let compilationDuration: TimeInterval

    init(
        segmentation: MLModel, embedding: MLModel, downloadDuration: TimeInterval = 0,
        compilationDuration: TimeInterval = 0
    ) {
        self.segmentationModel = segmentation
        self.embeddingModel = embedding
        self.downloadDuration = downloadDuration
        self.compilationDuration = compilationDuration
    }
}

// -----------------------------
// MARK: - Default Model Location (Offline Only)
// -----------------------------

extension DiarizerModels {
    static func defaultModelsDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return
            applicationSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
    }

    static func defaultConfiguration() -> MLModelConfiguration {
        let config = MLModelConfiguration()
        // Enable Float16 optimization for ~2x speedup
        config.allowLowPrecisionAccumulationOnGPU = true
        let isCI = ProcessInfo.processInfo.environment["CI"] != nil
        config.computeUnits = isCI ? .cpuAndNeuralEngine : .all
        return config
    }
}

// -----------------------------
// MARK: - Predownloaded models.
// -----------------------------

extension DiarizerModels {

    /// Load the models from the given local files.
    ///
    /// If the models fail to load, no recovery will be attempted. No models are downloaded.
    ///
    static func load(
        localSegmentationModel: URL,
        localEmbeddingModel: URL,
        configuration: MLModelConfiguration? = nil
    ) async throws -> DiarizerModels {

        let logger = AppLogger(category: "DiarizerModels")
        logger.info("Loading predownloaded models")

        let configuration = configuration ?? defaultConfiguration()

        let startTime = Date()
        let segmentationModel = try MLModel(contentsOf: localSegmentationModel, configuration: configuration)
        let embeddingModel = try MLModel(contentsOf: localEmbeddingModel, configuration: configuration)

        let endTime = Date()
        let loadDuration = endTime.timeIntervalSince(startTime)
        return DiarizerModels(
            segmentation: segmentationModel, embedding: embeddingModel, downloadDuration: 0,
            compilationDuration: loadDuration)
    }
}

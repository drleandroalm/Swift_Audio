import Foundation

/// Model repositories on HuggingFace
enum Repo: String, CaseIterable {
    case vad = "FluidInference/silero-vad-coreml"
    case parakeet = "FluidInference/parakeet-tdt-0.6b-v3-coreml"
    case parakeetV2 = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    case diarizer = "FluidInference/speaker-diarization-coreml"

    var folderName: String {
        rawValue.split(separator: "/").last?.description ?? rawValue
    }

}

/// Centralized model names for all FluidAudio components
enum ModelNames {

    /// Diarizer model names
    enum Diarizer {
        static let segmentation = "pyannote_segmentation"
        static let embedding = "wespeaker_v2"

        static let segmentationFile = segmentation + ".mlmodelc"
        static let embeddingFile = embedding + ".mlmodelc"

        static let requiredModels: Set<String> = [
            segmentationFile,
            embeddingFile,
        ]
    }

    /// ASR model names
    enum ASR {
        static let preprocessor = "Preprocessor"
        static let encoder = "Encoder"
        static let decoder = "Decoder"
        static let joint = "JointDecision"

        // Shared vocabulary file across all model versions
        static let vocabularyFile = "parakeet_vocab.json"

        static let preprocessorFile = preprocessor + ".mlmodelc"
        static let encoderFile = encoder + ".mlmodelc"
        static let decoderFile = decoder + ".mlmodelc"
        static let jointFile = joint + ".mlmodelc"

        static let requiredModels: Set<String> = [
            preprocessorFile,
            encoderFile,
            decoderFile,
            jointFile,
        ]

        /// Get vocabulary filename for specific model version
        static func vocabulary(for repo: Repo) -> String {
            return vocabularyFile
        }
    }

    /// VAD model names
    enum VAD {
        static let sileroVad = "silero-vad-unified-256ms-v6.0.0"

        static let sileroVadFile = sileroVad + ".mlmodelc"

        static let requiredModels: Set<String> = [
            sileroVadFile
        ]
    }

    @available(macOS 13.0, iOS 16.0, *)
    static func getRequiredModelNames(for repo: Repo) -> Set<String> {
        switch repo {
        case .vad:
            return ModelNames.VAD.requiredModels
        case .parakeet, .parakeetV2:
            return ModelNames.ASR.requiredModels
        case .diarizer:
            return ModelNames.Diarizer.requiredModels
        }
    }

}

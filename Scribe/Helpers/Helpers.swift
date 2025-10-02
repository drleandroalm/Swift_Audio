import AVFoundation
import Foundation
import SwiftUI

enum TranscriptionState {
    case transcribing
    case notTranscribing
}

public enum TranscriptionError: Error {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case noInternetForModelDownload
    case audioFilePathNotFound

    var descriptionString: String {
        switch self {

        case .couldNotDownloadModel:
            return "Não foi possível baixar o modelo."
        case .failedToSetupRecognitionStream:
            return "Não foi possível configurar a transmissão de reconhecimento de voz."
        case .invalidAudioDataType:
            return "Formato de áudio não suportado."
        case .localeNotSupported:
            return "Esta localidade ainda não é compatível com o SpeechAnalyzer."
        case .noInternetForModelDownload:
            return
                "O modelo não pôde ser baixado porque o dispositivo está sem conexão com a internet."
        case .audioFilePathNotFound:
            return "Não foi possível gravar o áudio no arquivo."
        }
    }
}

public enum RecordingState: Equatable {
    case stopped
    case recording
    case paused
}

public enum PlaybackState: Equatable {
    case playing
    case notPlaying
}

public struct AudioData: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer
    var time: AVAudioTime
}

// Ask for permission to access the microphone.
extension Recorder {
    nonisolated func isAuthorized() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }

        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

extension AVAudioPlayerNode {
    var currentTime: TimeInterval {
        guard let nodeTime: AVAudioTime = self.lastRenderTime,
            let playerTime: AVAudioTime = self.playerTime(forNodeTime: nodeTime)
        else { return 0 }

        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}

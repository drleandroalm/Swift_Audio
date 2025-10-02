import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import SwiftData
import Accelerate
#if os(macOS)
import AppKit
#endif

// MARK: - Local buffer conversion (16kHz mono float)
extension SpeakerEnrollmentController {
    fileprivate func convertTo16kMonoFloat(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let mono16k = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        if sourceFormat.sampleRate == 16000,
           sourceFormat.channelCount == 1,
           sourceFormat.commonFormat == .pcmFormatFloat32,
           let cd = buffer.floatChannelData {
            let count = Int(buffer.frameLength)
            return Array(UnsafeBufferPointer(start: cd[0], count: count))
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: mono16k) else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (16000.0 / sourceFormat.sampleRate) + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: mono16k, frameCapacity: capacity) else { return nil }
        let servedFlag = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        servedFlag.initialize(to: 0)
        defer {
            servedFlag.deinitialize(count: 1)
            servedFlag.deallocate()
        }
        let status = converter.convert(to: out, error: nil) { _, outStatus in
            if servedFlag.pointee == 0 {
                servedFlag.pointee = 1
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .endOfStream
            return nil
        }
        guard status == .haveData || status == .inputRanDry || status == .endOfStream,
              let outData = out.floatChannelData else { return nil }
        let frames = Int(out.frameLength)
        var result = Array(UnsafeBufferPointer(start: outData[0], count: frames))
        if let maxAmp = result.map({ abs($0) }).max(), maxAmp > 1.0 { result = result.map { $0 / maxAmp } }
        return result
    }
}

// MARK: - Enrollment Controller

@Observable
final class SpeakerEnrollmentController {
    var name: String = ""
    var isRecording: Bool = false
    var isProcessing: Bool = false
    var errorMessage: String?
    var infoMessage: String?
    var capturedSeconds: Double = 0
    var minRequiredSeconds: Double = 8.0
    var inputLevelRMS: Float = 0

    private let engine = AVAudioEngine()
    private(set) var samples: [Float] = []
    private(set) var clips: [[Float]] = []

    func start() throws {
        guard !isRecording else { return }

        // macOS: verify mic access
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            // Will prompt implicitly when starting capture
            break
        case .denied, .restricted:
            errorMessage = "Acesso ao microfone negado. Ative nas Preferências do Sistema."
            return
        @unknown default:
            break
        }

        samples.removeAll()
        capturedSeconds = 0
        inputLevelRMS = 0

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if let floats = self.convertTo16kMonoFloat(buffer) {
                self.samples.append(contentsOf: floats)
                self.capturedSeconds = Double(self.samples.count) / 16000.0
                self.inputLevelRMS = Self.rmsLevel(of: floats)
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        infoMessage = "Gravando amostra de voz..."
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        infoMessage = "Amostra capturada. Pronta para inscrever."
    }

    func reset() {
        stop()
        samples.removeAll()
        clips.removeAll()
        capturedSeconds = 0
        inputLevelRMS = 0
        errorMessage = nil
        infoMessage = nil
    }

    func addCurrentClip() {
        guard !samples.isEmpty else { return }
        clips.append(samples)
        samples.removeAll()
        capturedSeconds = 0
        infoMessage = "Amostra adicionada. Grave outra ou importe um arquivo."
    }

    func addImportedClip(_ floats: [Float]) {
        guard !floats.isEmpty else { return }
        clips.append(floats)
        infoMessage = "Arquivo importado com sucesso."
    }

    private static func rmsLevel(of chunk: [Float]) -> Float {
        guard !chunk.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_measqv(chunk, 1, &sum, vDSP_Length(chunk.count))
        let rms = sqrt(sum)
        return min(max(rms * 4.0, 0), 1) // normalize for UI
    }
}

// MARK: - Enrollment Sheet

struct SpeakerEnrollmentView: View {
    let diarizationManager: DiarizationManager

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var controller = SpeakerEnrollmentController()

    var body: some View {
        #if os(macOS)
        content
            .frame(width: 520)
        #else
        content
        #endif
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 18) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Inscrever novo falante")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Name field
            VStack(alignment: .leading, spacing: 6) {
                Text("Nome do falante")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Ex.: Alice", text: $controller.name)
                    .textFieldStyle(.roundedBorder)
            }

            // Capture status and meters
            VStack(spacing: 10) {
                // Progress toward min seconds
                ProgressView(value: min(controller.capturedSeconds / controller.minRequiredSeconds, 1.0)) {
                    Text("Duração capturada: \(format(controller.capturedSeconds)) / \(format(controller.minRequiredSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Input level bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(gradient)
                            .frame(width: geo.size.width * CGFloat(controller.inputLevelRMS))
                    }
                }
                .frame(height: 8)

                if let info = controller.infoMessage, !info.isEmpty {
                    Text(info)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("Amostras acumuladas: \(controller.clips.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        controller.addCurrentClip()
                    } label: {
                        Label("Adicionar amostra", systemImage: "plus.circle")
                    }
                    .buttonStyle(.glass)
                    .disabled(controller.samples.isEmpty || controller.isRecording)

                    #if os(macOS)
                    Button {
                        importFromFile()
                    } label: {
                        Label("Importar arquivo", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.glass)
                    #endif
                }
            }

            HStack(spacing: 12) {
                Button(controller.isRecording ? "Parar" : "Gravar") {
                    Task {
                        if controller.isRecording {
                            controller.stop()
                        } else {
                            do { try controller.start() } catch { controller.errorMessage = error.localizedDescription }
                        }
                    }
                }
                .buttonStyle(.glass)
                .tint(controller.isRecording ? .red : .blue)

                Button("Limpar") { controller.reset() }
                    .buttonStyle(.glass)

                Spacer()

                Button("Cancelar") { dismiss() }
                    .buttonStyle(.glass)

                Button(action: enroll) {
                    if controller.isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Salvar")
                    }
                }
                .buttonStyle(.glass)
                .tint(.green)
                .disabled(!canEnroll)
            }
        }
        .padding(20)
        .alert("Erro na inscrição", isPresented: .constant(controller.errorMessage != nil)) {
            Button("OK") { controller.errorMessage = nil }
        } message: {
            if let msg = controller.errorMessage { Text(msg) }
        }
    }

    private var canEnroll: Bool {
        !controller.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && ((controller.capturedSeconds >= controller.minRequiredSeconds) || !controller.clips.isEmpty)
        && !controller.isRecording
        && !controller.isProcessing
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [.green.opacity(0.8), .yellow.opacity(0.8), .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
    }

    private func enroll() {
        controller.isProcessing = true
        controller.errorMessage = nil
        let name = controller.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var allClips = controller.clips
        if !controller.samples.isEmpty { allClips.append(controller.samples) }
        Task { @MainActor in
            do {
                if allClips.count > 1 {
                    _ = try await diarizationManager.enrollSpeaker(fromClips: allClips, name: name, in: modelContext)
                } else if let single = allClips.first {
                    _ = try await diarizationManager.enrollSpeaker(from: single, name: name, in: modelContext)
                } else {
                    throw SpeakerEnrollmentError.invalidAudio("Nenhuma amostra disponível")
                }
                dismiss()
            } catch {
                controller.errorMessage = error.localizedDescription
            }
            controller.isProcessing = false
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}

#if os(macOS)
private extension SpeakerEnrollmentView {
    func importFromFile() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.audio]
        } else {
            panel.allowedFileTypes = ["wav", "m4a", "mp3", "caf", "aiff", "aif"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let capacity = AVAudioFrameCount(file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                    controller.errorMessage = "Falha ao alocar buffer de áudio"
                    return
                }
                try file.read(into: buffer)
                if let floats = controller.convertTo16kMonoFloat(buffer) {
                    controller.addImportedClip(floats)
                } else {
                    controller.errorMessage = "Falha ao converter áudio para 16kHz mono"
                }
            } catch {
                controller.errorMessage = "Falha ao importar arquivo: \(error.localizedDescription)"
            }
        }
    }
}
#endif

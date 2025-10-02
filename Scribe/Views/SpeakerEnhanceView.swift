import SwiftUI
import AVFoundation
import Accelerate
import SwiftData
#if os(macOS)
import AppKit
#endif

@Observable
final class SpeakerEnhanceController {
    var isRecording: Bool = false
    var isProcessing: Bool = false
    var errorMessage: String?
    var infoMessage: String?
    var capturedSeconds: Double = 0
    var inputLevelRMS: Float = 0
    private let engine = AVAudioEngine()
    private(set) var samples: [Float] = []
    private(set) var clips: [[Float]] = []

    func start() throws {
        guard !isRecording else { return }
        samples.removeAll(); capturedSeconds = 0; inputLevelRMS = 0
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
        engine.prepare(); try engine.start(); isRecording = true
        infoMessage = "Gravando amostra..."
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0); engine.stop(); isRecording = false
        infoMessage = "Amostra capturada. Adicione ou aplique." 
    }

    func reset() {
        stop(); samples.removeAll(); clips.removeAll(); capturedSeconds = 0; inputLevelRMS = 0
        errorMessage = nil; infoMessage = nil
    }

    func addCurrentClip() { guard !samples.isEmpty else { return }; clips.append(samples); samples.removeAll(); capturedSeconds = 0 }
    func addImportedClip(_ floats: [Float]) { guard !floats.isEmpty else { return }; clips.append(floats) }

    private static func rmsLevel(of chunk: [Float]) -> Float {
        guard !chunk.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_measqv(chunk, 1, &sum, vDSP_Length(chunk.count))
        let rms = sqrt(sum)
        return min(max(rms * 4.0, 0), 1)
    }
}

struct SpeakerEnhanceView: View {
    let diarizationManager: DiarizationManager
    let speaker: Speaker

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var controller = SpeakerEnhanceController()

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle().fill(speaker.displayColor).frame(width: 10, height: 10)
                Text("Aprimorar falante: \(speaker.name)").font(.headline).fontWeight(.semibold)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(controller.inputLevelRMS))
                }
            }
            .frame(height: 8)

            if let info = controller.infoMessage { Text(info).font(.footnote).foregroundStyle(.secondary) }

            HStack(spacing: 8) {
                Text("Amostras acumuladas: \(controller.clips.count)").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Adicionar amostra") { controller.addCurrentClip() }.buttonStyle(.glass).disabled(controller.samples.isEmpty || controller.isRecording)
                #if os(macOS)
                Button("Importar arquivo") { importFromFile() }.buttonStyle(.glass)
                #endif
            }

            HStack(spacing: 12) {
                Button(controller.isRecording ? "Parar" : "Gravar") { try? (controller.isRecording ? controller.stop() : controller.start()) }
                    .buttonStyle(.glass).tint(controller.isRecording ? .red : .blue)
                Button("Limpar") { controller.reset() }.buttonStyle(.glass)
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(.glass)
                Button(action: applyEnhancement) {
                    controller.isProcessing ? AnyView(AnyView(ProgressView().controlSize(.small))) : AnyView(Text("Aplicar"))
                }.buttonStyle(.glass).tint(.green).disabled(!canApply)
            }
        }
        .padding(20)
        .alert("Erro ao aprimorar", isPresented: .constant(controller.errorMessage != nil)) {
            Button("OK") { controller.errorMessage = nil }
        } message: { if let m = controller.errorMessage { Text(m) } }
    }

    private var canApply: Bool { (!controller.clips.isEmpty || !controller.samples.isEmpty) && !controller.isRecording && !controller.isProcessing }

    private func applyEnhancement() {
        controller.isProcessing = true
        var clips = controller.clips
        if !controller.samples.isEmpty { clips.append(controller.samples) }
        Task { @MainActor in
            do {
                _ = try await diarizationManager.enhanceSpeaker(id: speaker.id, withClips: clips, in: modelContext)
                dismiss()
            } catch { controller.errorMessage = error.localizedDescription }
            controller.isProcessing = false
        }
    }

    #if os(macOS)
    private func importFromFile() {
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
                controller.errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}

// MARK: - Local buffer conversion utility for enhancement
extension SpeakerEnhanceController {
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

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Accelerate
import SwiftData
#if os(macOS)
import AppKit
#endif

@Observable
final class SimilarityVerificationController {
    var isRecording: Bool = false
    var isProcessing: Bool = false
    var errorMessage: String?
    var infoMessage: String?
    var confidence: Float? = nil
    var inputLevelRMS: Float = 0

    private let engine = AVAudioEngine()
    private(set) var samples: [Float] = []

    func start() throws {
        guard !isRecording else { return }
        samples.removeAll()
        inputLevelRMS = 0
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if let floats = self.convertTo16kMonoFloat(buffer) {
                self.samples.append(contentsOf: floats)
                self.inputLevelRMS = Self.rmsLevel(of: floats)
            }
        }
        engine.prepare()
        try engine.start()
        isRecording = true
        infoMessage = "Gravando amostra de verificação..."
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        infoMessage = "Amostra capturada. Verifique a semelhança."
    }

    func reset() {
        stop()
        samples.removeAll()
        inputLevelRMS = 0
        confidence = nil
        errorMessage = nil
        infoMessage = nil
    }

    func replaceSamples(_ floats: [Float]) {
        samples = floats
    }

    private static func rmsLevel(of chunk: [Float]) -> Float {
        guard !chunk.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_measqv(chunk, 1, &sum, vDSP_Length(chunk.count))
        let rms = sqrt(sum)
        return min(max(rms * 4.0, 0), 1)
    }
}

struct SimilarityVerificationView: View {
    let diarizationManager: DiarizationManager
    let targetSpeaker: Speaker

    @Environment(\.dismiss) private var dismiss
    @State private var controller = SimilarityVerificationController()
    @Environment(AppSettings.self) private var settings
    @State private var autoVerify = false
    @State private var threshold: Float = 0.8
    @State private var liveTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("Verificar semelhança com \(targetSpeaker.name)")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Mic level bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(controller.inputLevelRMS))
                }
            }
            .frame(height: 8)

            if let info = controller.infoMessage { Text(info).font(.footnote).foregroundStyle(.secondary) }

            if let conf = controller.confidence {
                VStack(spacing: 8) {
                    let percent = Int((conf * 100).rounded())
                    Text("Confiança: \(percent)%")
                        .font(.title3)
                        .fontWeight(.semibold)
                    ProgressView(value: Double(conf))
                        .tint(conf > 0.85 ? .green : (conf > 0.6 ? .yellow : .red))
                    let matched = conf >= threshold
                    Text(matched ? "Compatível" : "Não compatível")
                        .font(.footnote)
                        .foregroundStyle(matched ? .green : .secondary)
                }
            }

            // Threshold and auto verify controls
            HStack(spacing: 12) {
                Toggle("Verificação contínua", isOn: $autoVerify)
                Spacer()
                Text("Limite")
                Slider(value: Binding(get: { Double(threshold) }, set: { threshold = Float($0) }), in: 0.5...0.95, step: 0.05)
                Text(String(format: "%.2f", threshold)).font(.caption).monospacedDigit()
            }

            HStack(spacing: 12) {
                Button(controller.isRecording ? "Parar" : "Gravar") {
                    Task {
                        if controller.isRecording {
                            controller.stop()
                            liveTask?.cancel(); liveTask = nil
                        } else {
                            try? controller.start()
                            if autoVerify { startLiveLoop() }
                        }
                    }
                }
                .buttonStyle(.glass)
                .tint(controller.isRecording ? .red : .blue)

                #if os(macOS)
                Button("Importar arquivo") { importFromFile() }
                    .buttonStyle(.glass)
                #endif

                Spacer()

                Button("Cancelar") { dismiss() }.buttonStyle(.glass)
                Button("Verificar") { verify() }
                    .buttonStyle(.glass)
                    .tint(.green)
                    .disabled(controller.samples.isEmpty || controller.isRecording)
            }
        }
        .padding(20)
        .alert("Erro na verificação", isPresented: .constant(controller.errorMessage != nil)) {
            Button("OK") { controller.errorMessage = nil }
        } message: { if let msg = controller.errorMessage { Text(msg) } }
        .onChange(of: autoVerify) { _, newValue in
            if newValue && controller.isRecording { startLiveLoop() } else { liveTask?.cancel(); liveTask = nil }
        }
        .onDisappear { liveTask?.cancel(); liveTask = nil }
        .onAppear {
            // Seed defaults from Settings
            autoVerify = settings.verifyAutoEnabled
            threshold = settings.verifyThreshold
        }
    }

    private func verify() {
        controller.isProcessing = true
        Task { @MainActor in
            do {
                let score = try await diarizationManager.similarity(of: controller.samples, to: targetSpeaker)
                controller.confidence = score
            } catch {
                controller.errorMessage = error.localizedDescription
            }
            controller.isProcessing = false
        }
    }

    private func startLiveLoop() {
        liveTask?.cancel()
        liveTask = Task { [weak controller] in
            while !(Task.isCancelled) {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                guard let controller, controller.isRecording else { continue }
                // Take last ~1s of audio for quick check
                let count = controller.samples.count
                let take = min(count, 16000)
                if take > 4000 { // minimal amount
                    let slice = Array(controller.samples.suffix(take))
                    await MainActor.run {
                        Task { @MainActor in
                            do { controller.confidence = try await diarizationManager.similarity(of: slice, to: targetSpeaker) } catch { controller.errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
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
                    controller.replaceSamples(floats)
                } else {
                    controller.errorMessage = "Falha ao converter áudio para 16kHz mono"
                }
            } catch {
                controller.errorMessage = "Falha ao importar arquivo: \(error.localizedDescription)"
            }
        }
    }
    #endif
}

// MARK: - Local buffer conversion (16kHz mono float)
extension SimilarityVerificationController {
    fileprivate func convertTo16kMonoFloat(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let mono16k = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        // Fast path: already 16k mono float
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

@preconcurrency import AVFoundation
import Foundation
import os
import SwiftUI
import SwiftData

final class Recorder: @unchecked Sendable {
    enum StopCause: String { case user, silenceTimeout, pipelineBackpressure, error }
    private var outputContinuation: AsyncStream<AudioData>.Continuation?

    // Separate engines for recording and playback to avoid conflicts
    private let recordingEngine: AVAudioEngine
    private let playbackEngine: AVAudioEngine

    private let transcriber: any SpokenWordTranscribing
    private var audioFile: AVAudioFile?
    var playerNode: AVAudioPlayerNode?

    private var memo: Memo
    private let url: URL
    
    // Diarization support
    private let diarizationManager: DiarizationManager
    private let modelContext: ModelContext
    // Reusable converter to the analyzer's preferred stream format (typically 16 kHz mono)
    // We keep previous naming to minimize churn but the format now mirrors the SpeechAnalyzer's input.
    private var convertFormat16k: AVAudioFormat?
    private var converterTo16k: AVAudioConverter?
    // Cache the analyzer's preferred stream format on the main actor and use it off-actor safely
    private var preferredStreamFormat: AVAudioFormat?

    // Dedicated queue to avoid QoS inversions for audio engine operations
    private let audioQueue = DispatchQueue(label: "Recorder.AudioQueue", qos: .userInteractive)

    // Tracks whether any input audio buffers have been observed after starting
    private(set) var hasReceivedAudio: Bool = false
    // Tracks whether any input audio buffers have ever been observed in this session
    private var everReceivedAudio: Bool = false
    private var firstBufferMonitor: Task<Void, Never>?
    private var loggedFirstTapDetails: Bool = false
    static let firstBufferNotification = Notification.Name("RecorderFirstBufferReceived")
    static let didStopWithCauseNotification = Notification.Name("RecorderDidStopWithCause")
    private var noAudioReinitAttempts = 0
    // Observers for route/config changes
    private var observers: [NSObjectProtocol] = []
    // Reconfiguration gate to avoid overlapping re-inits
    private var isReconfiguring: Bool = false
    // macOS default input listener token
    #if os(macOS)
    private var audioDeviceObserverId: UUID?
    #endif
    // Converter error backoff
    private var converterErrorCount: Int = 0
    private var lastConverterErrorTs: CFAbsoluteTime = 0
    // Segmented file reopen control
    private var fileSegmentIndex: Int = 0
    #if os(macOS)
    // Bind and re-assert the selected input device for the session to mitigate HAL churn
    private var boundInputDevice: AudioInputDevice?
    #endif

    // Helper to hop to the audio queue from async contexts
    private func runOnAudioQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            audioQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Deterministically stop audio engines and release resources
    func teardown() async {
        // Stop recording engine and remove taps
        try? await runOnAudioQueue { [weak self] in
            guard let self = self else { return }
            if self.recordingEngine.isRunning {
                self.recordingEngine.stop()
            }
            self.recordingEngine.inputNode.removeTap(onBus: 0)
        }

        // Finish any pending audio streaming continuation
        outputContinuation?.finish()
        outputContinuation = nil

        // Stop playback engine and detach any player node
        await stopPlaying()

        // Clear file handle
        audioFile = nil

        firstBufferMonitor?.cancel()
        firstBufferMonitor = nil
    }

    init(transcriber: any SpokenWordTranscribing, memo: Memo, diarizationManager: DiarizationManager, modelContext: ModelContext) {
        self.recordingEngine = AVAudioEngine()
        self.playbackEngine = AVAudioEngine()
        self.transcriber = transcriber
        self.memo = memo
        self.diarizationManager = diarizationManager
        self.modelContext = modelContext
        self.url = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension("wav")
    }

    func record() async throws {
        print("DEPURAÇÃO [Gravador]: Iniciando sessão de gravação")
        Log.audio.info("Recording session starting")
        // Proactively ensure ML models are warm before we start streaming
        ModelWarmupService.shared.warmupIfNeeded()

        // Defer exposing the recording URL on the memo until the file is created

        guard await isAuthorized() else {
            print("DEPURAÇÃO [Gravador]: Falha na autorização de gravação")
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        // Set up audio session for both iOS and macOS
        do {
            try setUpAudioSession()
            print("DEPURAÇÃO [Gravador]: Configuração da sessão de áudio concluída")
            Log.audio.info("Audio session configured")
        } catch {
            print("DEPURAÇÃO [Gravador]: Erro ao configurar a sessão de áudio: \(error)")
            Log.audio.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Install route/config observers once per Recorder lifecycle
        installAudioObserversIfNeeded()
        #if os(macOS)
        await MainActor.run {
            AudioDeviceManager.startDefaultInputMonitoring()
            if audioDeviceObserverId == nil {
                audioDeviceObserverId = AudioDeviceManager.addDefaultInputObserver { [weak self] _ in
                    self?.scheduleReconfigure(reason: "default-input-change")
                }
            }
        }
        #endif

        do {
            try await transcriber.setUpTranscriber()
            print("DEPURAÇÃO [Gravador]: Configuração do transcritor concluída")
            Log.speech.info("Speech transcriber configured")
        } catch {
            print("DEPURAÇÃO [Gravador]: Erro ao configurar o transcritor: \(error)")
            Log.speech.error("Transcriber setup failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Cache analyzer's preferred input format for conversion (avoid accessing @MainActor type off-actor)
        self.preferredStreamFormat = await MainActor.run { (self.transcriber as? SpokenWordTranscriber)?.analyzerFormat }

        // Initialize diarization manager
        do {
            try await diarizationManager.initialize()
            print("DEPURAÇÃO [Gravador]: Gerenciador de diarização inicializado")
            Log.audio.info("Diarization manager initialized")
            // Load known speakers (custom names + embeddings) for consistent recognition
            await diarizationManager.loadKnownSpeakers(from: modelContext)
        } catch {
            print("DEPURAÇÃO [Gravador]: Falha na configuração da diarização: \(error)")
            Log.audio.error("Diarization init failed: \(error.localizedDescription, privacy: .public)")
            // Continue without diarization if it fails
        }

        print("DEPURAÇÃO [Gravador]: Sessão de áudio e transcritor configurados com sucesso")

        // Create audio stream and process it
        do {
            let audioStreamSequence = try await audioStream()

            // Reset session-level first-buffer state
            everReceivedAudio = false
            firstBufferMonitor?.cancel()
            // Increase timeout to 10 seconds to accommodate slower audio system initialization
            // and HAL issues, especially on macOS with external microphones
            firstBufferMonitor = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(10 * NSEC_PER_SEC))
                await self?.handleNoAudioDetected()
            }

            for await audioData in audioStreamSequence {
                // Process the buffer for transcription
                try await self.transcriber.streamAudioToTranscriber(audioData.buffer)

                // Also process for diarization
                await self.diarizationManager.processAudioBuffer(audioData.buffer)
            }
        } catch {
            print("DEPURAÇÃO [Gravador]: Falha ao transmitir o áudio: \(error)")
            Log.audio.error("Audio streaming failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func stopRecording(cause: StopCause = .user) async throws {
        print("DEPURAÇÃO [Gravador]: Encerrando sessão de gravação")
        Log.audio.info("Recording session stopping")
        Log.state.info("Recording stop requested, cause=\(cause.rawValue, privacy: .public)")

        try? await runOnAudioQueue { [weak self] in
            guard let self = self else { return }
            if self.recordingEngine.isRunning {
                self.recordingEngine.stop()
                print("DEPURAÇÃO [Gravador]: Motor de gravação interrompido")
                Log.audio.info("AVAudioEngine stopped")
            }
            self.recordingEngine.inputNode.removeTap(onBus: 0)
        }

        // Update memo completion status on main actor
        await MainActor.run { [memo] in
            memo.isDone = true
        }

        // Clean up continuation
        outputContinuation?.finish()
        outputContinuation = nil
        print("DEPURAÇÃO [Gravador]: Continuação do fluxo de áudio finalizada")
        NotificationCenter.default.post(name: Self.didStopWithCauseNotification, object: nil, userInfo: ["cause": cause.rawValue])

        // Reset observation flags after stopping
        hasReceivedAudio = false
        everReceivedAudio = false
        cancelFirstBufferMonitor()
        // Remove any listeners to avoid spurious reconfigs after stop
        removeAudioObservers()
        #if os(macOS)
        await MainActor.run {
            if let id = audioDeviceObserverId { AudioDeviceManager.removeDefaultInputObserver(id); audioDeviceObserverId = nil }
        }
        #endif

        do {
            try await transcriber.finishTranscribing()
            print("DEPURAÇÃO [Gravador]: Transcrição finalizada")
            Log.speech.info("Speech transcription finished")
        } catch {
            print("DEPURAÇÃO [Gravador]: Erro ao finalizar a transcrição: \(error)")
            Log.speech.error("Transcription finish failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Process final diarization
        await processFinalDiarization()

        print("DEPURAÇÃO [Gravador]: Gravação encerrada e transcrição finalizada")
    }

    func pauseRecording() {
        print("DEPURAÇÃO [Gravador]: Pausando gravação")
        recordingEngine.pause()
    }

    func resumeRecording() throws {
        print("DEPURAÇÃO [Gravador]: Retomando gravação")
        try recordingEngine.start()
    }

    #if os(iOS)
        func setUpAudioSession() throws {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
    #else
        // macOS audio session setup
        func setUpAudioSession() throws {
            print("DEPURAÇÃO [Gravador]: Configurando sessão de áudio no macOS")

            // Reset recording engine if needed
            if recordingEngine.isRunning {
                print("DEPURAÇÃO [Gravador]: Interrompendo motor de gravação para reiniciar")
                recordingEngine.stop()
            }
            recordingEngine.reset()

            // Smart microphone selection (mimic system unless user overrides in settings)
            MicrophoneSelector.applySelectionIfNeeded(AppSettings())
            // Cache/bind the current default input for this session and re-assert it on restarts
            if boundInputDevice == nil {
                boundInputDevice = AudioDeviceManager.currentDefaultInput()
            } else if let dev = boundInputDevice {
                AudioDeviceManager.setDefaultInput(dev.id)
            }

            // Request microphone access
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                print("DEPURAÇÃO [Gravador]: Acesso ao áudio já autorizado")
            case .notDetermined:
                print("DEPURAÇÃO [Gravador]: Acesso ao áudio não determinado; solicitando...")
            // This will be handled by the isAuthorized() check in record()
            case .denied, .restricted:
                print("DEPURAÇÃO [Gravador]: Acesso ao áudio negado ou restrito")
                throw TranscriptionError.failedToSetupRecognitionStream
            @unknown default:
                print("DEPURAÇÃO [Gravador]: Status de autorização de áudio desconhecido")
                throw TranscriptionError.failedToSetupRecognitionStream
            }
        }
    #endif

    private func audioStream() async throws -> AsyncStream<AudioData> {
        let stream = AsyncStream(AudioData.self, bufferingPolicy: .unbounded) { continuation in
            self.outputContinuation = continuation
        }

        try await runOnAudioQueue {
            try self.configureRecordingEngineLocked(resetFile: true)
        }

        return stream
    }

    private func configureRecordingEngineLocked(resetFile: Bool) throws {
        print("DEPURAÇÃO [Gravador]: Configurando motor de gravação")
        Log.audio.info("Configuring AVAudioEngine + input tap")

        if recordingEngine.isRunning {
            print("DEPURAÇÃO [Gravador]: Interrompendo motor de gravação existente")
            recordingEngine.stop()
        }

        recordingEngine.inputNode.removeTap(onBus: 0)
        recordingEngine.reset()

        let inputFormat = recordingEngine.inputNode.outputFormat(forBus: 0)
        print("DEPURAÇÃO [Gravador]: Formato de entrada: \(inputFormat)")

        // Validate and log detailed format information
        Log.audio.info("Input format details - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount), isInterleaved: \(inputFormat.isInterleaved)")
        if let channelLayout = inputFormat.channelLayout {
            Log.audio.info("Channel layout tag: \(channelLayout.layoutTag)")
        } else {
            Log.audio.warning("No channel layout available for input format")
        }

        // For stability with CoreAudio (esp. Bluetooth inputs and aggregate devices),
        // install the tap at the node's native format.
        let tapFormat = inputFormat

        // Prefer converting directly into the SpeechAnalyzer's preferred format to avoid
        // a second conversion inside the transcriber (which has been failing with -50).
        let desiredOutFormat: AVAudioFormat = {
            if let fmt = self.preferredStreamFormat { return fmt }
            // Fallback: 16 kHz mono Float32
            return AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        }()

        self.convertFormat16k = desiredOutFormat
        self.converterTo16k = AVAudioConverter(from: inputFormat, to: desiredOutFormat)
        self.converterTo16k?.primeMethod = .none

        if resetFile || audioFile == nil {
            // Always create the on-disk file at the tap's native format to avoid
            // mismatch if the analyzer-preferred conversion isn't available for some devices.
            let inputSettings = tapFormat.settings
            do {
                self.audioFile = try AVAudioFile(forWriting: url, settings: inputSettings)
                print("DEPURAÇÃO [Gravador]: Arquivo de áudio criado com sucesso em: \(url)")
                let recordingURL = url
                Task { @MainActor [memo] in memo.url = recordingURL }
            } catch {
                print("DEPURAÇÃO [Gravador]: Falha ao criar arquivo de áudio: \(error)")
                throw error
            }
        } else {
            // If the tap format changed (e.g., after a route change), optionally reopen a new segment file
            if let currentFile = audioFile {
                let f = currentFile.processingFormat
                let changed = (f.sampleRate != tapFormat.sampleRate) || (f.channelCount != tapFormat.channelCount) || (f.commonFormat != tapFormat.commonFormat)
                if changed {
                    fileSegmentIndex += 1
                    let base = url.deletingPathExtension()
                    let segURL = base.deletingLastPathComponent()
                        .appendingPathComponent(base.lastPathComponent + ".seg\(fileSegmentIndex)")
                        .appendingPathExtension("wav")
                    do {
                        self.audioFile = try AVAudioFile(forWriting: segURL, settings: tapFormat.settings)
                        Log.audio.notice("Opened new segment file due to format change: \(segURL.path, privacy: .public)")
                    } catch {
                        Log.audio.error("Failed to open segment file: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        // Reset per-reconfigure observation; retain session-level everReceivedAudio
        hasReceivedAudio = false

        if recordingEngine.inputNode.isVoiceProcessingEnabled {
            do {
                try recordingEngine.inputNode.setVoiceProcessingEnabled(false)
                print("DEPURAÇÃO [Gravador]: Voice processing desativado no input node")
            } catch {
                print("DEPURAÇÃO [Gravador]: Não foi possível desativar voice processing: \(error)")
            }
        }

        // Use a slightly larger buffer for Bluetooth inputs to reduce HAL overloads
        #if os(macOS)
        let currentInputName = AudioDeviceManager.currentDefaultInput()?.name.lowercased() ?? ""
        let isBluetoothInput = currentInputName.contains("airpods") || currentInputName.contains("bluetooth") || currentInputName.contains("hands-free")
        let chosenBufferSize: AVAudioFrameCount = isBluetoothInput ? 4096 : 2048
        #else
        let chosenBufferSize: AVAudioFrameCount = 2048
        #endif

        recordingEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: chosenBufferSize,
            format: tapFormat
        ) { [weak self] (buffer, time) in
            guard let self else { return }
            if !self.hasReceivedAudio {
                self.hasReceivedAudio = true
                self.everReceivedAudio = true
                // Reset the reinit attempts counter since we're getting audio successfully
                self.noAudioReinitAttempts = 0
                print("DEPURAÇÃO [Gravador]: Primeiro buffer recebido (\(buffer.frameLength) frames)")
                Log.audio.info("Primeiro buffer recebido")
                DispatchQueue.main.async { [weak self] in
                    self?.cancelFirstBufferMonitor()
                    NotificationCenter.default.post(name: Recorder.firstBufferNotification, object: nil)
                }
            }
            // Convert to 16k mono for ML and for on-disk writing when possible
            let outBuf = self.convertTo16kMono(buffer) ?? buffer
            if !self.loggedFirstTapDetails {
                self.loggedFirstTapDetails = true
                let inFmt = buffer.format
                let outFmt = outBuf.format
                print("[Recorder DEBUG]: Tap in fmt — sr=\(inFmt.sampleRate), ch=\(inFmt.channelCount), common=\(inFmt.commonFormat.rawValue), interleaved=\(inFmt.isInterleaved)")
                print("[Recorder DEBUG]: Tap out fmt — sr=\(outFmt.sampleRate), ch=\(outFmt.channelCount), common=\(outFmt.commonFormat.rawValue), interleaved=\(outFmt.isInterleaved)")
            }
            // Write the original input buffer to disk to match the file's native format.
            self.writeBufferToDisk(buffer: buffer)
            let audioData = AudioData(buffer: outBuf, time: time)
            self.outputContinuation?.yield(audioData)
        }

        recordingEngine.prepare()
        try recordingEngine.start()
        print("DEPURAÇÃO [Gravador]: Motor de gravação iniciado com sucesso")
        Log.audio.info("AVAudioEngine started")
        Log.audio.info("Motor de gravação iniciado")
        #if os(macOS)
        Log.audio.info("Tap buffer=\(chosenBufferSize, privacy: .public) isBT=\(isBluetoothInput ? "1" : "0", privacy: .public) input=\(currentInputName, privacy: .public)")
        #else
        Log.audio.info("Tap buffer=\(chosenBufferSize, privacy: .public)")
        #endif
    }

    private func writeBufferToDisk(buffer: AVAudioPCMBuffer) {
        do {
            try audioFile?.write(from: buffer)
        } catch {
            print("DEPURAÇÃO [Gravador]: Erro ao gravar arquivo: \(error)")
        }
    }

    private func convertTo16kMono(_ inBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let targetFormat = convertFormat16k else { return nil }
        // Rebuild converter if input/output formats changed mid-stream (e.g., route change)
        if converterTo16k == nil || converterTo16k?.inputFormat != inBuffer.format || converterTo16k?.outputFormat != targetFormat {
            self.converterTo16k = AVAudioConverter(from: inBuffer.format, to: targetFormat)
            self.converterTo16k?.primeMethod = .none
            let src = inBuffer.format
            let dst = targetFormat
            Log.audio.notice("Rebuilt converter (src sr=\(src.sampleRate, privacy: .public) ch=\(src.channelCount, privacy: .public) → dst sr=\(dst.sampleRate, privacy: .public) ch=\(dst.channelCount, privacy: .public))")
        }
        guard let converter = converterTo16k else { return nil }
        let ratio = targetFormat.sampleRate / inBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        // Use unmanaged flag to avoid concurrency warnings
        let flag = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        flag.initialize(to: 0)
        defer { flag.deinitialize(count: 1); flag.deallocate() }
        var error: NSError?
        // Reset the converter between independent buffers to avoid lingering endOfStream state
        converter.reset()
        let status = converter.convert(to: out, error: &error) { _, statusPtr in
            if flag.pointee == 0 {
                flag.pointee = 1
                statusPtr.pointee = .haveData
                return inBuffer
            }
            statusPtr.pointee = .endOfStream
            return nil
        }
        if status == .error {
            Log.audio.error("AVAudioConverter.convert() error (src sr=\(inBuffer.format.sampleRate, privacy: .public) ch=\(inBuffer.format.channelCount, privacy: .public))")
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastConverterErrorTs < 1.0 { converterErrorCount += 1 } else { converterErrorCount = 1 }
            lastConverterErrorTs = now
            if converterErrorCount >= 3 {
                converterErrorCount = 0
                scheduleReconfigure(reason: "converter-error")
            }
            return nil
        }
        return out
    }

    private func cancelFirstBufferMonitor() {
        firstBufferMonitor?.cancel()
        firstBufferMonitor = nil
    }

    private func handleNoAudioDetected() async {
        // Only treat as no-audio if we have not seen any audio at all in this session
        guard !everReceivedAudio, outputContinuation != nil else { return }
        cancelFirstBufferMonitor()
        #if os(macOS)
            let currentDevice = AudioDeviceManager.currentDefaultInput()?.name ?? "<desconhecido>"
        #else
            let currentDevice = "<iOS>"
        #endif
        print("DEPURAÇÃO [Gravador]: Nenhum áudio detectado após o timeout; reinicializando engine de captura (dispositivo=\(currentDevice))")
        Log.audio.warning("No audio detected; attempting engine reinit (device=\(currentDevice, privacy: .public))")
        Log.audio.warning("Nenhum áudio detectado (dispositivo=\(currentDevice, privacy: .public))")

        do {
            #if os(macOS)
            // Re-assert the bound device before reconfiguring
            if let dev = boundInputDevice { AudioDeviceManager.setDefaultInput(dev.id) }
            #endif
            try await runOnAudioQueue {
                try self.configureRecordingEngineLocked(resetFile: false)
            }

            if !self.everReceivedAudio {
                self.noAudioReinitAttempts += 1
                // Increase attempt threshold to 4 attempts with longer delays between them
                if self.noAudioReinitAttempts >= 4 {
                    // Consider this a silence timeout; end stream cleanly
                    Log.state.info("Stopping due to silence timeout after \(self.noAudioReinitAttempts) attempts")
                    try? await stopRecording(cause: .silenceTimeout)
                } else {
                    // After reconfigure, allow progressively longer delays for audio initialization
                    let delay: UInt64 = UInt64(min(12, 6 + (self.noAudioReinitAttempts * 2))) // 8s, 10s, 12s
                    self.firstBufferMonitor = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: delay * NSEC_PER_SEC)
                        await self?.handleNoAudioDetected()
                    }
                }
            }
        } catch {
            print("DEPURAÇÃO [Gravador]: Falha ao reinicializar engine após ausência de áudio: \(error)")
            Log.audio.error("Engine reinit failed after no-audio: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Route / Config Observers
    private func installAudioObserversIfNeeded() {
        guard observers.isEmpty else { return }
        #if os(iOS)
        let routeObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            let reasonRaw = (notif.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.intValue ?? -1
            let sess = AVAudioSession.sharedInstance()
            let current = sess.currentRoute.inputs.first?.portName ?? "<unknown>"
            Log.audio.notice("Route change (reason=\(reasonRaw, privacy: .public), input=\(current, privacy: .public)); scheduling reconfig")
            self.scheduleReconfigure(reason: "route-change")
        }
        observers.append(routeObs)
        #endif
        let cfgObs = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: recordingEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Log.audio.notice("AVAudioEngineConfigurationChange received; scheduling reconfig")
            self.scheduleReconfigure(reason: "engine-config-change")
        }
        observers.append(cfgObs)

        // Terminal backpressure observer - stop recording gracefully when system is overwhelmed
        let backpressureObs = NotificationCenter.default.addObserver(
            forName: Notification.Name("DiarizationManagerTerminalBackpressure"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let drops = (notification.userInfo?["consecutiveDrops"] as? Int) ?? 0
            let liveSec = (notification.userInfo?["liveSeconds"] as? Double) ?? 0
            Log.audio.error("Terminal backpressure detected (\(drops) consecutive drops, \(liveSec, format: .fixed(precision: 2))s buffer) - stopping recording gracefully")
            // Stop recording asynchronously to avoid blocking main thread
            Task.detached { [weak self] in
                guard let self else { return }
                try? await self.stopRecording(cause: .pipelineBackpressure)
            }
        }
        observers.append(backpressureObs)
    }

    private func removeAudioObservers() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    private func scheduleReconfigure(reason: String) {
        // Avoid reconfiguring if we already stopped or have no active continuation
        guard outputContinuation != nil else { return }
        if isReconfiguring { return }
        isReconfiguring = true
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isReconfiguring = false }
            do {
                self.recordingEngine.inputNode.removeTap(onBus: 0)
                try self.configureRecordingEngineLocked(resetFile: false)
                Log.audio.info("Reconfigured capture after \(reason, privacy: .public)")
                // If we have not yet seen audio for this session, restart the first-buffer monitor window
                // with extended timeout to handle HAL delays
                if !self.everReceivedAudio {
                    self.cancelFirstBufferMonitor()
                    self.firstBufferMonitor = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(8 * NSEC_PER_SEC))
                        await self?.handleNoAudioDetected()
                    }
                }
            } catch {
                Log.audio.error("Reconfigure after \(reason, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func playRecording() async {
        guard let audioFile = audioFile else {
            return
        }

        // Stop any existing playback
        await stopPlaying()

        try? await runOnAudioQueue { [weak self] in
            guard let self = self else { return }

            // Setup playback engine
            let playerNode = AVAudioPlayerNode()
            self.playerNode = playerNode

            self.playbackEngine.attach(playerNode)
            self.playbackEngine.connect(
                playerNode,
                to: self.playbackEngine.outputNode,
                format: audioFile.processingFormat
            )

            playerNode.scheduleFile(
                audioFile,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { _ in
                // Playback completed
            }

            do {
                try self.playbackEngine.start()
                playerNode.play()
            } catch {
                print("[Recorder]: Error starting playback engine: \(error.localizedDescription)")
            }
        }
    }

    func recordingDuration() -> TimeInterval {
        if let file = audioFile {
            return Double(file.length) / file.processingFormat.sampleRate
        }
        return 0
    }

    func seek(to time: TimeInterval, play: Bool) async {
        try? await runOnAudioQueue { [weak self] in
            guard let self = self, let file = self.audioFile else { return }

            let sampleRate = file.processingFormat.sampleRate
            let startFrame = max(0, AVAudioFramePosition(time * sampleRate))
            let remaining = max(0, file.length - startFrame)
            let frames = AVAudioFrameCount(remaining)

            // Stop any current playback and detach/reattach a fresh node for safety
            self.playerNode?.stop()
            if let node = self.playerNode {
                self.playbackEngine.detach(node)
                self.playerNode = nil
            }

            let node = AVAudioPlayerNode()
            self.playerNode = node
            self.playbackEngine.attach(node)
            self.playbackEngine.connect(node, to: self.playbackEngine.outputNode, format: file.processingFormat)

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil, completionCallbackType: .dataPlayedBack) { _ in }

            if !self.playbackEngine.isRunning {
                do { try self.playbackEngine.start() } catch { print("[Recorder]: Engine start on seek failed: \(error)") }
            }
            if play { node.play() }
        }
    }

    func stopPlaying() async {
        try? await runOnAudioQueue { [weak self] in
            guard let self = self else { return }

            // Stop the player node
            self.playerNode?.stop()

            // Stop the playback engine
            if self.playbackEngine.isRunning {
                self.playbackEngine.stop()
            }

            // Clean up the player node
            if let playerNode = self.playerNode {
                self.playbackEngine.detach(playerNode)
                self.playerNode = nil
            }
        }
    }
    
    // MARK: - Diarization Processing
    
    private func processFinalDiarization() async {
        print("DEPURAÇÃO [Gravador]: Processando diarização final...")
        
        guard let diarizationResult = await diarizationManager.finishProcessing() else {
            print("DEPURAÇÃO [Gravador]: Nenhum resultado de diarização disponível")
            return
        }
        
        print(
            "DEPURAÇÃO [Gravador]: Diarização concluída com \(diarizationResult.segments.count) segmentos e \(diarizationResult.segments.count) falantes"
        )
        
        await applyDiarizationResult(diarizationResult)
    }

    @MainActor
    private func applyDiarizationResult(_ result: DiarizationResult) {
        memo.updateWithDiarizationResult(result, in: modelContext)

        if !result.segments.isEmpty {
            alignTranscriptionWithSpeakers(result)
        }
    }

    @MainActor
    private func alignTranscriptionWithSpeakers(_ diarizationResult: DiarizationResult) {
        print("DEPURAÇÃO [Gravador]: Alinhando transcrição com segmentos de falantes (preciso)...")

        // Build fast lookup for diarization segments
        let diarSegs = diarizationResult.segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }

        // Prepare a mapping from (speakerId,start,end) to SpeakerSegment
        // We'll select by matching speakerId and nearest start time.
        func findSpeakerSegment(for seg: TimedSpeakerSegment) -> SpeakerSegment? {
            let targetStart = TimeInterval(seg.startTimeSeconds)
            return memo.speakerSegments.min(by: { a, b in
                let da = abs(a.startTime - targetStart)
                let db = abs(b.startTime - targetStart)
                if abs(da - db) < 0.01 { return a.speakerId < b.speakerId }
                return da < db
            }).flatMap { candidate in
                candidate.speakerId == seg.speakerId ? candidate : memo.speakerSegments.first(where: { $0.speakerId == seg.speakerId && abs($0.startTime - targetStart) < 0.2 })
            }
        }

        // Clear any previous text on segments before precise alignment
        for s in memo.speakerSegments { s.text = "" }

        // Iterate through attributed runs that carry audio time
        let attributed = memo.text
        attributed.runs.forEach { run in
            guard let tr = attributed[run.range].audioTimeRange else { return }
            let startSec = tr.start.seconds
            let endSec = tr.end.seconds
            guard startSec.isFinite, endSec.isFinite else { return }
            let mid = (startSec + endSec) * 0.5

            // Find diarization segment that covers the mid time
            if let seg = diarSegs.first(where: { mid >= Double($0.startTimeSeconds) && mid < Double($0.endTimeSeconds) }),
               let target = findSpeakerSegment(for: seg) {
                // Append this run's text to the speaker segment
                let snippet = String(attributed[run.range].characters)
                if target.text.isEmpty {
                    target.text = snippet
                } else {
                    // Preserve spacing across runs
                    let glue = snippet.hasPrefix(" ") || target.text.hasSuffix(" ") ? "" : " "
                    target.text.append(glue + snippet)
                }
            }
        }

        print("DEPURAÇÃO [Gravador]: Alinhamento preciso concluído")
    }
}

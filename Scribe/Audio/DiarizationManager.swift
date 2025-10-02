import Foundation
@preconcurrency import AVFoundation
import CoreML
import SwiftData
import os

protocol DiarizerManaging: AnyObject {
    func initialize(models: DiarizerModels)
    func performCompleteDiarization(_ samples: [Float], sampleRate: Int) throws -> DiarizationResult
    func validateAudio(_ audio: [Float]) -> AudioValidationResult
    // Insert or update a speaker in the in-memory database (ID + embedding + duration)
    func upsertRuntimeSpeaker(id: String, embedding: [Float], duration: Float)
}

extension DiarizerManager: DiarizerManaging {
    func performCompleteDiarization(_ samples: [Float], sampleRate: Int) throws -> DiarizationResult {
        let contiguous = ContiguousArray(samples)
        return try performCompleteDiarization(contiguous, sampleRate: sampleRate)
    }

    func validateAudio(_ audio: [Float]) -> AudioValidationResult {
        let contiguous = ContiguousArray(audio)
        return validateAudio(contiguous)
    }

    func upsertRuntimeSpeaker(id: String, embedding: [Float], duration: Float) {
        // Name is not required for runtime assignment; UI uses SwiftData names
        speakerManager.upsertSpeaker(
            id: id,
            currentEmbedding: embedding,
            duration: duration,
            rawEmbeddings: [],
            updateCount: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// Notification names (nonisolated for cross-actor access)
extension DiarizationManager {
    static let backpressureNotification = Notification.Name("DiarizationManagerBackpressureDrop")
    static let terminalBackpressureNotification = Notification.Name("DiarizationManagerTerminalBackpressure")
    static let resultNotification = Notification.Name("DiarizationManagerDidProduceResult")
}

@MainActor
@Observable
final class DiarizationManager {
    private let log = Logger(subsystem: "com.swift.examples.scribe", category: "Diarization")
    private var fluidDiarizer: (any DiarizerManaging)?
    private var isInitialized = false
    private var audioBuffer: [Float] = []
    private var fullAudio: [Float] = []
    private let sampleRate: Float = 16000.0
    // Live processing window size to reduce perceived latency
    var processingWindowSeconds: Double = 10.0  // Optimal per FluidAudio docs
    var adaptiveWindowEnabled: Bool = true
    private let minWindow: Double = 1.0
    private let maxWindow: Double = 6.0
    // Adaptive live pause/resume controls
    var adaptiveRealtimeEnabled: Bool = true
    var showBackpressureAlerts: Bool = true
    private var cooldownUntil: Date? = nil
    private var pausedByAdaptiveControl: Bool = false

    // Backpressure safeguards for streaming windows (does not affect final pass)
    var backpressureEnabled: Bool = true
    var maxLiveBufferSeconds: Double = 15.0  // Increased for 10s windows
    private var consecutiveDrops: Int = 0
    private var lastBackpressureNoticeAt: Date? = nil

    private let diarizerFactory: (DiarizerConfig) -> any DiarizerManaging
    private let modelLoader: () async throws -> DiarizerModels
    private var knownSpeakersLoaded = false
    
    // Configuration
    var config: DiarizerConfig = DiarizerConfig()
    var isEnabled: Bool = true
    var enableRealTimeProcessing: Bool = false

    // ANE memory optimizer for enhanced performance
    private let memoryOptimizer = ANEMemoryOptimizer()

    // Performance tracking structure
    private struct ConversionMetrics {
        var totalConversions: Int = 0
        var totalTimeMs: Double = 0
        var aneSuccesses: Int = 0
        var aneFallbacks: Int = 0
        var fastPathHits: Int = 0

        var averageTimeMs: Double {
            totalConversions > 0 ? totalTimeMs / Double(totalConversions) : 0
        }

        var aneSuccessRate: Double {
            let aneAttempts = aneSuccesses + aneFallbacks
            return aneAttempts > 0 ? Double(aneSuccesses) / Double(aneAttempts) * 100 : 0
        }

        mutating func reset() {
            self = ConversionMetrics()
        }

        func summary() -> String {
            """
            [ANE Metrics] Conversions: \(totalConversions), Avg: \(String(format: "%.2f", averageTimeMs))ms, \
            FastPath: \(fastPathHits), ANE Success: \(String(format: "%.1f", aneSuccessRate))%, \
            Fallbacks: \(aneFallbacks)
            """
        }
    }

    private var conversionMetrics = ConversionMetrics()

    // State
    var isProcessing = false
    var lastError: (any Error)?
    var processingProgress: Double = 0.0
    
    // Results
    private(set) var lastResult: DiarizationResult?

    // Small helper to offload CPU-bound work onto a background queue
    private func runOffMain<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try work()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
    
    init(
        config: DiarizerConfig = DiarizerConfig(),
        isEnabled: Bool = true,
        enableRealTimeProcessing: Bool = false,
        diarizerFactory: @escaping (DiarizerConfig) -> any DiarizerManaging = { DiarizerManager(config: $0) },
        modelLoader: @escaping () async throws -> DiarizerModels = { try await DiarizationManager.resolveDiarizerModels() }
    ) {
        self.config = config
        self.isEnabled = isEnabled
        self.enableRealTimeProcessing = enableRealTimeProcessing
        self.diarizerFactory = diarizerFactory
        self.modelLoader = modelLoader
    }

    convenience init(
        config: DiarizerConfig = DiarizerConfig(),
        isEnabled: Bool = true,
        enableRealTimeProcessing: Bool = false,
        diarizer: any DiarizerManaging
    ) {
        self.init(
            config: config,
            isEnabled: isEnabled,
            enableRealTimeProcessing: enableRealTimeProcessing,
            diarizerFactory: { _ in diarizer },
            modelLoader: { throw DiarizationError.configurationError("Uso de modelos não suportado em testes") }
        )
        self.fluidDiarizer = diarizer
        self.isInitialized = true
    }
    
    // MARK: - Initialization
    
    func initialize() async throws {
        print("[GerenciadorDiarizacao] Inicializando diarizador do FluidAudio...")

        guard isEnabled else {
            print("[GerenciadorDiarizacao] A diarização está desativada nas configurações")
            return
        }

        do {
            // Create FluidAudio diarizer with custom config
            let fluidConfig = createFluidAudioConfig()
            let diarizer = diarizerFactory(fluidConfig)

            // Initialize the diarizer with local models when available, or fall back to downloads
            let models = try await self.modelLoader()
            try await runOffMain { diarizer.initialize(models: models) }

            fluidDiarizer = diarizer
            isInitialized = true
            print("[GerenciadorDiarizacao] Diarizador do FluidAudio inicializado com sucesso")
        } catch {
            print("[GerenciadorDiarizacao] Falha ao inicializar o diarizador: \(error)")
            lastError = error
            throw error
        }
    }

    private func createFluidAudioConfig() -> DiarizerConfig {
        return config
    }

    private static func resolveDiarizerModels() async throws -> DiarizerModels {
        let fileManager = FileManager.default

        var candidateDirectories: [URL] = []
        if let override = ProcessInfo.processInfo.environment["FLUID_AUDIO_MODELS_PATH"], !override.isEmpty {
            candidateDirectories.append(URL(fileURLWithPath: override, isDirectory: true))
        }

        // App bundle resource folder (if packaged)
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("speaker-diarization-coreml", isDirectory: true) {
            candidateDirectories.append(bundleURL)
        }

        // Developer-local model cache inside the repository checkout
        candidateDirectories.append(
            URL(fileURLWithPath: "/Users/leandroalmeida/swift-scribe/speaker-diarization-coreml", isDirectory: true)
        )

        // Legacy external drive location retained as a fallback for existing setups
        candidateDirectories.append(
            URL(fileURLWithPath: "/Volumes/Untitled/FluidAudio/speaker-diarization-coreml", isDirectory: true)
        )

        for basePath in candidateDirectories {
            let segmentationURL = basePath.appendingPathComponent("pyannote_segmentation.mlmodelc", isDirectory: true)
            let embeddingURL = basePath.appendingPathComponent("wespeaker_v2.mlmodelc", isDirectory: true)

            var isSegmentationDir: ObjCBool = false
            var isEmbeddingDir: ObjCBool = false
            let hasSegmentation = fileManager.fileExists(
                atPath: segmentationURL.path,
                isDirectory: &isSegmentationDir
            ) && isSegmentationDir.boolValue
            let hasEmbedding = fileManager.fileExists(
                atPath: embeddingURL.path,
                isDirectory: &isEmbeddingDir
            ) && isEmbeddingDir.boolValue

            if hasSegmentation && hasEmbedding {
                print("[GerenciadorDiarizacao] Carregando modelos de diarização do caminho local em \(basePath.path)")
                do {
                    return try await DiarizerModels.load(
                        localSegmentationModel: segmentationURL,
                        localEmbeddingModel: embeddingURL
                    )
                } catch {
                    print(
                        "[GerenciadorDiarizacao] Falha ao carregar modelos em \(basePath.path). Tentando próximo candidato ou download remoto. Erro: \(error)"
                    )
                }
            }
        }

        // Enforce offline, bundled models per project requirements
        throw DiarizationError.configurationError("Modelos locais não encontrados. Verifique o bundle do app ou a variável FLUID_AUDIO_MODELS_PATH.")
    }

    // MARK: - Audio Processing
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isEnabled, isInitialized else { return }
        // If we paused real-time processing due to load, check cooldown
        if adaptiveRealtimeEnabled, pausedByAdaptiveControl, let until = cooldownUntil, Date() >= until {
            enableRealTimeProcessing = true
            pausedByAdaptiveControl = false
            cooldownUntil = nil
            // Nudge window slightly larger to reduce immediate re-overload
            if processingWindowSeconds < maxWindow { processingWindowSeconds = min(maxWindow, processingWindowSeconds + 0.5) }
            log.notice("Resuming real-time diarization after cooldown; window=\(self.processingWindowSeconds, format: .fixed(precision: 2))s")
        }
        
        // Convert audio buffer to Float array at 16kHz mono (high-quality resample)
        guard let floatSamples = convertTo16kMonoFloat(buffer) else {
            print("[GerenciadorDiarizacao] Falha ao converter o buffer de áudio")
            return
        }
        
        // Accumulate audio for batch processing with backpressure
        audioBuffer.append(contentsOf: floatSamples)

        if backpressureEnabled {
            let cap = Int(self.sampleRate * Float(self.maxLiveBufferSeconds))
            if self.audioBuffer.count > cap {
                let overflow = self.audioBuffer.count - cap
                // Drop oldest samples to keep latency bounded
                self.audioBuffer.removeFirst(overflow)
                self.consecutiveDrops += 1
                let liveSec = Double(self.audioBuffer.count)/Double(self.sampleRate)
                log.warning("Backpressure drop: \(overflow) samples (~\(Double(overflow)/Double(self.sampleRate), format: .fixed(precision: 2)) s), liveBuffer=\(liveSec, format: .fixed(precision: 2)) s, consecutive=\(self.consecutiveDrops)")

                // Detect terminal backpressure - system critically overwhelmed
                if self.consecutiveDrops >= 50 {
                    log.error("⚠️ TERMINAL BACKPRESSURE: \(self.consecutiveDrops) consecutive drops - audio system overwhelmed")
                    NotificationCenter.default.post(
                        name: Self.terminalBackpressureNotification,
                        object: self,
                        userInfo: ["consecutiveDrops": self.consecutiveDrops, "liveSeconds": liveSec]
                    )
                }

                // Maybe pause live processing adaptively
                if adaptiveRealtimeEnabled, enableRealTimeProcessing, (self.consecutiveDrops >= 3 || liveSec > (2.0 * self.processingWindowSeconds)) {
                    enableRealTimeProcessing = false
                    pausedByAdaptiveControl = true
                    cooldownUntil = Date().addingTimeInterval(15)
                    log.notice("Pausing real-time diarization due to sustained backpressure; cooldown 15s")
                }
                // Throttle UI notifications to avoid blinking banners
                if showBackpressureAlerts {
                    let now = Date()
                    if self.consecutiveDrops >= 3 {
                        if self.lastBackpressureNoticeAt == nil || now.timeIntervalSince(self.lastBackpressureNoticeAt!) > 10 {
                            self.lastBackpressureNoticeAt = now
                            NotificationCenter.default.post(
                                name: Self.backpressureNotification,
                                object: self,
                                userInfo: [
                                    "dropped": overflow,
                                    "liveSeconds": liveSec,
                                    "consecutive": self.consecutiveDrops
                                ]
                            )
                        }
                    }
                }
            } else {
                self.consecutiveDrops = 0
            }
        }
        fullAudio.append(contentsOf: floatSamples)
        
        // Process in real-time if enabled and we have enough audio
        if enableRealTimeProcessing,
           !isProcessing,
           audioBuffer.count >= Int(sampleRate * Float(processingWindowSeconds)) {
            _ = await processAccumulatedAudio()
        }
    }
    
    func finishProcessing() async -> DiarizationResult? {
        guard isEnabled, isInitialized else { return nil }
        // If we still have a pending window and real-time processing is enabled, process it first
        if enableRealTimeProcessing, !audioBuffer.isEmpty {
            _ = await processAccumulatedAudio()
        } else {
            // Discard partial window when not streaming live
            audioBuffer.removeAll()
        }
        // Produce a full-recording diarization to ensure comprehensive attribution
        guard !self.fullAudio.isEmpty, let diarizer = self.fluidDiarizer else { return nil }
        do {
            let start = Date()
            let samples = self.fullAudio
            let srate = Int(self.sampleRate)
            let allResult = try await runOffMain {
                try diarizer.performCompleteDiarization(samples, sampleRate: srate)
            }
            let dt = Date().timeIntervalSince(start)
            let uniqueSpeakerCount = Set(allResult.segments.map { $0.speakerId }).count
            print("[GerenciadorDiarizacao] Diarização FINAL concluída em \(dt)s — segmentos: \(allResult.segments.count), falantes: \(uniqueSpeakerCount)")
            lastResult = allResult
            // Clear accumulated audio once a final pass has completed
            self.fullAudio.removeAll()
            return allResult
        } catch {
            print("[GerenciadorDiarizacao] A diarização final falhou: \(error)")
            return nil
        }
    }
    
    private func processAccumulatedAudio() async -> DiarizationResult? {
        guard let diarizer = self.fluidDiarizer, !self.audioBuffer.isEmpty else {
            return nil
        }
        
        self.isProcessing = true
        self.processingProgress = 0.0
        
        do {
            print("[GerenciadorDiarizacao] Processando \(self.audioBuffer.count) amostras de áudio...")
            let startTime = Date()
            // Perform diarization using FluidAudio (off-main)
            let samples = self.audioBuffer
            let srate = Int(self.sampleRate)
            let fluidResult = try await runOffMain {
                try diarizer.performCompleteDiarization(samples, sampleRate: srate)
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            let uniqueSpeakerCount = Set(fluidResult.segments.map { $0.speakerId }).count
            print("[GerenciadorDiarizacao] Diarização concluída em \(processingTime)s — segmentos: \(fluidResult.segments.count), falantes: \(uniqueSpeakerCount)")
            log.info("Live diarization window=\(self.processingWindowSeconds, format: .fixed(precision: 2))s, time=\(processingTime, format: .fixed(precision: 2))s")

            // Adaptive window sizing: aim to keep processing within ~60% of window duration
            if self.adaptiveWindowEnabled {
                let ratio = processingTime / self.processingWindowSeconds
                // If it takes too long relative to the window, increase window (lower update rate, reduce load)
                if ratio > 0.8, self.processingWindowSeconds < self.maxWindow {
                    self.processingWindowSeconds = min(self.maxWindow, self.processingWindowSeconds + 0.5)
                    log.notice("Adaptive window increase → \(self.processingWindowSeconds, format: .fixed(precision: 2))s (ratio=\(ratio, format: .fixed(precision: 2)))")
                } else if ratio < 0.3, self.processingWindowSeconds > self.minWindow {
                    // Plenty of headroom: shrink the window to be more responsive
                    self.processingWindowSeconds = max(self.minWindow, self.processingWindowSeconds - 0.5)
                    log.notice("Adaptive window decrease → \(self.processingWindowSeconds, format: .fixed(precision: 2))s (ratio=\(ratio, format: .fixed(precision: 2)))")
                }
            }
            
            // Use FluidAudio result directly
            lastResult = fluidResult
            self.processingProgress = 1.0
            self.isProcessing = false
            
            // Publish incremental results for live UI updates
            NotificationCenter.default.post(
                name: Self.resultNotification,
                object: self,
                userInfo: ["result": fluidResult]
            )
            
            // Clear only the live window buffer after processing; keep fullAudio for final pass
            self.audioBuffer.removeAll()
            
            return fluidResult
            
        } catch {
            print("[GerenciadorDiarizacao] A diarização falhou: \(error)")
            self.lastError = error
            self.isProcessing = false
            return nil
        }
    }

    // MARK: - Speaker Comparison

    // MARK: - Known Speakers Loading / Enrollment / Similarity

    /// Loads known speakers from SwiftData into FluidAudio's in-memory SpeakerManager.
    /// Call after initialize() and before processing audio.
    func loadKnownSpeakers(from context: ModelContext) async {
        guard let diarizer = fluidDiarizer, isInitialized, !knownSpeakersLoaded else { return }

        // Fetch all persisted speakers with valid embeddings
        let descriptor = FetchDescriptor<Speaker>()
        let persisted: [Speaker] = (try? context.fetch(descriptor)) ?? []
        let candidates = persisted.compactMap { s -> (id: String, embedding: [Float], duration: Float)? in
            guard let emb = s.embedding, !emb.isEmpty else { return nil }
            // Validate embedding quality via FluidAudio utilities
            if !SpeakerUtilities.validateEmbedding(emb) { return nil }
            return (id: s.id, embedding: emb, duration: 0)
        }

        if !candidates.isEmpty {
            for item in candidates {
                diarizer.upsertRuntimeSpeaker(id: item.id, embedding: item.embedding, duration: item.duration)
            }
            knownSpeakersLoaded = true
            print("[GerenciadorDiarizacao] Carregados \(candidates.count) falantes conhecidos no SpeakerManager")
        } else {
            print("[GerenciadorDiarizacao] Nenhum falante conhecido com embedding válido encontrado para carregar")
        }
    }

    /// Enroll a new speaker from raw audio samples and persist with a custom name.
    /// Returns the created SwiftData Speaker on success.
    func enrollSpeaker(from samples: [Float], name: String, in context: ModelContext) async throws -> Speaker {
        guard isInitialized, let diarizer = fluidDiarizer else {
            throw SpeakerEnrollmentError.diarizerNotReady
        }

        // Basic audio validation
        let validation = diarizer.validateAudio(samples)
        guard validation.isValid else {
            throw SpeakerEnrollmentError.invalidAudio(validation.issues.joined(separator: "; "))
        }

        // Run diarization and extract best embedding
        let result = try diarizer.performCompleteDiarization(samples, sampleRate: Int(sampleRate))
        guard let best = bestSegment(for: result) else {
            throw SpeakerEnrollmentError.noSpeechDetected
        }

        let embedding = best.embedding
        guard SpeakerUtilities.validateEmbedding(embedding) else {
            throw SpeakerEnrollmentError.invalidEmbedding
        }

        // Create app Speaker with deterministic ID and chosen color
        let newId = UUID().uuidString
        let speakerCount = (try? context.fetch(FetchDescriptor<Speaker>()).count) ?? 0
        let color = Speaker.generateSpeakerColor(for: speakerCount)
        let appSpeaker = Speaker(id: newId, name: name, displayColor: color, embedding: embedding)
        context.insert(appSpeaker)

        // Reflect in FluidAudio SpeakerManager for live recognition
        diarizer.upsertRuntimeSpeaker(id: newId, embedding: embedding, duration: Float(best.durationSeconds))

        return appSpeaker
    }

    /// Enroll a new speaker from multiple clips by averaging embeddings across clips.
    /// Each clip is diarized independently; the best segment embedding from each is averaged.
    func enrollSpeaker(fromClips clips: [[Float]], name: String, in context: ModelContext) async throws -> Speaker {
        guard isInitialized, let diarizer = fluidDiarizer else {
            throw SpeakerEnrollmentError.diarizerNotReady
        }

        var embeddings: [[Float]] = []
        embeddings.reserveCapacity(clips.count)

        for clip in clips where !clip.isEmpty {
            let validation = diarizer.validateAudio(clip)
            guard validation.isValid else { continue }
            let result = try diarizer.performCompleteDiarization(clip, sampleRate: Int(sampleRate))
            if let best = bestSegment(for: result), SpeakerUtilities.validateEmbedding(best.embedding) {
                embeddings.append(best.embedding)
            }
        }

        guard let averaged = SpeakerUtilities.averageEmbeddings(embeddings), SpeakerUtilities.validateEmbedding(averaged) else {
            throw SpeakerEnrollmentError.invalidEmbedding
        }

        let newId = UUID().uuidString
        let speakerCount = (try? context.fetch(FetchDescriptor<Speaker>()).count) ?? 0
        let color = Speaker.generateSpeakerColor(for: speakerCount)
        let appSpeaker = Speaker(id: newId, name: name, displayColor: color, embedding: averaged)
        context.insert(appSpeaker)

        diarizer.upsertRuntimeSpeaker(id: newId, embedding: averaged, duration: 0)

        return appSpeaker
    }

    /// Compute similarity (as 1 - cosine distance) between provided audio and a stored speaker.
    /// Returns a confidence score in [0, 1], or throws if invalid.
    func similarity(of samples: [Float], to speaker: Speaker) async throws -> Float {
        guard isInitialized, let diarizer = fluidDiarizer else {
            throw SpeakerEnrollmentError.diarizerNotReady
        }
        guard let targetEmbedding = speaker.embedding, SpeakerUtilities.validateEmbedding(targetEmbedding) else {
            throw SpeakerEnrollmentError.missingTargetEmbedding
        }

        // Validate and extract embedding from samples
        let validation = diarizer.validateAudio(samples)
        guard validation.isValid else {
            throw SpeakerEnrollmentError.invalidAudio(validation.issues.joined(separator: "; "))
        }

        let result = try diarizer.performCompleteDiarization(samples, sampleRate: Int(sampleRate))
        guard let best = bestSegment(for: result) else {
            throw SpeakerEnrollmentError.noSpeechDetected
        }

        let distance = SpeakerUtilities.cosineDistance(best.embedding, targetEmbedding)
        if !distance.isFinite { throw SpeakerEnrollmentError.invalidEmbedding }
        let confidence = max(0, min(1, 1 - distance))
        return confidence
    }

    /// Rename a known speaker across persistence and FluidAudio runtime database.
    func renameSpeaker(id: String, to newName: String, in context: ModelContext) async throws {
        // Update SwiftData
        let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.name = newName
        } else {
            throw SpeakerEnrollmentError.speakerNotFound(id)
        }

        // Update runtime diarizer (re-initialize that single speaker)
        guard let diarizer = fluidDiarizer else { return }
        if let emb = try context.fetch(descriptor).first?.embedding, SpeakerUtilities.validateEmbedding(emb) {
            diarizer.upsertRuntimeSpeaker(id: id, embedding: emb, duration: 0)
        }
    }

    private func bestSegment(for result: DiarizationResult) -> TimedSpeakerSegment? {
        // Prefer longest, then highest quality
        return result.segments.max { a, b in
            if a.durationSeconds == b.durationSeconds {
                return a.qualityScore < b.qualityScore
            }
            return a.durationSeconds < b.durationSeconds
        }
    }

    func extractBestEmbedding(from samples: [Float]) throws -> [Float]? {
        guard isInitialized, let diarizer = fluidDiarizer else { return nil }
        let result = try diarizer.performCompleteDiarization(samples, sampleRate: Int(sampleRate))
        return bestSegment(for: result)?.embedding
    }

    /// Enhance an existing speaker by fusing new clips with the current embedding.
    /// Averages the current embedding with all valid embeddings extracted from clips.
    func enhanceSpeaker(id: String, withClips clips: [[Float]], in context: ModelContext) async throws -> Speaker {
        guard isInitialized else { throw SpeakerEnrollmentError.diarizerNotReady }
        let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == id })
        guard let existing = try context.fetch(descriptor).first else {
            throw SpeakerEnrollmentError.speakerNotFound(id)
        }

        var newEmbeddings: [[Float]] = []
        for clip in clips where !clip.isEmpty {
            if let emb = try extractBestEmbedding(from: clip), SpeakerUtilities.validateEmbedding(emb) {
                newEmbeddings.append(emb)
            }
        }

        guard !newEmbeddings.isEmpty else { throw SpeakerEnrollmentError.invalidEmbedding }

        var all: [[Float]] = []
        if let base = existing.embedding, SpeakerUtilities.validateEmbedding(base) { all.append(base) }
        all.append(contentsOf: newEmbeddings)
        guard let fused = SpeakerUtilities.averageEmbeddings(all) else { throw SpeakerEnrollmentError.invalidEmbedding }

        existing.embedding = fused
        upsertRuntimeSpeaker(id: id, embedding: fused, duration: 0)
        return existing
    }

    // MARK: - Utility Methods
    
    private func convertTo16kMonoFloat(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let startTime = FeatureFlags.enablePerformanceMonitoring ? Date() : nil
        defer {
            if FeatureFlags.enablePerformanceMonitoring, let start = startTime {
                let elapsed = Date().timeIntervalSince(start) * 1000.0  // ms
                conversionMetrics.totalConversions += 1
                conversionMetrics.totalTimeMs += elapsed

                if elapsed > FeatureFlags.conversionWarningThresholdMs {
                    print("[DiarizationManager] ⚠️ Slow conversion: \(String(format: "%.2f", elapsed))ms")
                }

                // Log metrics every 100 conversions
                if conversionMetrics.totalConversions % 100 == 0 {
                    print(conversionMetrics.summary())
                }
            }
        }

        let sourceFormat = buffer.format
        let mono16k = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: 16000,
                                    channels: 1,
                                    interleaved: false)!

        // Fast path: already 16k mono float (NO changes to this path)
        if sourceFormat.sampleRate == 16000,
           sourceFormat.channelCount == 1,
           sourceFormat.commonFormat == .pcmFormatFloat32,
           let cd = buffer.floatChannelData {
            let count = Int(buffer.frameLength)
            if FeatureFlags.enablePerformanceMonitoring {
                conversionMetrics.fastPathHits += 1
            }
            return Array(UnsafeBufferPointer(start: cd[0], count: count))
        }

        // Conversion required
        let converter = AVAudioConverter(from: sourceFormat, to: mono16k)!
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (16000.0 / sourceFormat.sampleRate) + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: mono16k, frameCapacity: capacity) else { return nil }

        // Use a tiny unmanaged state to avoid concurrency warnings with captured vars
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

        // ===== ANE OPTIMIZATION INTEGRATION POINT =====
        var result: [Float]

        // Check if ANE optimization is enabled
        // Note: Preset filtering can be done in FeatureFlags if needed
        let shouldUseANE = FeatureFlags.useANEMemoryOptimization

        if shouldUseANE {
            // Try ANE-aligned allocation
            do {
                // Create ANE-aligned MLMultiArray
                let shape = [NSNumber(value: frames)]
                let alignedArray = try memoryOptimizer.createAlignedArray(
                    shape: shape,
                    dataType: .float32
                )

                // Validate alignment if enabled
                if FeatureFlags.validateMemoryAlignment {
                    let address = Int(bitPattern: alignedArray.dataPointer)
                    guard address % ANEMemoryOptimizer.aneAlignment == 0 else {
                        print("[DiarizationManager] ⚠️ ANE alignment validation failed, using fallback")
                        if FeatureFlags.enablePerformanceMonitoring {
                            conversionMetrics.aneFallbacks += 1
                        }
                        // Fallback to standard allocation
                        result = Array(UnsafeBufferPointer(start: outData[0], count: frames))
                        if let maxAmp = result.map({ abs($0) }).max(), maxAmp > 1.0 {
                            result = result.map { $0 / maxAmp }
                        }
                        return result
                    }
                }

                // Copy data using ANE-optimized memory operations
                memoryOptimizer.optimizedCopy(
                    from: UnsafeBufferPointer(start: outData[0], count: frames),
                    to: alignedArray,
                    offset: 0
                )

                // Convert MLMultiArray back to [Float]
                // Note: This creates a Swift array from ANE-aligned memory
                let floatPtr = alignedArray.dataPointer.assumingMemoryBound(to: Float.self)
                result = Array(UnsafeBufferPointer(start: floatPtr, count: frames))

                if FeatureFlags.enablePerformanceMonitoring {
                    conversionMetrics.aneSuccesses += 1
                }

                if FeatureFlags.logANEMetrics {
                    print("[DiarizationManager] ✅ ANE-aligned allocation: \(frames) samples")
                }

            } catch {
                // ANE allocation failed - fallback to standard allocation
                if FeatureFlags.logANEMetrics {
                    print("[DiarizationManager] ⚠️ ANE allocation failed: \(error), using standard allocation")
                }
                if FeatureFlags.enablePerformanceMonitoring {
                    conversionMetrics.aneFallbacks += 1
                }

                if FeatureFlags.enableAutomaticFallback {
                    result = Array(UnsafeBufferPointer(start: outData[0], count: frames))
                } else {
                    return nil  // Fail hard if automatic fallback disabled
                }
            }
        } else {
            // ANE optimization disabled - use standard allocation
            result = Array(UnsafeBufferPointer(start: outData[0], count: frames))
        }

        // Normalize lightly to [-1, 1] (unchanged logic)
        if let maxAmp = result.map({ abs($0) }).max(), maxAmp > 1.0 {
            result = result.map { $0 / maxAmp }
        }

        return result
    }

    /// Print ANE optimization metrics summary
    func logANEMetricsSummary() {
        guard FeatureFlags.enablePerformanceMonitoring else { return }
        print("=== ANE Optimization Report ===")
        print(conversionMetrics.summary())
        print("===============================")
    }

    /// Reset ANE metrics (useful for benchmarking)
    func resetANEMetrics() {
        conversionMetrics.reset()
    }


    // MARK: - Reset and Cleanup
    
    func reset() {
        audioBuffer.removeAll()
        lastResult = nil
        lastError = nil
        processingProgress = 0.0
        isProcessing = false
    }
    
    func validateAudio(_ audio: [Float]) async -> AudioValidationResult? {
        guard let diarizer = fluidDiarizer else { return nil }
        return diarizer.validateAudio(audio)
    }

    // Expose a runtime upsert for external helpers (e.g., import).
    func upsertRuntimeSpeaker(id: String, embedding: [Float], duration: Float = 0) {
        fluidDiarizer?.upsertRuntimeSpeaker(id: id, embedding: embedding, duration: duration)
    }

    // Note: deinit removed due to MainActor/Sendable isolation constraints
    // ANE buffer pool will be automatically released when manager is deallocated
}

// MARK: - Error Types

enum DiarizationError: LocalizedError {
    case notInitialized
    case processingFailed(String)
    case invalidAudioFormat
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Gerenciador de diarização não inicializado"
        case .processingFailed(let message):
            return "Falha no processamento de diarização: \(message)"
        case .invalidAudioFormat:
            return "Formato de áudio inválido para diarização"
        case .configurationError(let message):
            return "Erro de configuração da diarização: \(message)"
        }
    }
}

enum SpeakerEnrollmentError: LocalizedError {
    case diarizerNotReady
    case invalidAudio(String)
    case noSpeechDetected
    case invalidEmbedding
    case missingTargetEmbedding
    case speakerNotFound(String)

    var errorDescription: String? {
        switch self {
        case .diarizerNotReady:
            return "Diarizador não está pronto"
        case .invalidAudio(let message):
            return "Áudio inválido para inscrição: \(message)"
        case .noSpeechDetected:
            return "Não foi detectada fala suficiente para extrair a voz"
        case .invalidEmbedding:
            return "Embedding de voz inválido"
        case .missingTargetEmbedding:
            return "Falante de destino não possui embedding salvo"
        case .speakerNotFound(let id):
            return "Falante não encontrado: \(id)"
        }
    }
}

// MARK: - Progress Tracking

extension DiarizationManager {
    func estimateProgress(for audioLength: TimeInterval) -> Double {
        // Rough estimation based on typical processing speed
        let estimatedProcessingTime = audioLength * 0.1 // 10% of real-time
        return min(processingProgress / estimatedProcessingTime, 1.0)
    }
}

#if DEBUG
extension DiarizationManager {
    func replaceDiarizerForTesting(
        _ diarizer: any DiarizerManaging,
        config: DiarizerConfig,
        isEnabled: Bool? = nil,
        enableRealTimeProcessing: Bool? = nil
    ) {
        self.config = config
        if let isEnabled {
            self.isEnabled = isEnabled
        }
        if let enableRealTimeProcessing {
            self.enableRealTimeProcessing = enableRealTimeProcessing
        }
        self.fluidDiarizer = diarizer
        self.isInitialized = true
    }
}
#endif

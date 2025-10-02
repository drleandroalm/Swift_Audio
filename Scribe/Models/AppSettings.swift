import SwiftUI

@Observable
class AppSettings {
    var colorScheme: ColorScheme?
    
    // Diarization settings
    var diarizationEnabled: Bool = true
    var clusteringThreshold: Float = 0.7
    var minSegmentDuration: TimeInterval = 1.0  // Updated from 0.5 → 1.0 per FluidAudio optimal (17.7% DER)
    var maxSpeakers: Int? = nil
    var enableRealTimeProcessing: Bool = false
    var processingWindowSeconds: Double = 10.0  // Optimal per FluidAudio docs (was 3.0)
    // Streaming backpressure/adaptation
    var backpressureEnabled: Bool = true
    var maxLiveBufferSeconds: Double = 20.0  // Updated from 15.0 → 20.0 to accommodate 10s windows + overlap
    var adaptiveWindowEnabled: Bool = true
    // Adaptive real-time pause under load
    var adaptiveRealtimeEnabled: Bool = true
    // UI alerts for performance/backpressure
    var showBackpressureAlerts: Bool = true
    var preset: DiarizationPreset = .custom
    // Feature toggles
    var preciseColorizationEnabled: Bool = true
    var analyticsPanelEnabled: Bool = true
    var waveformEnabled: Bool = true
    // URL trigger
    var allowURLRecordTrigger: Bool = true
    // Microphone selection
    var micManualOverrideEnabled: Bool = false
    // Platform-specific identifier: macOS uses AudioDeviceID (UInt32) stringified; iOS uses AVAudioSessionPortDescription.uid
    var micSelectedDeviceId: String? = nil
    // Verification defaults
    var verifyAutoEnabled: Bool = false
    var verifyThreshold: Float = 0.8
    // Per-speaker overrides
    var verifyPreset: VerifyPreset = .balanced
    var perSpeakerThresholds: [String: Float] = [:] // speakerId -> threshold
    // Speaker embedding fusion method for "Salvar como conhecido"
    var embeddingFusionMethod: EmbeddingFusionMethod = .durationWeighted

    init() {
        // Load saved settings
        if let savedScheme = UserDefaults.standard.object(forKey: "colorScheme") as? Int {
            switch savedScheme {
            case 0:
                self.colorScheme = .light
            case 1:
                self.colorScheme = .dark
            default:
                self.colorScheme = nil
            }
        } else {
            self.colorScheme = nil
        }
        
        // Load diarization settings
        loadDiarizationSettings()
    }

    func setColorScheme(_ scheme: ColorScheme?) {
        self.colorScheme = scheme

        // Save to UserDefaults
        if let scheme = scheme {
            UserDefaults.standard.set(scheme == .light ? 0 : 1, forKey: "colorScheme")
        } else {
            UserDefaults.standard.removeObject(forKey: "colorScheme")
        }
    }

    var themeDisplayName: String {
        switch colorScheme {
        case .light:
            return "Claro"
        case .dark:
            return "Escuro"
        case nil:
            return "Sistema"
        case .some(_):
            return "Sistema"
        }
    }
    
    // MARK: - Diarization Settings
    
    private func loadDiarizationSettings() {
        diarizationEnabled = UserDefaults.standard.object(forKey: "diarizationEnabled") as? Bool ?? true
        clusteringThreshold = UserDefaults.standard.object(forKey: "clusteringThreshold") as? Float ?? 0.7
        minSegmentDuration = UserDefaults.standard.object(forKey: "minSegmentDuration") as? TimeInterval ?? 1.0
        maxSpeakers = UserDefaults.standard.object(forKey: "maxSpeakers") as? Int
        enableRealTimeProcessing = UserDefaults.standard.object(forKey: "enableRealTimeProcessing") as? Bool ?? self.enableRealTimeProcessing
        processingWindowSeconds = UserDefaults.standard.object(forKey: "processingWindowSeconds") as? Double ?? 10.0
        backpressureEnabled = UserDefaults.standard.object(forKey: "backpressureEnabled") as? Bool ?? true
        maxLiveBufferSeconds = UserDefaults.standard.object(forKey: "maxLiveBufferSeconds") as? Double ?? 20.0
        adaptiveWindowEnabled = UserDefaults.standard.object(forKey: "adaptiveWindowEnabled") as? Bool ?? true
        adaptiveRealtimeEnabled = UserDefaults.standard.object(forKey: "adaptiveRealtimeEnabled") as? Bool ?? true
        showBackpressureAlerts = UserDefaults.standard.object(forKey: "showBackpressureAlerts") as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: "diarizationPreset"), let p = DiarizationPreset(rawValue: raw) {
            preset = p
        } else {
            preset = .custom
        }
        preciseColorizationEnabled = UserDefaults.standard.object(forKey: "preciseColorizationEnabled") as? Bool ?? true
        analyticsPanelEnabled = UserDefaults.standard.object(forKey: "analyticsPanelEnabled") as? Bool ?? true
        waveformEnabled = UserDefaults.standard.object(forKey: "waveformEnabled") as? Bool ?? true
        allowURLRecordTrigger = UserDefaults.standard.object(forKey: "allowURLRecordTrigger") as? Bool ?? true
        micManualOverrideEnabled = UserDefaults.standard.object(forKey: "micManualOverrideEnabled") as? Bool ?? false
        micSelectedDeviceId = UserDefaults.standard.string(forKey: "micSelectedDeviceId")
        verifyAutoEnabled = UserDefaults.standard.object(forKey: "verifyAutoEnabled") as? Bool ?? false
        verifyThreshold = UserDefaults.standard.object(forKey: "verifyThreshold") as? Float ?? 0.8
        if let raw = UserDefaults.standard.string(forKey: "verifyPreset"), let p = VerifyPreset(rawValue: raw) {
            verifyPreset = p
        }
        if let raw = UserDefaults.standard.string(forKey: "embeddingFusionMethod"), let m = EmbeddingFusionMethod(rawValue: raw) {
            embeddingFusionMethod = m
        }
        if let data = UserDefaults.standard.data(forKey: "perSpeakerThresholds"),
           let dict = try? JSONDecoder().decode([String: Float].self, from: data) {
            perSpeakerThresholds = dict
        }
    }
    
    // Note: setters moved below to mark preset as custom when adjusted
    
    func setEnableRealTimeProcessing(_ enabled: Bool) {
        self.enableRealTimeProcessing = enabled
        UserDefaults.standard.set(enabled, forKey: "enableRealTimeProcessing")
        if preset != .custom { setPreset(.custom, apply: false) }
    }
    
    func setProcessingWindowSeconds(_ seconds: Double) {
        self.processingWindowSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "processingWindowSeconds")
        if preset != .custom { setPreset(.custom, apply: false) }
    }

    func setBackpressureEnabled(_ enabled: Bool) {
        self.backpressureEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "backpressureEnabled")
    }

    func setMaxLiveBufferSeconds(_ seconds: Double) {
        self.maxLiveBufferSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "maxLiveBufferSeconds")
    }

    func setAdaptiveWindowEnabled(_ enabled: Bool) {
        self.adaptiveWindowEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "adaptiveWindowEnabled")
    }

    func setAdaptiveRealtimeEnabled(_ enabled: Bool) {
        self.adaptiveRealtimeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "adaptiveRealtimeEnabled")
    }

    func setShowBackpressureAlerts(_ enabled: Bool) {
        self.showBackpressureAlerts = enabled
        UserDefaults.standard.set(enabled, forKey: "showBackpressureAlerts")
    }

    func setPreciseColorizationEnabled(_ enabled: Bool) {
        self.preciseColorizationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "preciseColorizationEnabled")
    }

    func setAnalyticsPanelEnabled(_ enabled: Bool) {
        self.analyticsPanelEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "analyticsPanelEnabled")
    }

    func setWaveformEnabled(_ enabled: Bool) {
        self.waveformEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "waveformEnabled")
    }

    func setAllowURLRecordTrigger(_ enabled: Bool) {
        self.allowURLRecordTrigger = enabled
        UserDefaults.standard.set(enabled, forKey: "allowURLRecordTrigger")
    }

    // MARK: - Microphone selection
    func setMicManualOverrideEnabled(_ enabled: Bool) {
        self.micManualOverrideEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "micManualOverrideEnabled")
    }

    func setMicSelectedDeviceId(_ id: String?) {
        self.micSelectedDeviceId = id
        if let id { UserDefaults.standard.set(id, forKey: "micSelectedDeviceId") }
        else { UserDefaults.standard.removeObject(forKey: "micSelectedDeviceId") }
    }

    func setVerifyAutoEnabled(_ enabled: Bool) {
        self.verifyAutoEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "verifyAutoEnabled")
    }

    func setVerifyThreshold(_ value: Float) {
        self.verifyThreshold = value
        UserDefaults.standard.set(value, forKey: "verifyThreshold")
    }

    func setVerifyPreset(_ preset: VerifyPreset) {
        self.verifyPreset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: "verifyPreset")
        switch preset {
        case .conservative:
            verifyThreshold = 0.9
        case .balanced:
            verifyThreshold = 0.8
        case .aggressive:
            verifyThreshold = 0.7
        }
        UserDefaults.standard.set(verifyThreshold, forKey: "verifyThreshold")
    }

    func setSpeakerThreshold(_ value: Float, for speakerId: String) {
        perSpeakerThresholds[speakerId] = value
        persistSpeakerThresholds()
    }

    func removeSpeakerThreshold(for speakerId: String) {
        perSpeakerThresholds.removeValue(forKey: speakerId)
        persistSpeakerThresholds()
    }

    func effectiveThreshold(for speakerId: String?) -> Float {
        if let id = speakerId, let v = perSpeakerThresholds[id] { return v }
        return verifyThreshold
    }

    private func persistSpeakerThresholds() {
        if let data = try? JSONEncoder().encode(perSpeakerThresholds) {
            UserDefaults.standard.set(data, forKey: "perSpeakerThresholds")
        }
    }

    func setEmbeddingFusionMethod(_ method: EmbeddingFusionMethod) {
        embeddingFusionMethod = method
        UserDefaults.standard.set(method.rawValue, forKey: "embeddingFusionMethod")
    }
    
    /// Returns the current diarization configuration for FluidAudio
    func diarizationConfig() -> DiarizerConfig {
        DiarizerConfig(
            clusteringThreshold: clusteringThreshold,
            minSpeechDuration: Float(minSegmentDuration),
            numClusters: maxSpeakers ?? -1,
            minActiveFramesCount: 10.0,
            debugMode: false
        )
    }

    // MARK: - Preset Management
    func setPreset(_ newValue: DiarizationPreset, apply: Bool = true) {
        self.preset = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: "diarizationPreset")

        guard apply else { return }

        // Apply preset without marking as .custom. We write values directly
        // and persist them, avoiding the custom-flag logic in setters.
        switch newValue {
        case .meeting:
            diarizationEnabled = true
            enableRealTimeProcessing = false  // Disabled to prevent backpressure overload
            processingWindowSeconds = 10
            clusteringThreshold = 0.65
            minSegmentDuration = 1.0  // Updated from 0.4 → 1.0 per FluidAudio optimal
            maxSpeakers = nil
        case .interview:
            diarizationEnabled = true
            enableRealTimeProcessing = false  // Disabled to prevent backpressure overload
            processingWindowSeconds = 10
            clusteringThreshold = 0.75
            minSegmentDuration = 1.0  // Updated from 0.8 → 1.0 per FluidAudio optimal
            maxSpeakers = 2
        case .podcast:
            diarizationEnabled = true
            enableRealTimeProcessing = false  // Disabled to prevent backpressure overload
            processingWindowSeconds = 10
            clusteringThreshold = 0.7
            minSegmentDuration = 1.0  // Updated from 0.6 → 1.0 per FluidAudio optimal
            maxSpeakers = 4
        case .custom:
            break
        }

        // Persist values updated above
        UserDefaults.standard.set(diarizationEnabled, forKey: "diarizationEnabled")
        UserDefaults.standard.set(enableRealTimeProcessing, forKey: "enableRealTimeProcessing")
        UserDefaults.standard.set(processingWindowSeconds, forKey: "processingWindowSeconds")
        UserDefaults.standard.set(clusteringThreshold, forKey: "clusteringThreshold")
        UserDefaults.standard.set(minSegmentDuration, forKey: "minSegmentDuration")
        if let maxSpeakers { UserDefaults.standard.set(maxSpeakers, forKey: "maxSpeakers") } else { UserDefaults.standard.removeObject(forKey: "maxSpeakers") }
    }

    // When manual values are changed directly, mark preset as custom
    func setClusteringThreshold(_ threshold: Float) {
        self.clusteringThreshold = threshold
        UserDefaults.standard.set(threshold, forKey: "clusteringThreshold")
        if preset != .custom { setPreset(.custom, apply: false) }
    }
    
    func setMinSegmentDuration(_ duration: TimeInterval) {
        self.minSegmentDuration = duration
        UserDefaults.standard.set(duration, forKey: "minSegmentDuration")
        if preset != .custom { setPreset(.custom, apply: false) }
    }
    
    // Overload to keep original names in use-sites intact
    func setDiarizationEnabled(_ enabled: Bool) {
        self.diarizationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "diarizationEnabled")
        if preset != .custom { setPreset(.custom, apply: false) }
    }
    
    func setMaxSpeakers(_ speakers: Int?) {
        self.maxSpeakers = speakers
        if let speakers = speakers {
            UserDefaults.standard.set(speakers, forKey: "maxSpeakers")
        } else {
            UserDefaults.standard.removeObject(forKey: "maxSpeakers")
        }
        if preset != .custom { setPreset(.custom, apply: false) }
    }
}
    // MARK: - Presets
    enum DiarizationPreset: String, CaseIterable, Identifiable {
        case meeting
        case interview
        case podcast
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .meeting: return "Reunião"
            case .interview: return "Entrevista"
            case .podcast: return "Podcast"
            case .custom: return "Personalizado"
            }
        }

        var description: String {
            switch self {
            case .meeting:
                return "Otimizado para reuniões com vários falantes. Janelas mais curtas e detecção automática de falantes."
            case .interview:
                return "Ideal para entrevistas com dois falantes. Segmentos mais longos e maior estabilidade."
            case .podcast:
                return "Feito para podcasts (2–4 falantes). Equilíbrio entre estabilidade e alternância de falas."
            case .custom:
                return "Ajuste manual dos parâmetros de diarização."
            }
        }
    }

    enum VerifyPreset: String, CaseIterable, Identifiable {
        case conservative
        case balanced
        case aggressive
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .conservative: return "Conservador"
            case .balanced: return "Balanceado"
            case .aggressive: return "Agressivo"
            }
        }
        var description: String {
            switch self {
            case .conservative: return "Menos falsos positivos (≥ 0,90)."
            case .balanced:     return "Recomendado para ambientes normais (≈ 0,80)."
            case .aggressive:   return "Mais permissivo (≈ 0,70)."
            }
        }
    }

    enum EmbeddingFusionMethod: String, CaseIterable, Identifiable {
        case simpleAverage
        case durationWeighted
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .simpleAverage: return "Média simples"
            case .durationWeighted: return "Ponderado por duração"
            }
        }
        var description: String {
            switch self {
            case .simpleAverage: return "Faz a média aritmética das embeddings dos segmentos."
            case .durationWeighted: return "Pondera as embeddings pela duração de cada segmento (recomendado)."
            }
        }
    }

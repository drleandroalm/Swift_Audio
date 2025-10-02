import SwiftUI
import SwiftData

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "Geral"
    case appearance = "Aparência"
    case about = "Sobre"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .appearance:
            return "paintbrush"
        case .about:
            return "info.circle"
        }
    }
}

enum ThemeOption: CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system:
            return "Sistema"
        case .light:
            return "Claro"
        case .dark:
            return "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func from(colorScheme: ColorScheme?) -> ThemeOption {
        switch colorScheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .none:
            return .system
        case .some(_):
            return .system
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTheme: ThemeOption = .system
    @State private var selectedTab: SettingsTab = .general
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var isPhone: Bool {
        #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .phone
        #else
            return false
        #endif
    }

    var body: some View {
        #if os(iOS)
            phoneLayout
        #else
            splitViewLayout
        #endif
    }

    #if os(iOS)
        private var phoneLayout: some View {
            NavigationStack {
                List {
                    ForEach(SettingsTab.allCases) { tab in
                        NavigationLink(destination: settingsContent(for: tab)) {
                            Label(tab.rawValue, systemImage: tab.icon)
                        }
                    }
                }
                .navigationTitle("Configurações")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        dismissButton
                    }
                }
            }
        }
    #endif

    private var splitViewLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            selectedTheme = ThemeOption.from(colorScheme: settings.colorScheme)
        }
    }

    private var sidebarContent: some View {
        #if os(macOS)
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Configurações")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
            .toolbarBackground(.hidden)
            .padding(.top, 10)
            .toolbar(removing: .sidebarToggle)
        #else
            List(SettingsTab.allCases) { tab in
                Button(action: { selectedTab = tab }) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                }
                .listRowBackground(
                    selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear
                )
            }
            .navigationTitle("Configurações")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
            .toolbarBackground(.hidden)
        #endif
    }

    private var detailContent: some View {
        settingsContent(for: selectedTab)
            .navigationTitle(selectedTab.rawValue)
            #if os(macOS)
                .navigationSplitViewStyle(.balanced)
                .navigationSubtitle("")
            #endif
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        dismissButton
                    }
                #endif
            }
            .toolbarBackground(.hidden)
    }

    private var dismissButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
        }
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(settings: settings)
        case .appearance:
            AppearanceSettingsView(settings: settings, selectedTheme: $selectedTheme)
                .onAppear {
                    selectedTheme = ThemeOption.from(colorScheme: settings.colorScheme)
                }
        case .about:
            AboutSettingsView()
        }
    }
}

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var manualMaxSpeakers: Int = 2
    @Environment(\.modelContext) private var modelContext
    @State private var micDevices: [MicrophoneSelector.Device] = []
    @State private var selectedMicId: String? = nil

    var body: some View {
        SettingsPageView(
            title: "Configurações gerais",
            subtitle: "Gerencie a diarização de falantes e o comportamento da captura."
        ) {
            SettingsGroup(title: "Microfone") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Selecionar microfone manualmente", isOn: Binding(
                        get: { settings.micManualOverrideEnabled },
                        set: { settings.setMicManualOverrideEnabled($0) }
                    ))
                    .onChange(of: settings.micManualOverrideEnabled) { _, _ in
                        MicrophoneSelector.applySelectionIfNeeded(settings)
                    }
                    if settings.micManualOverrideEnabled {
                        HStack {
                            Text("Dispositivo de entrada")
                                .fontWeight(.medium)
                            Spacer()
                            Picker("Dispositivo", selection: Binding(
                                get: { selectedMicId ?? settings.micSelectedDeviceId ?? "" },
                                set: { newId in selectedMicId = newId; settings.setMicSelectedDeviceId(newId); MicrophoneSelector.applySelectionIfNeeded(settings) }
                            )) {
                                ForEach(micDevices) { dev in
                                    Text(dev.name).tag(dev.id)
                                }
                            }
                            .frame(maxWidth: 420)
                        }
                    } else {
                        let current = MicrophoneSelector.currentDeviceName() ?? "<desconhecido>"
                        Text("Usando seleção automática do sistema: \(current)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear {
                    micDevices = MicrophoneSelector.availableDevices()
                    selectedMicId = settings.micSelectedDeviceId ?? selectedMicId
                }
            }

            SettingsGroup(title: "Diarização de falantes") {
                VStack(alignment: .leading, spacing: 16) {
                    // Preset selector
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Perfil")
                                .fontWeight(.medium)
                            Spacer()
                            Picker("Perfil", selection: Binding(
                                get: { settings.preset },
                                set: { settings.setPreset($0) }
                            )) {
                                ForEach(DiarizationPreset.allCases) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                            .pickerStyle(.segmented)
                            #if os(macOS)
                                .help(settings.preset.description)
                            #endif
                            .frame(maxWidth: 420)

                            Button {
                                settings.setPreset(settings.preset)
                            } label: {
                                Label("Restaurar padrão", systemImage: "arrow.counterclockwise")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(settings.preset == .custom)
                            #if os(macOS)
                                .help("Reaplica os valores do perfil selecionado")
                            #endif
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text(settings.preset.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Ajustar qualquer controle abaixo define o perfil como Personalizado.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Habilitar diarização", isOn: Binding(
                        get: { settings.diarizationEnabled },
                        set: { settings.setDiarizationEnabled($0) }
                    ))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Limite de agrupamento")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.2f", settings.clusteringThreshold))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(settings.clusteringThreshold) },
                                set: { settings.setClusteringThreshold(Float($0)) }
                            ),
                            in: 0.3...0.95,
                            step: 0.05
                        )
                        Text("Valores menores identificam mais falantes, enquanto valores maiores priorizam precisão.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        DisclosureGroup("Exemplos práticos") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "chevron.right")
                                    Text("0,65 ≈ identifica trocas de fala com maior sensibilidade (útil em reuniões)")
                                        .font(.caption)
                                }
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "chevron.right")
                                    Text("0,85 ≈ agrupa falas mais longas do mesmo falante (útil em entrevistas)")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Duração mínima do segmento")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f s", settings.minSegmentDuration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Stepper(value: Binding(
                            get: { settings.minSegmentDuration },
                            set: { settings.setMinSegmentDuration($0) }
                        ), in: 0.3...3.0, step: 0.1) {
                            Text("Refina a duração mínima de fala antes de registrar um segmento.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        DisclosureGroup("Exemplos práticos") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "chevron.right")
                                    Text("0,4 s ≈ cortes rápidos entre falas curtas (reuniões/podcasts dinâmicos)")
                                        .font(.caption)
                                }
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "chevron.right")
                                    Text("1,0 s ≈ menos cortes; ideal quando há pausas naturais mais longas")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Detectar número de falantes automaticamente", isOn: Binding(
                        get: { settings.maxSpeakers == nil },
                        set: { newValue in
                            if newValue {
                                settings.setMaxSpeakers(nil)
                            } else {
                                settings.setMaxSpeakers(manualMaxSpeakers)
                            }
                        }
                    ))

                    if settings.maxSpeakers != nil {
                        Stepper(value: Binding(
                            get: {
                                let current = settings.maxSpeakers ?? manualMaxSpeakers
                                manualMaxSpeakers = current
                                return current
                            },
                            set: { newValue in
                                manualMaxSpeakers = newValue
                                settings.setMaxSpeakers(newValue)
                            }
                        ), in: 2...12) {
                            Text("Limitar a até \(manualMaxSpeakers) falantes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            SettingsGroup(title: "Automação") {
                Toggle("Permitir acionar gravação via URL (swiftscribe://record)", isOn: Binding(
                    get: { settings.allowURLRecordTrigger },
                    set: { settings.setAllowURLRecordTrigger($0) }
                ))
                .tint(.blue)
                Text("Quando ativado, o app inicia a gravação ao receber a URL 'swiftscribe://record'. Requer registrar o esquema de URL no Info plist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

            SettingsGroup(title: "Exibições e Analytics") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Colorir o texto principal por falante (preciso)", isOn: Binding(
                        get: { settings.preciseColorizationEnabled },
                        set: { settings.setPreciseColorizationEnabled($0) }
                    ))
                    Text("Aplica cor por falante diretamente às palavras no texto principal usando o tempo de cada token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Mostrar painel de analytics (Falantes)", isOn: Binding(
                        get: { settings.analyticsPanelEnabled },
                        set: { settings.setAnalyticsPanelEnabled($0) }
                    ))
                    Text("Exibe proporções, número de turnos e tempo total por falante após a gravação.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Mostrar waveform no scrubber", isOn: Binding(
                        get: { settings.waveformEnabled },
                        set: { settings.setWaveformEnabled($0) }
                    ))
                    Text("Exibe a forma de onda abaixo do controle deslizante de reprodução. Desative para reduzir uso de memória em arquivos muito longos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                }

                SettingsGroup(title: "Verificação de semelhança") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Global preset
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Perfil de verificação")
                                    .fontWeight(.medium)
                                Spacer()
                                Picker("Perfil de verificação", selection: Binding(
                                    get: { settings.verifyPreset },
                                    set: { settings.setVerifyPreset($0) }
                                )) {
                                    ForEach(VerifyPreset.allCases) { p in
                                        Text(p.displayName).tag(p)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 360)
                            }
                            Text(settings.verifyPreset.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Verificação contínua (padrão)", isOn: Binding(
                            get: { settings.verifyAutoEnabled },
                            set: { settings.setVerifyAutoEnabled($0) }
                        ))

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Limiar de confiança (padrão)")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.2f", settings.verifyThreshold))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(settings.verifyThreshold) },
                                    set: { settings.setVerifyThreshold(Float($0)) }
                                ),
                                in: 0.5...0.95, step: 0.05
                            )
                            Text("Acima do limiar considera compatível. Aumente para reduzir falsos positivos.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // Fusion method for saving known speakers
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Fusão de embeddings")
                                    .fontWeight(.medium)
                                Spacer()
                                Picker("Fusão", selection: Binding(
                                    get: { settings.embeddingFusionMethod },
                                    set: { settings.setEmbeddingFusionMethod($0) }
                                )) {
                                    ForEach(EmbeddingFusionMethod.allCases) { m in
                                        Text(m.displayName).tag(m)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 420)
                            }
                            Text(settings.embeddingFusionMethod.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // Per-speaker overrides
                        Divider().padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ajustes por falante (opcional)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            let speakers = (try? modelContext.fetch(FetchDescriptor<Speaker>())) ?? []
                            if speakers.isEmpty {
                                Text("Nenhum falante cadastrado.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(speakers, id: \.id) { sp in
                                    HStack {
                                        Text(sp.name).frame(width: 160, alignment: .leading)
                                        Slider(value: Binding(
                                            get: { Double(settings.perSpeakerThresholds[sp.id] ?? settings.verifyThreshold) },
                                            set: { settings.setSpeakerThreshold(Float($0), for: sp.id) }
                                        ), in: 0.5...0.99, step: 0.01)
                                        Text(String(format: "%.2f", settings.perSpeakerThresholds[sp.id] ?? settings.verifyThreshold))
                                            .font(.caption).foregroundStyle(.secondary)
                                        Button("Redefinir") { settings.removeSpeakerThreshold(for: sp.id) }
                                            .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsGroup(title: "Processamento em tempo real") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Processar durante a captura", isOn: Binding(
                            get: { settings.enableRealTimeProcessing },
                            set: { settings.setEnableRealTimeProcessing($0) }
                    ))

                    Text("Quando ativado, a diarização tenta analisar a gravação durante a captura para fornecer resultados imediatos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Janela de processamento: \(Int(settings.processingWindowSeconds)) s")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    #if os(iOS)
                        Slider(value: Binding(
                            get: { settings.processingWindowSeconds },
                            set: { settings.setProcessingWindowSeconds($0) }
                        ), in: 1...10, step: 1)
                    #else
                        Stepper(value: Binding(
                            get: { settings.processingWindowSeconds },
                            set: { settings.setProcessingWindowSeconds($0) }
                        ), in: 1...10, step: 1) {
                            Text("Ajusta o tamanho da janela usada para diarização contínua durante a captura.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    #endif

                    Divider().padding(.vertical, 4)

                    // Backpressure and adaptation controls
                    Toggle("Controle de backpressure (limitar atraso ao vivo)", isOn: Binding(
                        get: { settings.backpressureEnabled },
                        set: { settings.setBackpressureEnabled($0) }
                    ))
                    .tint(.blue)
                    Text("Quando ativado, o app limita a fila de áudio ao vivo e descarta amostras antigas sob carga.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Buffer ao vivo máximo: \(Int(settings.maxLiveBufferSeconds)) s")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    #if os(iOS)
                        Slider(value: Binding(
                            get: { settings.maxLiveBufferSeconds },
                            set: { settings.setMaxLiveBufferSeconds($0) }
                        ), in: 2...12, step: 1)
                    #else
                        Stepper(value: Binding(
                            get: { settings.maxLiveBufferSeconds },
                            set: { settings.setMaxLiveBufferSeconds($0) }
                        ), in: 2...12, step: 1) {
                            Text("Limita a latência ao vivo sob carga pesada.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    #endif

                    Toggle("Adaptação automática da janela", isOn: Binding(
                        get: { settings.adaptiveWindowEnabled },
                        set: { settings.setAdaptiveWindowEnabled($0) }
                    ))
                    .tint(.blue)
                    Text("Ajusta dinamicamente o tamanho da janela para manter o tempo de processamento dentro de um limite seguro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Pausar diarização ao vivo sob alto uso", isOn: Binding(
                        get: { settings.adaptiveRealtimeEnabled },
                        set: { settings.setAdaptiveRealtimeEnabled($0) }
                    ))
                    .tint(.blue)
                    Text("Quando ativado, a diarização em tempo real é pausada temporariamente em casos de uso elevado para manter a estabilidade. O processamento completo ocorre no final.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Exibir alertas de desempenho", isOn: Binding(
                        get: { settings.showBackpressureAlerts },
                        set: { settings.setShowBackpressureAlerts($0) }
                    ))
                    Text("Controla a exibição de mensagens como ‘Alto uso — reduzindo latência’. Não afeta a qualidade da transcrição nem a diarização final.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .onAppear {
            manualMaxSpeakers = settings.maxSpeakers ?? manualMaxSpeakers
        }
    }
}

struct AppearanceSettingsView: View {
    @Bindable var settings: AppSettings
    @Binding var selectedTheme: ThemeOption

    var body: some View {
        SettingsPageView(
            title: "Aparência",
            subtitle: "Personalize a aparência do app."
        ) {
            SettingsGroup(title: "Tema") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Esquema de cores")
                            .fontWeight(.medium)
                        Spacer()
                    }

                    Picker("Tema", selection: $selectedTheme) {
                        ForEach(ThemeOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedTheme) { _, newValue in
                        settings.setColorScheme(newValue.colorScheme)
                    }

                    Text(
                        "Escolha como o app deve parecer. \"Sistema\" usa a aparência configurada no dispositivo."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        SettingsPageView(
            title: "Sobre",
            subtitle: "Informações sobre o Swift Scribe."
        ) {
            SettingsGroup(title: "Informações do app") {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "app.badge")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Swift Scribe")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Transcrição de áudio e anotações com IA")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    Divider()

                    VStack(spacing: 12) {
                        SettingsInfoRow(label: "Versão", value: "1.0.0")
                        SettingsInfoRow(label: "Compilação", value: "1.0.0 (1)")
                        SettingsInfoRow(label: "Plataforma", value: platformName)
                        }

                    }
                    .padding()
                }
        }
    }

    private var platformName: String {
        #if os(macOS)
            return "macOS"
        #elseif os(iOS)
            return "iOS"
        #else
            return "Desconhecido"
        #endif
    }
}

// MARK: - Reusable Components

struct SettingsPageView<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }

                    content
                }
                .padding()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox(title) {
            content
        }
    }
}

struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
        }
    }
}

#Preview {
    SettingsView(settings: AppSettings())
}

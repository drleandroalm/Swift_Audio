import AVFoundation
import Foundation
import Speech
import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers
import os

struct TranscriptView: View {
    @Bindable var memo: Memo
    @Binding var isRecording: Bool
    @State var isPlaying = false
    @State var isGenerating = false

    @State var recorder: Recorder?
    @StateObject var speechTranscriber: SpokenWordTranscriber

    @State var downloadProgress = 0.0

    @State var currentPlaybackTime = 0.0

    @State var timer: Timer?
    // Background task that streams mic audio to the transcriber/diarizer
    @State private var recordTask: Task<Void, Never>?
    // Guard for avoiding rapid start/stop races and accidental early stop
    @State private var isTransitioningRecordingState = false
    @State private var minStopUntil: Date? = nil
    // Buffer settle indicator (first input buffer arrival)
    @State private var bufferSettled: Bool = false
    @State private var streamSettled: Bool = false
    @State private var firstBufferArrivedAt: Date? = nil
    // Debounce live diarization UI updates to reduce SwiftUI churn during recording
    @State private var pendingLiveResult: DiarizationResult?
    @State private var liveDebounceWork: DispatchWorkItem?
    // Recording banners
    @State private var bannerMessage: String? = nil
    @State private var bannerVisible: Bool = false

    // Recording timer state
    @State var recordingStartTime: Date?
    @State var recordingDuration: TimeInterval = 0
    @State var recordingTimer: Timer?
    
    // Track spurious stops to prevent timer resets
    @State private var expectedStop: Bool = false
    @State private var lastStopCause: String? = nil

    // AI enhancement state
    @State var showingEnhancedView = false
    @State var enhancementError: String?
    @State var isEditingSummary = false
    
    // Speaker view state
    @State var showingSpeakerView = false
    @State private var showingEnrollmentSheet = false
    @State private var showingRenameSheet = false
    @State private var renameTargetSpeakerId: String? = nil
    @State private var renameNewName: String = ""
    @State private var showingVerifySheet = false
    @State private var verifyTargetSpeakerId: String? = nil
    // iOS file import/export (Speakers)
    @State private var iosShowingExport = false
    @State private var iosShowingImport = false
    @State private var iosExportDocument = SpeakersDocument()
    // iOS file export (Transcript)
    @State private var iosShowExportTranscriptJSON = false
    @State private var iosShowExportTranscriptMD = false
    @State private var transcriptJSONDoc = TranscriptJSONDocument()
    @State private var transcriptMDdoc = TranscriptMarkdownDocument()
    @State private var iosShowCombinedExport = false
    @State private var combinedExportDoc = CombinedExportDocument()
    @State private var showTranscriptExportPicker = false
    @State private var showingEnhanceSheet = false
    @State private var enhanceTargetSpeakerId: String? = nil
    // Scrubber / clear-confirm state
    @State private var totalDuration: TimeInterval = 0
    @State private var isScrubbing: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var waveform: [Float] = []
    // Throttle repeated backpressure banners
    @State private var lastBackpressureBannerAt: Date? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(DiarizationManager.self) private var diarizationManager
    
    // Unified mode switch for finished memos
    enum DisplayMode: String, CaseIterable, Identifiable { case transcript, summary, speakers; var id: String { rawValue } }
    @State private var displayMode: DisplayMode = .transcript
    
    init(memo: Memo, isRecording: Binding<Bool>) {
        self._memo = Bindable(wrappedValue: memo)
        self._isRecording = isRecording
        let transcriber = SpokenWordTranscriber(memo: memo)
        self._speechTranscriber = StateObject(wrappedValue: transcriber)
        // Recorder will be initialized in onAppear with proper modelContext
        self._recorder = State(initialValue: nil)
        // Show enhanced view by default if summary exists
        self._showingEnhancedView = State(initialValue: memo.summary != nil)
    }

    // Break up heavy UI into smaller computed views to reduce type-checker load.
    private func modeSwitchView() -> AnyView {
        switch displayMode {
        case .transcript:
            return AnyView(playbackView)
        case .summary:
            return AnyView(enhancedView)
        case .speakers:
            return memo.hasSpeakerData ? AnyView(speakerView) : AnyView(playbackView)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            if !memo.isDone {
                LiveRecordingContentView(content: AnyView(liveRecordingView))
            } else {
                FinishedMemoContentView(
                    header: AnyView(modernHeader),
                    toolbar: AnyView(transcriptToolbar),
                    modeView: modeSwitchView()
                )
            }

            // Add padding at bottom for floating buttons
            #if os(iOS)
                Spacer().frame(height: 100)
            #else
                Spacer()
            #endif
        }
        #if os(macOS)
            .padding(20)
        #endif
    }

    // iOS floating buttons and transient banner overlays as erased views to ease type-checking
    private var iOSFloatingButtonsAny: AnyView {
        #if os(iOS)
            return AnyView(
                VStack {
                    Spacer()
                    bottomButtonBar
                }
                .ignoresSafeArea(.keyboard)
            )
        #else
            return AnyView(EmptyView())
        #endif
    }

    private var bannerOverlayAny: AnyView {
        if bannerVisible, let msg = bannerMessage {
            return AnyView(
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(msg).font(.subheadline).fontWeight(.semibold)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(radius: 4)
                    Spacer()
                }
                .padding(.top, 16)
            )
        }
        return AnyView(EmptyView())
    }

    // macOS toolbar extracted to reduce type-checker pressure in body
    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        #if os(macOS)
        Group {
            // AI controls
            if memo.isDone {
                ToolbarItem { enhanceButton }
                if memo.summary != nil { ToolbarItem { viewToggleButton } }
                ToolbarItem { memo.hasSpeakerData ? AnyView(speakerViewToggleButton) : AnyView(speakerViewToggleButtonDisabled) }
            }
            ToolbarSpacer(.fixed)
            if !memo.isDone { ToolbarItem { recordButton } }
            ToolbarSpacer(.fixed)
            if memo.isDone { ToolbarItem { playButton } }
            ToolbarSpacer(.fixed)
        }
        #else
        ToolbarItem(placement: .automatic) { EmptyView() }
        #endif
    }

    // MARK: - Event Handlers (extracted)

    private func onRecordingStateChanged(oldValue: Bool, newValue: Bool) {
        let timestamp = Date().timeIntervalSince1970
        Log.state.info("TranscriptView: onRecordingStateChanged CALLED at timestamp=\(timestamp, privacy: .public) oldValue=\(oldValue ? "true" : "false", privacy: .public) newValue=\(newValue ? "true" : "false", privacy: .public)")

        guard newValue != oldValue else {
            Log.state.warning("TranscriptView: Estado de gravação não mudou (oldValue=\(oldValue), newValue=\(newValue)), ignorando")
            return
        }
        Log.state.info("TranscriptView: Estado de gravação alterado de \(oldValue) para \(newValue)")
        Log.state.info("Recording toggled at timestamp=\(timestamp, privacy: .public)")

        if newValue == true {
            Log.state.info("TranscriptView: INICIANDO gravação - isTransitioningRecordingState=false->true")
            isTransitioningRecordingState = true
            // Ensure ML warmup has completed before starting engines
            ModelWarmupService.shared.warmupIfNeeded()
            // Disallow immediate stop toggles for a short period to avoid accidental double-tap/keyboard triggers
            minStopUntil = Date().addingTimeInterval(0.5)
            // Reset buffer settle indicator for a fresh session
            bufferSettled = false
            // Start recording timer
            let start = Date()
            memo.activeRecordingStart = start
            Log.state.error("🕐 About to call startRecordingClock at timestamp=\(Date().timeIntervalSince1970, privacy: .public)")
            startRecordingClock(at: start, resetElapsed: true)
            Log.state.error("🕐 Returned from startRecordingClock, recordingTimer=\(recordingTimer != nil ? "not nil" : "nil", privacy: .public) recordingDuration=\(recordingDuration, privacy: .public)")
            // Clear main-actor audio arrival flags for this session
            bufferSettled = false
            streamSettled = false
            firstBufferArrivedAt = nil

            // If restarting recording on an existing memo, reset the transcriber
            if memo.isDone {
                memo.isDone = false
                speechTranscriber.reset()
                print("DEPURAÇÃO [TranscriptView]: Transcritor reiniciado para memorando existente")
            }
            // Launch and retain the recording task so we can cancel it on stop.
            // Use a detached task to avoid unintended cancellation propagation from SwiftUI.
            Log.state.info("TranscriptView: Lançando recordTask...")
            recordTask = Task.detached(priority: .userInitiated) {
                let taskTimestamp = Date().timeIntervalSince1970
                await MainActor.run {
                    Log.state.info("TranscriptView: recordTask iniciado at timestamp=\(taskTimestamp, privacy: .public)")
                }
                // Snapshot a non-nil recorder instance on the main actor
                let currentRecorder = await MainActor.run { recorder }
                guard let recorder = currentRecorder else {
                    await MainActor.run {
                        Log.state.error("TranscriptView: Nenhum gravador disponível ao iniciar; mantendo isRecording=true e registrando erro")
                        Log.state.error("recordTask start failed: recorder unavailable; leaving isRecording=true")
                        isTransitioningRecordingState = false
                        showBanner("Falha ao iniciar — gravador indisponível")
                    }
                    return
                }
                await MainActor.run {
                    Log.state.info("TranscriptView: Recorder disponível, chamando recorder.record()...")
                }
                // Retry-on-error loop: avoid flipping isRecording=false on transient failures
                let maxAttempts = 2
                var attempt = 0
                while attempt <= maxAttempts {
                    do {
                        try await recorder.record()
                        // record() returned → check if this was expected
                        print("DEPURAÇÃO [TranscriptView]: record() returned — stream ended")
                        await MainActor.run {
                            if isRecording && !expectedStop {
                                // Stream ended unexpectedly (backpressure, HAL error, audio system failure)
                                Log.state.error("⚠️ Recording stream ended unexpectedly - cleaning up state")
                                isRecording = false
                                recordingTimer?.invalidate()
                                recordingTimer = nil
                                recordingStartTime = nil
                                recordingDuration = 0
                                memo.activeRecordingStart = nil
                                showBanner("Gravação interrompida inesperadamente")
                            }
                        }
                        break
                    } catch is CancellationError {
                        break
                    } catch let error as TranscriptionError {
                        let attemptIndex = attempt + 1
                        await MainActor.run {
                            Log.state.error("record() failed (TranscriptionError) attempt=\(attemptIndex): \(error.descriptionString)")
                            showBanner("Problema na gravação — tentando novamente…")
                            isTransitioningRecordingState = false
                        }
                        attempt += 1
                        if attempt <= maxAttempts { try? await Task.sleep(nanoseconds: 500_000_000); continue }
                        await MainActor.run {
                            enhancementError = "Falha na gravação: \(error.descriptionString)"
                        }
                        break
                    } catch {
                        let attemptIndex = attempt + 1
                        await MainActor.run {
                            Log.state.error("record() failed attempt=\(attemptIndex): \(error.localizedDescription)")
                            showBanner("Erro de gravação — tentando novamente…")
                            isTransitioningRecordingState = false
                        }
                        attempt += 1
                        if attempt <= maxAttempts { try? await Task.sleep(nanoseconds: 500_000_000); continue }
                        await MainActor.run {
                            enhancementError = "Falha na gravação: \(error.localizedDescription)"
                        }
                        break
                    }
                }
                await MainActor.run { isTransitioningRecordingState = false }
            }
        } else {
            print("DEPURAÇÃO [TranscriptView]: Iniciando parada da gravação")
            Log.state.info("Recording toggled")
            // Mark this as an expected stop to prevent spurious restarts
            expectedStop = true
            // Stop recording timer only for user-initiated stops
            recordingTimer?.invalidate()
            recordingTimer = nil
            recordingStartTime = nil
            recordingDuration = 0
            memo.activeRecordingStart = nil

            Task {
                do {
                    let runningTask = recordTask
                    recordTask = nil
                    try await recorder?.stopRecording(cause: .user)
                    print("DEPURAÇÃO [TranscriptView]: Gravação interrompida com sucesso")
                    isTransitioningRecordingState = false
                    await runningTask?.value
                    // Generate title and summary after recording stops
                    await generateTitleIfNeeded()
                    await generateAIEnhancements()
                } catch {
                    print("DEPURAÇÃO [TranscriptView]: Erro ao interromper a gravação: \(error)")
                    await MainActor.run {
                        enhancementError =
                            "Erro ao interromper a gravação: \(error.localizedDescription)"
                        isTransitioningRecordingState = false
                    }
                }
            }
        }
    }

    var body: some View {
        let base = AnyView(ZStack {
            AnyView(contentView)
            iOSFloatingButtonsAny
            BannerOverlayView(isVisible: bannerVisible, message: bannerMessage)
        })
        .background(
            LinearGradient(colors: [Color.black.opacity(0.01), Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .navigationTitle(memo.title)
        #if os(iOS)
            .overlay(combinedExporter)
        #endif
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isRecording)
            .toolbar { IOSPrincipalToolbar(title: memo.title, subtitle: memo.isDone ? memo.createdAt.formatted(date: .abbreviated, time: .omitted) : nil, isRecording: isRecording) }
        #endif
        .toolbar { macToolbar }
        
        let view = AnyView(base.modifier(
            RecordingHandlersModifier(
                onRecordingChange: { oldVal, newVal in onRecordingStateChanged(oldValue: oldVal, newValue: newVal) },
                onPlayingChange: { handlePlayback() },
                onMemoURLChange: { url in
                    if settings.waveformEnabled, let u = url {
                        waveform = WaveformGenerator.generate(from: u, desiredSamples: 600)
                    }
                },
                onFirstBuffer: { bufferSettled = true; if firstBufferArrivedAt == nil { firstBufferArrivedAt = Date() } },
                onFirstStream: { streamSettled = true },
                onRecorderStop: { cause in
                    if let c = cause { Log.state.info("Recorder did stop with cause=\(c, privacy: .public)") }
                    lastStopCause = cause
                    // Ignore spurious silenceTimeouts once the first buffer arrived on the main actor
                    // Also ignore silenceTimeouts if we've had any successful audio in this session
                    if cause == "silenceTimeout" && (firstBufferArrivedAt != nil || bufferSettled) {
                        Log.state.notice("Ignoring silenceTimeout stop due to first buffer already observed or settled")
                        return
                    }
                    // Don't reset timer/state for silence timeouts that might be spurious
                    if cause == "silenceTimeout" && !expectedStop {
                        showBanner("Sistema de áudio reiniciando — aguarde...")
                        // Try to restart recording automatically after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if !isRecording && memo.url == nil {
                                Log.state.notice("Auto-restarting recording after spurious silence timeout")
                                isRecording = true
                            }
                        }
                        return
                    }
                    // Show more informative banner for different stop causes
                    if cause == "silenceTimeout" { 
                        showBanner("Sistema de áudio não respondeu — verifique microfone") 
                    }
                    if isRecording { 
                        expectedStop = true
                        isRecording = false
                        isTransitioningRecordingState = false 
                        expectedStop = false
                    }
                },
                onBackpressure: { live, drops in
                    guard settings.showBackpressureAlerts else { return }
                    if drops >= 3 {
                        let now = Date()
                        if lastBackpressureBannerAt == nil || now.timeIntervalSince(lastBackpressureBannerAt!) > 12 {
                            lastBackpressureBannerAt = now
                            showBanner(String(format: "Alto uso — reduzindo latência (%.1fs de buffer)", live))
                        }
                    }
                },
                onMemoIdChange: { Task { await reinitializeForNewMemo() } },
                onAppear: {
                    let timestamp = Date().timeIntervalSince1970
                    Log.ui.info("TranscriptView: onAppear chamado at timestamp=\(timestamp, privacy: .public)")
                    syncDiarizationWithSettings()
                    displayMode = memo.summary != nil ? .summary : .transcript
                    if recorder == nil { recorder = Recorder(transcriber: speechTranscriber, memo: memo, diarizationManager: diarizationManager, modelContext: modelContext) }
                    // Auto-record is now handled in ContentView.onAppear to avoid duplicate triggers
                    // Keep only "Novo Memorando" detection for manual creation
                    if !memo.isDone && memo.text.characters.isEmpty && memo.url == nil && memo.title == "Novo Memorando" {
                        let volatileCount = speechTranscriber.volatileTranscript.characters.count
                        let finalizedCount = speechTranscriber.finalizedTranscript.characters.count
                        let memoTextCount = memo.text.characters.count

                        Log.ui.warning("⚠️ onAppear RESET CONDITION MET at timestamp=\(timestamp, privacy: .public)")
                        Log.ui.info("  isRecording=\(isRecording ? "true" : "false", privacy: .public)")
                        Log.ui.info("  isTransitioning=\(isTransitioningRecordingState ? "true" : "false", privacy: .public)")
                        Log.ui.info("  memo.text.count=\(memoTextCount, privacy: .public)")
                        Log.ui.info("  volatileTranscript.count=\(volatileCount, privacy: .public)")
                        Log.ui.info("  finalizedTranscript.count=\(finalizedCount, privacy: .public)")

                        // CRITICAL FIX: Only reset if NOT actively recording
                        // During live recording, transcripts are in volatileTranscript/finalizedTranscript, NOT memo.text
                        // Resetting here would clear active transcription from the screen (BUG!)
                        if !isRecording && !isTransitioningRecordingState {
                            Log.ui.info("TranscriptView: Novo memorando detectado - resetting transcriber for fresh start")
                            speechTranscriber.reset()
                        } else {
                            Log.ui.error("⛔️ PREVENTED RESET - Recording is active! (isRecording=\(isRecording), isTransitioning=\(isTransitioningRecordingState))")
                        }
                        // Note: Recording will be started by ContentView's auto-record logic or user action
                    }
                    if settings.waveformEnabled, let url = memo.url { waveform = WaveformGenerator.generate(from: url, desiredSamples: 600) } else { waveform = [] }
                    resumeRecordingClockIfNeeded()
                },
                onTask: { downloadProgress = speechTranscriber.downloadFraction * 100.0 },
                onDisappear: {
                    timer?.invalidate(); timer = nil
                    recordingTimer?.invalidate(); recordingTimer = nil
                    let task = recordTask; recordTask = nil
                    Task { await recorder?.teardown(); await task?.value }
                },
                enhancementError: $enhancementError,
                showClearConfirm: $showClearConfirm,
                onClearConfirmed: { clearTranscript() },
                isRecording: $isRecording,
                isPlaying: $isPlaying,
                memoId: memo.id,
                memoURL: memo.url
            )
        ))
        return view
    }

    // MARK: - Bottom Button Bar for iOS

    #if os(iOS)
        @ViewBuilder
        private var bottomButtonBar: some View {
            HStack(spacing: 16) {
                // Recording/Stop button - always visible when recording
                if !memo.isDone {
                    recordButtonLarge
                } else {
                    // View toggle buttons
                    HStack(spacing: 12) {
                        if memo.summary != nil {
                            viewToggleButtonCompact
                        }
                        
                        if memo.hasSpeakerData {
                            speakerViewToggleButtonCompact
                        } else {
                            speakerViewToggleButtonCompactDisabled
                        }
                    }

                    Spacer()

                    // AI enhance button
                    enhanceButtonCompact
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }

        @ViewBuilder
        private var recordButtonLarge: some View {
            Button {
                handleRecordingButtonTap()
            } label: {
                HStack(spacing: 12) {
                    Label(
                        isRecording ? "Parar gravação" : "Iniciar gravação",
                        systemImage: isRecording ? "stop.circle.fill" : "record.circle.fill"
                    )
                    .font(.headline)
                    .fontWeight(.semibold)

                    if isRecording {
                        Text(formatDuration(recordingDuration))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
            }
            .buttonStyle(.glass)
            .controlSize(.extraLarge)
            .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))  // Green for start, red for stop
            .disabled(isTransitioningRecordingState)
        }

        @ViewBuilder
        private var viewToggleButtonCompact: some View {
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    showingEnhancedView.toggle()
                    if showingEnhancedView {
                        showingSpeakerView = false
                    }
                }
            } label: {
                Label(
                    showingEnhancedView ? "Transcrição" : "Resumo",
                    systemImage: showingEnhancedView ? "doc.plaintext" : "sparkles"
                )
                .font(.body)
                .fontWeight(.medium)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(showingEnhancedView ? .gray : SpokenWordTranscriber.green)
        }
        
        @ViewBuilder
        private var speakerViewToggleButtonCompact: some View {
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    showingSpeakerView.toggle()
                    if showingSpeakerView {
                        showingEnhancedView = false
                    }
                }
            } label: {
                Label(
                    showingSpeakerView ? "Transcrição" : "Falantes",
                    systemImage: showingSpeakerView ? "doc.plaintext" : "person.2"
                )
                .font(.body)
                .fontWeight(.medium)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(showingSpeakerView ? .gray : .blue)
        }

        @ViewBuilder
        private var speakerViewToggleButtonCompactDisabled: some View {
            HStack(spacing: 6) {
                Button(action: {}) {
                    Label("Falantes", systemImage: "person.2")
                        .font(.body)
                        .fontWeight(.medium)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(.gray.opacity(0.6))
                .disabled(true)

                Text("Geraremos assim que houver áudio suficiente")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        @ViewBuilder
        private var enhanceButtonCompact: some View {
            Button {
                handleAIEnhanceButtonTap()
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        memo.summary != nil ? "Gerar resumo novamente" : "Resumir com IA",
                        systemImage: memo.summary != nil ? "arrow.clockwise" : "sparkles"
                    )
                    .font(.body)
                    .fontWeight(.medium)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(SpokenWordTranscriber.green)
            .disabled(memo.text.characters.isEmpty || isGenerating)
        }
    #endif

    // MARK: - Enhanced View

    @ViewBuilder
    private var enhancedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
                // Simplified header for iOS
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(SpokenWordTranscriber.green)

                    Text("Resumo por IA")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            #endif

            #if os(macOS)
                // Header section with better spacing
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(SpokenWordTranscriber.green)
                            .symbolRenderingMode(.monochrome)

                        Text("Resumo aprimorado por IA")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            #endif

            // Enhanced content area with better formatting
            Group {
                if let summary = memo.summary, !String(summary.characters).isEmpty {
                    ScrollView {
                        Text(summary)
                            .font(.body)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            #if os(iOS)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            #else
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            #endif
                            .textSelection(.enabled)
                    }
                    #if os(macOS)
                        .padding(.horizontal, 16)
                    #endif
                    .scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    // Improved loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .foregroundStyle(SpokenWordTranscriber.green)

                        VStack(spacing: 8) {
                            Text("Gerando resumo aprimorado...")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("Isso pode levar alguns instantes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
            .background(.background.secondary.opacity(0.3))
        #endif
    }
    
    // MARK: - Speaker View
    
    @ViewBuilder
    private var speakerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
                // Simplified header for iOS
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.body)
                        .foregroundStyle(.blue)

                    Text("Falantes")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()
                    
                    // Speaker count badge
                    if memo.hasSpeakerData {
                        Text("\(memo.speakers(in: modelContext).count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue, in: Capsule())
                    }

                    Button {
                        showingEnrollmentSheet = true
                    } label: {
                        Label("Inscrever", systemImage: "person.crop.circle.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                    .tint(.blue)

                    Button {
                        prepareExport()
                        iosShowingExport = true
                    } label: {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)

                    Button {
                        iosShowingImport = true
                    } label: {
                        Label("Importar", systemImage: "square.and.arrow.down")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)

                    Button {
                        showTranscriptExportPicker = true
                    } label: {
                        Label("Exportar transcrição", systemImage: "doc.text")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            #endif

            #if os(macOS)
                // Header section with better spacing
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .symbolRenderingMode(.monochrome)

                        Text("Diarização de falantes")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()
                        
                        // Enroll speaker button (macOS toolbar-like in header)
                        Button {
                            showingEnrollmentSheet = true
                        } label: {
                            Label("Inscrever falante", systemImage: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.glass)
                        .tint(.blue)

                        // Export / Import speakers (macOS)
                        Button {
                            exportSpeakers()
                        } label: {
                            Label("Exportar", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.glass)

                        Button {
                            importSpeakers()
                        } label: {
                            Label("Importar", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.glass)
                        
                        // Speaker count and processing info
                        if memo.hasSpeakerData {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(memo.speakers(in: modelContext).count) falantes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(memo.speakerSegments.count) segmentos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            #endif

            // Speaker analytics (optional)
            if settings.analyticsPanelEnabled, memo.hasSpeakerData {
                speakerAnalyticsPanel
            }

            // Speaker transcript content
            Group {
                if memo.hasSpeakerData {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Speaker legend
                            speakerLegend
                            
                            Divider()
                            
                            // Speaker-segmented transcript
                            Text(memo.formattedTranscriptWithSpeakers(context: modelContext))
                                .font(.body)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                #if os(iOS)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                #else
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                #endif
                                .textSelection(.enabled)
                        }
                    }
                    #if os(macOS)
                        .padding(.horizontal, 16)
                    #endif
                    .scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    // No speaker data state
                    VStack(spacing: 20) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            Text("Nenhum dado de falantes")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("A diarização de falantes não foi executada para esta gravação")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
            .background(.background.secondary.opacity(0.3))
        #endif
        .sheet(isPresented: $showingEnrollmentSheet) {
            SpeakerEnrollmentView(diarizationManager: diarizationManager)
        }
        .sheet(isPresented: $showingRenameSheet) {
            if let sid = renameTargetSpeakerId,
               let speaker = try? modelContext.fetch(FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == sid })).first {
                SpeakerRenameView(speaker: speaker, newName: $renameNewName) { newName in
                    Task { @MainActor in
                        do {
                            try await diarizationManager.renameSpeaker(id: speaker.id, to: newName, in: modelContext)
                        } catch {
                            // Soft fail: name will still update in SwiftData below
                        }
                        speaker.name = newName
                        showingRenameSheet = false
                    }
                }
            } else {
                Text("Falante não encontrado")
                    .padding()
            }
        }
        .sheet(isPresented: $showingVerifySheet) {
            if let sid = verifyTargetSpeakerId,
               let speaker = try? modelContext.fetch(FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == sid })).first {
                SimilarityVerificationView(diarizationManager: diarizationManager, targetSpeaker: speaker)
            } else {
                Text("Falante não encontrado").padding()
            }
        }
        .sheet(isPresented: $showingEnhanceSheet) {
            if let sid = enhanceTargetSpeakerId,
               let speaker = try? modelContext.fetch(FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == sid })).first {
                SpeakerEnhanceView(diarizationManager: diarizationManager, speaker: speaker)
            } else {
                Text("Falante não encontrado").padding()
            }
        }
        #if os(iOS)
        .fileExporter(isPresented: $iosShowingExport, document: iosExportDocument, contentType: .json, defaultFilename: "speakers") { _ in }
        .fileImporter(isPresented: $iosShowingImport, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                if let data = try? Data(contentsOf: url) {
                    try? SpeakerIO.importSpeakers(data: data, context: modelContext, diarizationManager: diarizationManager)
                }
            }
        }
        .confirmationDialog("Exportar transcrição", isPresented: $showTranscriptExportPicker) {
            Button("JSON") { prepareTranscriptJSON(); iosShowExportTranscriptJSON = true }
            Button("Markdown") { prepareTranscriptMD(); iosShowExportTranscriptMD = true }
            Button("Cancelar", role: .cancel) {}
        }
        .fileExporter(isPresented: $iosShowExportTranscriptJSON, document: transcriptJSONDoc, contentType: .json, defaultFilename: "transcript") { _ in }
        .fileExporter(isPresented: $iosShowExportTranscriptMD, document: transcriptMDdoc, contentType: .plainText, defaultFilename: "transcript") { _ in }
        #endif
    }

    #if os(iOS)
    private func prepareExport() {
        if let data = try? SpeakerIO.encodeSpeakers(context: modelContext) {
            iosExportDocument = SpeakersDocument(data: data)
        } else {
            iosExportDocument = SpeakersDocument()
        }
    }

    private func prepareTranscriptJSON() {
        if let data = TranscriptExport.jsonData(for: memo, context: modelContext) {
            transcriptJSONDoc = TranscriptJSONDocument(data: data)
        } else {
            transcriptJSONDoc = TranscriptJSONDocument()
        }
    }

    private func prepareTranscriptMD() {
        if let data = TranscriptExport.markdownData(for: memo, context: modelContext) {
            transcriptMDdoc = TranscriptMarkdownDocument(data: data)
        } else {
            transcriptMDdoc = TranscriptMarkdownDocument()
        }
    }
    #endif

    #if os(macOS)
    private func exportSpeakers() {
        // Prefer Save Panel when entitlement is present; fall back to Documents if unavailable or failing
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let defaultName = "speakers-\(formatter.string(from: Date())).json"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.json] } else { panel.allowedFileTypes = ["json"] }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try SpeakerIO.exportSpeakers(context: modelContext, to: url)
                return
            } catch {
                // Fall through to sandbox-safe fallback below
                print("Export via Save Panel failed, falling back: \(error)")
            }
        }

        // Fallback: export into app container Documents and reveal in Finder
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(defaultName)
            do {
                try SpeakerIO.exportSpeakers(context: modelContext, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { print("Export failed: \(error)") }
        }
    }

    private func importSpeakers() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try SpeakerIO.importSpeakers(context: modelContext, from: url, diarizationManager: diarizationManager) } catch { print("Import failed: \(error)") }
        }
    }
    #endif

    // MARK: Analytics Panel
    @ViewBuilder
    private var speakerAnalyticsPanel: some View {
        let segments = memo.speakerSegments
        if segments.isEmpty { EmptyView() } else {
            let total = segments.reduce(0.0) { $0 + $1.duration }
            let groups = Dictionary(grouping: segments, by: { $0.speakerId })
            let stats: [(speaker: Speaker, total: TimeInterval, turns: Int, ratio: Double)] = groups.compactMap { (id, segs) in
                let totalDur = segs.reduce(0.0) { $0 + $1.duration }
                let turns = segs.count
                let ratio = total > 0 ? totalDur / total : 0
                let sp = try? modelContext.fetch(FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == id })).first
                guard let speaker = sp else { return nil }
                return (speaker, totalDur, turns, ratio)
            }.sorted(by: { $0.total > $1.total })

            VStack(alignment: .leading, spacing: 10) {
                #if os(macOS)
                    Text("Analytics de Falantes")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                #endif

                ForEach(stats, id: \.speaker.id) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(s.speaker.displayColor).frame(width: 10, height: 10)
                            Text(s.speaker.name)
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.0f%%", s.ratio * 100))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            let w = max(1, s.ratio * geo.size.width)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.15))
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(gradient(for: s.speaker.displayColor))
                                    .frame(width: w)
                                    .overlay(
                                        LinearGradient(colors: [Color.white.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    )
                            }
                        }
                        .frame(height: 10)
                        HStack(spacing: 12) {
                            Text("Tempo: \(formatDuration(s.total))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Turnos: \(s.turns)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Divider().padding(.horizontal, 16).padding(.top, 6)
            }
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private var speakerLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Falantes")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            let speakers = memo.speakers(in: modelContext)
            // Speaker cards with mini-sparklines
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 12) {
                ForEach(speakers, id: \.id) { speaker in
                    speakerCard(for: speaker)
                }
            }
            .padding(.bottom, 8)

            Divider().padding(.vertical, 4)
            
            // Legend chips
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120))
            ], spacing: 8) {
                ForEach(speakers, id: \.id) { speaker in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(speaker.displayColor)
                            .frame(width: 12, height: 12)

                        Text(speaker.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Button {
                            saveSpeakerAsKnown(speaker)
                        } label: {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Salvar como conhecido para rotulagem automática")

                        Button {
                            renameTargetSpeakerId = speaker.id
                            renameNewName = speaker.name
                            showingRenameSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Renomear falante")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .contextMenu {
                        Button("Renomear", systemImage: "pencil") {
                            renameTargetSpeakerId = speaker.id
                            renameNewName = speaker.name
                            showingRenameSheet = true
                        }
                        Button("Salvar como conhecido", systemImage: "person.crop.circle.badge.checkmark") {
                            saveSpeakerAsKnown(speaker)
                        }
                        Button("Aprimorar", systemImage: "waveform.badge.plus") {
                            enhanceTargetSpeakerId = speaker.id
                            showingEnhanceSheet = true
                        }
                        Button("Verificar semelhança", systemImage: "checkmark.seal") {
                            verifyTargetSpeakerId = speaker.id
                            showingVerifySheet = true
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func speakerCard(for speaker: Speaker) -> some View {
        let segments = memo.speakerSegments.filter { $0.speakerId == speaker.id }.sorted { $0.startTime < $1.startTime }
        let total = max(memo.speakerSegments.last?.endTime ?? 0, 0.001)
        let totalDur = segments.reduce(0.0) { $0 + $1.duration }
        let turns = segments.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(speaker.displayColor).frame(width: 10, height: 10)
                Text(speaker.name).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button {
                    saveSpeakerAsKnown(speaker)
                } label: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.plain)
                .help("Salvar como conhecido")
                Text(formatDuration(totalDur)).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12))
                    // Sparklines as thin blocks proportional to segment lengths and positions
                    HStack(spacing: 0) {
                        ForEach(segments, id: \.id) { seg in
                            let w = max(1, (seg.endTime - seg.startTime) / total * geo.size.width)
                            let h = CGFloat(max(0.2, min(1.0, seg.duration / max(0.5, totalDur))) * 24)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(gradient(for: speaker.displayColor))
                                .frame(width: w, height: h)
                                .padding(.vertical, (24 - h) / 2)
                        }
                    }
                }
            }
            .frame(height: 24)
            HStack(spacing: 12) {
                Text("Turnos: \(turns)").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", (totalDur / max(0.001, (memo.speakerSegments.reduce(0.0, { max($0, $1.endTime) }) ))) * 100)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Individual Toolbar Buttons

    @ViewBuilder
    private var playButton: some View {
        Button {
            handlePlayButtonTap()
        } label: {
            Label(
                isPlaying ? "Pausar" : "Reproduzir",
                systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var recordButton: some View {
        Button {
            handleRecordingButtonTap()
        } label: {
            HStack(spacing: 8) {
                Label(
                    isRecording ? "Parar" : "Gravar",
                    systemImage: isRecording ? "stop.fill" : "record.circle"
                )

                if isRecording {
                    Text(formatDuration(recordingDuration))
                        .font(.body)
                        .monospacedDigit()
                }
            }
        }
        .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))
        .disabled(isTransitioningRecordingState)
    }

    // Modern header with segmented control for finished memos
    @ViewBuilder
    private var modernHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(memo.title)
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                HStack(spacing: 12) {
                    // Buffer settle indicator (non-blocking)
                    #if os(macOS)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bufferSettled ? Color.green.opacity(0.8) : Color.orange.opacity(0.7))
                            .frame(width: 8, height: 8)
                        Text(bufferSettled ? "Mic pronto" : "Aguardando áudio…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                    if memo.isDone {
                        playButton
                    } else {
                        recordButton
                    }
                }
            }

            // Mode switcher
            Picker("Exibição", selection: $displayMode) {
                Text("Transcrição").tag(DisplayMode.transcript)
                Text("Resumo").tag(DisplayMode.summary)
                Text("Falantes").tag(DisplayMode.speakers)
            }
            .pickerStyle(.segmented)
            .onChange(of: displayMode) { _, mode in
                withAnimation(.smooth(duration: 0.2)) {
                    switch mode {
                    case .transcript:
                        showingEnhancedView = false
                        showingSpeakerView = false
                    case .summary:
                        showingEnhancedView = true
                        showingSpeakerView = false
                    case .speakers:
                        showingSpeakerView = true
                        showingEnhancedView = false
                    }
                }
            }

            // Quick actions under header
            HStack(spacing: 10) {
                Button {
                    copyTranscript()
                } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)

                Button {
                    showClearConfirm = true
                } label: {
                    Label("Limpar", systemImage: "trash")
                }
                .buttonStyle(.glass)
                .tint(.red)
                .disabled(memo.text.characters.isEmpty)

                Button {
                    handleAIEnhanceButtonTap()
                } label: {
                    if isGenerating { ProgressView().controlSize(.small) } else { Label("Resumir", systemImage: "sparkles") }
                }
                .buttonStyle(.glass)
                .tint(SpokenWordTranscriber.green)
                .disabled(memo.text.characters.isEmpty || isGenerating)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        }

    @ViewBuilder
    private var viewToggleButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                showingEnhancedView.toggle()
                // Ensure only one special view is shown at a time
                if showingEnhancedView {
                    showingSpeakerView = false
                }
            }
        } label: {
            Label(
                showingEnhancedView ? "Transcrição" : "Resumo",
                systemImage: showingEnhancedView
                    ? "doc.plaintext.fill" : "sparkles.rectangle.stack.fill"
            )
        }
        .buttonStyle(.glass)
    }
    
    @ViewBuilder
    private var speakerViewToggleButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                showingSpeakerView.toggle()
                // Ensure only one special view is shown at a time
                if showingSpeakerView {
                    showingEnhancedView = false
                }
            }
        } label: {
            Label(
                showingSpeakerView ? "Transcrição" : "Falantes",
                systemImage: showingSpeakerView ? "doc.plaintext.fill" : "person.2.fill"
            )
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var speakerViewToggleButtonDisabled: some View {
        Button(action: {}) {
            Label("Falantes", systemImage: "person.2.fill")
        }
        .buttonStyle(.glass)
        .disabled(true)
        .tint(.gray.opacity(0.6))
        #if os(macOS)
            .help("Geraremos assim que houver áudio suficiente")
        #endif
    }

    @ViewBuilder
    private var enhanceButton: some View {
        Button {
            handleAIEnhanceButtonTap()
        } label: {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    memo.summary != nil ? "Reaprimorar" : "Aprimorar",
                    systemImage: memo.summary != nil ? "arrow.clockwise" : "sparkles"
                )
            }
        }
        .buttonStyle(.glass)
        .tint(SpokenWordTranscriber.green)
        .disabled(memo.text.characters.isEmpty || isGenerating)
    }

    @ViewBuilder
    var liveRecordingView: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if memo.hasSpeakerData {
                    // Quick speaker summary and timeline during live capture
                    speakerChipsInline
                    speakerTimelineBar
                        .frame(height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                let finalizedCount = speechTranscriber.finalizedTranscript.characters.count
                let volatileCount = speechTranscriber.volatileTranscript.characters.count
                let showingMic = speechTranscriber.finalizedTranscript.utf8.isEmpty && speechTranscriber.volatileTranscript.utf8.isEmpty
                let _ = Log.ui.debug("UI STATE: finalized=\(finalizedCount) volatile=\(volatileCount) showingMic=\(showingMic)")

                if speechTranscriber.finalizedTranscript.utf8.isEmpty
                    && speechTranscriber.volatileTranscript.utf8.isEmpty
                {
                    let _ = Log.ui.info("UI: Showing microphone animation (both transcripts empty)")
                    VStack(spacing: 20) {
                        // Radial mic indicator with concentric waves
                        RadialPulsingMic(isActive: isRecording)
                            .frame(width: 160, height: 160)

                        // Recording timer
                        Text(formatDuration(recordingDuration))
                            .font(.system(size: 32, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text("Ouvindo...")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text("Comece a falar no microfone")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(iOS)
                        .padding(.top, 40)
                    #else
                        .padding()
                    #endif
                } else {
                    let _ = Log.ui.info("UI: Showing transcription text (finalized=\(speechTranscriber.finalizedTranscript.characters.count) volatile=\(speechTranscriber.volatileTranscript.characters.count))")
                    VStack(alignment: .leading, spacing: 16) {
                        // Live transcript with optional precise coloring
                        let combined: AttributedString = {
                            var a = speechTranscriber.finalizedTranscript
                            a += speechTranscriber.volatileTranscript
                            return a
                        }()
                        let colored = settings.preciseColorizationEnabled ? coloredAttributedString(base: combined) : combined
                        Text(colored)
                        .font(.body)
                        .lineSpacing(4)
                        #if os(iOS)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        #else
                            .padding(20)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // Compact toolbar shown when memo is done and viewing transcript
    @ViewBuilder
    private var transcriptToolbar: some View {
        if memo.isDone && displayMode == .transcript {
            HStack(spacing: 10) {
                // Precise colorization toggle
                Button {
                    settings.setPreciseColorizationEnabled(!settings.preciseColorizationEnabled)
                } label: {
                    Label("Colorir", systemImage: settings.preciseColorizationEnabled ? "paintbrush.fill" : "paintbrush")
                }
                .buttonStyle(.glass)

                // Analytics toggle
                Button {
                    settings.setAnalyticsPanelEnabled(!settings.analyticsPanelEnabled)
                } label: {
                    Label("Analytics", systemImage: settings.analyticsPanelEnabled ? "chart.bar.fill" : "chart.bar")
                }
                .buttonStyle(.glass)

                #if os(macOS)
                    // Export transcript JSON
                    Button {
                        exportTranscriptJSON()
                    } label: {
                        Label("JSON", systemImage: "curlybraces.square")
                    }
                    .buttonStyle(.glass)

                    // Export transcript Markdown
                    Button {
                        exportTranscriptMD()
                    } label: {
                        Label("MD", systemImage: "doc.text")
                    }
                    .buttonStyle(.glass)

                    // Unified Share (combined)
                    Button { exportCombinedJSON() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.glass)
                #else
                    Menu {
                        Button("Exportar JSON", systemImage: "curlybraces.square") { iosShowExportTranscriptJSON = true }
                        Button("Exportar Markdown", systemImage: "doc.text") { iosShowExportTranscriptMD = true }
                        Button("Exportar Completo", systemImage: "square.and.arrow.up") {
                            if let data = TranscriptExport.combinedJSONData(for: memo, context: modelContext) {
                                combinedExportDoc = CombinedExportDocument(data: data)
                                iosShowCombinedExport = true
                            }
                        }
                    } label: {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                #endif

                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }

    #if os(macOS)
    private func exportTranscriptJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "transcript.json"
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.json] } else { panel.allowedFileTypes = ["json"] }
        if panel.runModal() == .OK, let url = panel.url,
           let data = TranscriptExport.jsonData(for: memo, context: modelContext) {
            try? data.write(to: url)
        }
    }
    private func exportTranscriptMD() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "transcript.md"
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.plainText] } else { panel.allowedFileTypes = ["md","txt"] }
        if panel.runModal() == .OK, let url = panel.url,
           let data = TranscriptExport.markdownData(for: memo, context: modelContext) {
            try? data.write(to: url)
        }
    }
    private func exportCombinedJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "memo_export.json"
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.json] } else { panel.allowedFileTypes = ["json"] }
        if panel.runModal() == .OK, let url = panel.url,
           let data = TranscriptExport.combinedJSONData(for: memo, context: modelContext) {
            try? data.write(to: url)
        }
    }
    #endif

    #if os(iOS)
    // Present iOS file exporter for combined export
    @ViewBuilder
    private var combinedExporter: some View {
        EmptyView()
            .fileExporter(isPresented: $iosShowCombinedExport, document: combinedExportDoc, contentType: .json, defaultFilename: "memo_export.json") { _ in }
    }
    #endif

    // Live speaker chips
    @ViewBuilder
    private var speakerChipsInline: some View {
        let speakers = memo.speakers(in: modelContext)
        if !speakers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(speakers, id: \.id) { speaker in
                        HStack(spacing: 6) {
                            Circle().fill(speaker.displayColor).frame(width: 10, height: 10)
                            Text(speaker.name).font(.caption)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    // Live speaker timeline bar based on memo.speakerSegments
    @ViewBuilder
    private var speakerTimelineBar: some View {
        let segments = memo.speakerSegments.sorted(by: { $0.startTime < $1.startTime })
        let total = segments.last?.endTime ?? (segments.first?.endTime ?? 1)
        let speakers = memo.speakers(in: modelContext)
        let colorMap: [String: Color] = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.displayColor) })
        Group {
            if segments.isEmpty { EmptyView() }
            else {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(segments, id: \.id) { seg in
                            let width = max(1, (seg.endTime - seg.startTime) / max(total, 0.001) * geo.size.width)
                            (colorMap[seg.speakerId] ?? .blue)
                                .frame(width: width)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var playbackView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                #if os(macOS)
                    Text("Transcrição")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                #endif
                let base = AttributedString(String(memo.text.characters))
                let display = settings.preciseColorizationEnabled ? coloredAttributedString(base: base) : base
                textScrollView(attributedString: display)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    #else
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    #endif
                    .textSelection(.enabled)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            floatingScrubber
        }
    }

    // MARK: - Precise coloring helper
    private func coloredAttributedString(base: AttributedString) -> AttributedString {
        guard settings.preciseColorizationEnabled, memo.hasSpeakerData else { return base }
        var copy = base
        let segs = memo.speakerSegments.sorted(by: { $0.startTime < $1.startTime })
        if segs.isEmpty { return base }
        // Map speakerId -> color
        let speakers = memo.speakers(in: modelContext)
        let colorMap = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.displayColor) })
        copy.runs.forEach { run in
            guard let tr = copy[run.range].audioTimeRange else { return }
            let mid = (tr.start.seconds + tr.end.seconds) * 0.5
            if let seg = segs.first(where: { mid >= $0.startTime && mid < $0.endTime }),
               let color = colorMap[seg.speakerId] {
                copy[run.range].foregroundColor = color
            }
        }
        return copy
    }

    private func gradient(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.95), color.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var progressView: some View {
        ProgressView(value: downloadProgress, total: 100)
            .progressViewStyle(LinearProgressViewStyle())
            .opacity(downloadProgress > 0 && downloadProgress < 100 ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: downloadProgress)
    }
}

// MARK: - Radial Mic Indicator

struct RadialPulsingMic: View {
    var isActive: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                let base = CGFloat(i + 1)
                Circle()
                    .stroke(Color.red.opacity(0.25 / base), lineWidth: 2)
                    .scaleEffect(animate ? (0.8 + base * 0.25) : (0.6 + base * 0.15))
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: animate)
            }
            Circle()
                .fill(Color.red)
                .frame(width: 18, height: 18)
                .shadow(color: .red.opacity(0.5), radius: 10, x: 0, y: 0)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
        .onAppear { if isActive { animate = true } }
        .onChange(of: isActive) { _, newVal in
            withAnimation { animate = newVal }
        }
    }
}

// MARK: - TranscriptView Extension

extension TranscriptView {

    private func syncDiarizationWithSettings() {
        diarizationManager.config = settings.diarizationConfig()
        diarizationManager.isEnabled = settings.diarizationEnabled
        diarizationManager.enableRealTimeProcessing = settings.enableRealTimeProcessing
        diarizationManager.processingWindowSeconds = settings.processingWindowSeconds
        diarizationManager.backpressureEnabled = settings.backpressureEnabled
        diarizationManager.maxLiveBufferSeconds = settings.maxLiveBufferSeconds
        diarizationManager.adaptiveWindowEnabled = settings.adaptiveWindowEnabled
    }

    @MainActor
    private func startRecordingClock(at start: Date, resetElapsed: Bool) {
        let timestamp = Date().timeIntervalSince1970
        Log.state.error("🕐 startRecordingClock CALLED at timestamp=\(timestamp, privacy: .public) start=\(start.timeIntervalSince1970, privacy: .public) resetElapsed=\(resetElapsed ? "true" : "false", privacy: .public)")

        recordingStartTime = start
        recordingTimer?.invalidate()
        if resetElapsed {
            recordingDuration = 0
            Log.state.error("🕐 Reset recordingDuration to 0")
        } else {
            recordingDuration = max(0, Date().timeIntervalSince(start))
            Log.state.error("🕐 Set recordingDuration to \(recordingDuration, privacy: .public)")
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                if let startTime = recordingStartTime {
                    let newDuration = Date().timeIntervalSince(startTime)
                    recordingDuration = newDuration
                    if Int(newDuration) % 5 == 0 && Int(newDuration * 10) % 50 == 0 {
                        Log.state.error("🕐 Timer tick: duration=\(newDuration, privacy: .public)")
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingTimer = timer
        Log.state.error("🕐 Timer created and added to RunLoop, recordingTimer is now \(recordingTimer != nil ? "not nil" : "nil", privacy: .public)")
    }

    @MainActor
    private func resumeRecordingClockIfNeeded() {
        guard isRecording, recordingTimer == nil else { return }
        guard let start = memo.activeRecordingStart ?? recordingStartTime else { return }
        startRecordingClock(at: start, resetElapsed: false)
    }

    private func showBanner(_ message: String) {
        bannerMessage = message
        bannerVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            bannerVisible = false
        }
    }

    // Format duration for display
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Floating Scrubber
    @ViewBuilder
    private var floatingScrubber: some View {
        let duration = max(totalDuration, memo.duration ?? 0, memo.speakerSegments.last?.endTime ?? 0)
        if memo.isDone && duration > 0 {
            HStack(spacing: 8) {
                Text(formatDuration(currentPlaybackTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { min(max(0, currentPlaybackTime), duration) },
                        set: { newVal in
                            isScrubbing = true
                            currentPlaybackTime = newVal
                        }
                    ), in: 0...duration)
                    .frame(width: 240)
                    if settings.waveformEnabled {
                        Canvas { ctx, size in
                            guard !waveform.isEmpty else { return }
                            let samples = waveform
                            let barW = max(1, size.width / CGFloat(max(1, samples.count)))
                            let mid = size.height / 2
                            var path = Path()
                            for (i, amp) in samples.enumerated() {
                                let x = CGFloat(i) * barW
                                let h = CGFloat(amp) * mid
                                path.addRoundedRect(in: CGRect(x: x, y: mid - h, width: barW * 0.9, height: max(1, h * 2)), cornerSize: CGSize(width: 1.5, height: 1.5))
                            }
                            ctx.fill(path, with: .linearGradient(
                                Gradient(colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.12)]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: 0, y: size.height)
                            ))
                            // Playback cursor
                            let cursorX = CGFloat((duration > 0 ? currentPlaybackTime / duration : 0)) * size.width
                            let line = Path(CGRect(x: cursorX, y: 0, width: 1.5, height: size.height))
                            ctx.fill(line, with: .color(Color.mint.opacity(0.8)))
                        }
                        .frame(width: 240, height: 28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                Text(formatDuration(duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await recorder?.seek(to: currentPlaybackTime, play: isPlaying) }
                    isScrubbing = false
                } label: { Image(systemName: "gobackward") }
                .buttonStyle(.glass)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.trailing, 16)
            .padding(.bottom, 12)
            .onAppear {
                totalDuration = recorder?.recordingDuration() ?? (memo.duration ?? 0)
            }
        }
    }

    func handlePlayback() {
        guard memo.url != nil else {
            return
        }

        if isPlaying {
            Task {
                await recorder?.playRecording()
            }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak recorder] _ in
                DispatchQueue.main.async {
                    if let node = recorder?.playerNode, node.engine != nil {
                        currentPlaybackTime = node.currentTime
                    } else {
                        timer?.invalidate()
                        timer = nil
                        currentPlaybackTime = 0.0
                    }
                }
            }
        } else {
            // Invalidate timer first to avoid reading detached nodes during teardown
            timer?.invalidate()
            timer = nil
            Task { await recorder?.stopPlaying() }
            currentPlaybackTime = 0.0
        }
    }

    func handleRecordingButtonTap() {
        print("DEPURAÇÃO [TranscriptView]: Botão de gravação pressionado - estado atual: \(isRecording)")
        // Avoid re-entrancy while a transition is in progress
        if isTransitioningRecordingState {
            print("DEPURAÇÃO [TranscriptView]: Ignorando toque: transição em andamento")
            return
        }
        // Prevent accidental early stop (e.g., stray keypress) within a short grace window only
        if isRecording, let until = minStopUntil, Date() < until {
            print("DEPURAÇÃO [TranscriptView]: Ignorando parada precoce dentro da janela de proteção")
            showBanner("Aguarde \(String(format: "%.1f", until.timeIntervalSinceNow))s para parar")
            return
        }
        // Remove early-stop confirmation entirely; rely only on minStopUntil guard
        // If recording and within the initial grace window, ignore the stop tap
        if isRecording { /* no-op: handled by minStopUntil above */ }

        // Detect corrupted recording state (isRecording=true but no timer running)
        if isRecording && recordingTimer == nil {
            Log.state.error("⚠️ Corrupted recording state detected in button tap - forcing cleanup")
            print("DEPURAÇÃO [TranscriptView]: Estado corrompido detectado (isRecording=true, timer=nil) - limpando")
            isRecording = false
            isTransitioningRecordingState = false
            expectedStop = true
            memo.activeRecordingStart = nil
            recordingStartTime = nil
            recordingDuration = 0
            showBanner("Estado de gravação inconsistente foi corrigido")
            return
        }

        isRecording.toggle()
        print("DEPURAÇÃO [TranscriptView]: Estado de gravação alternado para: \(isRecording)")
    }

    func handlePlayButtonTap() {
        isPlaying.toggle()
    }

    func handleAIEnhanceButtonTap() {
        Task {
            await generateAIEnhancements()
        }
    }

    private func copyTranscript() {
        let text = String(memo.text.characters)
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }

    private func clearTranscript() {
        // Stop playback if needed
        isPlaying = false
        Task { await recorder?.stopPlaying() }
        // Delete persisted segments and reset memo fields
        for seg in memo.speakerSegments { modelContext.delete(seg) }
        memo.speakerSegments.removeAll()
        memo.hasSpeakerData = false
        memo.summary = nil
        memo.text = AttributedString("")
    }

    private func saveSpeakerAsKnown(_ speaker: Speaker) {
        // Fuse embeddings across this memo's segments for the target speaker according to Settings
        let segs = memo.speakerSegments.filter { $0.speakerId == speaker.id }
        let items: [(emb: [Float], dur: Float)] = segs.compactMap { seg in
            if let e = seg.embedding, !e.isEmpty { return (e, Float(seg.duration)) }
            return nil
        }
        guard !items.isEmpty else { return }
        let length = items.first!.emb.count
        let compatible = items.filter { $0.emb.count == length }
        guard !compatible.isEmpty else { return }
        var fused = Array(repeating: 0 as Float, count: length)
        switch settings.embeddingFusionMethod {
        case .simpleAverage:
            for (emb, _) in compatible { for i in 0..<length { fused[i] += emb[i] } }
            for i in 0..<length { fused[i] /= Float(compatible.count) }
        case .durationWeighted:
            let totalW = compatible.reduce(0 as Float) { $0 + max(0.001, $1.dur) }
            for (emb, dur) in compatible {
                let w = max(0.001, dur) / totalW
                for i in 0..<length { fused[i] += emb[i] * w }
            }
        }
        speaker.embedding = fused
        diarizationManager.upsertRuntimeSpeaker(id: speaker.id, embedding: fused, duration: Float(segs.reduce(0.0) { $0 + $1.duration }))
    }

    @MainActor
    private func applyLiveDiarizationResult(_ result: DiarizationResult) {
        memo.updateWithDiarizationResult(result, in: modelContext)
    }

    // Reinitialize transcriber/recorder when switching to a different memo instance
    @MainActor
    private func reinitializeForNewMemo() async {
        // Don't reinitialize if we're actively starting a recording or in transition
        // This prevents auto-record from being interrupted by memo selection changes
        // BUT: if isRecording=true but no timer is running, this is a corrupted state - force cleanup
        let isActuallyRecording = isRecording && recordingTimer != nil

        if (isTransitioningRecordingState || isActuallyRecording) {
            Log.state.info("TranscriptView: Skipping reinitializeForNewMemo - recording is active (isRecording=\(isRecording), isTransitioning=\(isTransitioningRecordingState))")
            return
        }

        // Detect and log corrupted state cleanup
        if isRecording && recordingTimer == nil {
            Log.state.warning("⚠️ Detected corrupted recording state (isRecording=true but no timer) - forcing cleanup")
        }

        Log.state.info("TranscriptView: Reinitializing for new memo")
        // Ensure existing recorder is stopped and engines are torn down
        let task = recordTask
        recordTask = nil
        await recorder?.teardown()
        await task?.value

        recordingTimer?.invalidate(); recordingTimer = nil
        timer?.invalidate(); timer = nil
        isRecording = false
        isPlaying = false
        isTransitioningRecordingState = false
        expectedStop = true
        memo.activeRecordingStart = nil
        recordingStartTime = nil
        recordingDuration = 0

        // Best effort: finish any ongoing recognition and reset for the new memo
        try? await speechTranscriber.finishTranscribing()
        speechTranscriber.reset()

        recorder = Recorder(
            transcriber: speechTranscriber,
            memo: memo,
            diarizationManager: diarizationManager,
            modelContext: modelContext
        )

        if settings.waveformEnabled, let url = memo.url {
            waveform = WaveformGenerator.generate(from: url, desiredSamples: 600)
        } else {
            waveform = []
        }
        displayMode = memo.summary != nil ? .summary : .transcript
    }

    @MainActor
    private func generateAIEnhancements() async {
        isGenerating = true
        enhancementError = nil

        do {
            // Safety net: avoid calling generator when there is no content
            let raw = String(memo.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                isGenerating = false
                return
            }
            try await memo.generateAIEnhancements()
            // Automatically show the enhanced view after successful generation
            withAnimation(.smooth(duration: 0.3)) {
                showingEnhancedView = true
            }
        } catch let fmError as FoundationModelsError {
            // Swallow "No content to enhance" errors to avoid noisy alerts on empty/new memos
            switch fmError {
            case .generationFailed(let nsError as NSError) where nsError.code == -2 || nsError.domain == "No content to enhance":
                enhancementError = nil
            default:
                enhancementError = fmError.localizedDescription
            }
        } catch {
            enhancementError = "Não foi possível gerar aprimoramentos de IA: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    @MainActor
    private func generateTitleIfNeeded() async {
        // Only generate title if we have content and the current title is generic
        guard !memo.text.characters.isEmpty,
            memo.title == "Novo Memorando" || memo.title.isEmpty
        else {
            return
        }

        do {
            let suggestedTitle = try await memo.suggestedTitle() ?? memo.title
            memo.title = suggestedTitle
        } catch {
            print("Erro ao gerar título: \(error)")
            // Keep the existing title if generation fails
        }
    }

    @ViewBuilder func textScrollView(attributedString: AttributedString) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                textWithHighlighting(attributedString: attributedString)
                Spacer()
            }
        }
    }

    func attributedStringWithCurrentValueHighlighted(attributedString: AttributedString)
        -> AttributedString
    {
        var copy = attributedString
        copy.runs.forEach { run in
            if shouldBeHighlighted(attributedStringRun: run) {
                let range = run.range
                copy[range].backgroundColor = .mint.opacity(0.2)
            }
        }
        return copy
    }

    func shouldBeHighlighted(attributedStringRun: AttributedString.Runs.Run) -> Bool {
        guard isPlaying || isScrubbing else { return false }
        let start = attributedStringRun.audioTimeRange?.start.seconds
        let end = attributedStringRun.audioTimeRange?.end.seconds
        guard let start, let end else {
            return false
        }

        if end < currentPlaybackTime { return false }

        if start < currentPlaybackTime, currentPlaybackTime < end {
            return true
        }

        return false
    }

    @ViewBuilder func textWithHighlighting(attributedString: AttributedString) -> some View {
        Group {
            Text(attributedStringWithCurrentValueHighlighted(attributedString: attributedString))
                .font(.body)
        }
    }
}

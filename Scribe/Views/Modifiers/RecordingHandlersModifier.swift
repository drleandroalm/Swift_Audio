import SwiftUI
import SwiftData
import AVFoundation
import os

struct RecordingHandlersModifier: ViewModifier {
    // Core dependencies are provided as closures to keep this type lightweight.
    let onRecordingChange: (_ old: Bool, _ new: Bool) -> Void
    let onPlayingChange: () -> Void
    let onMemoURLChange: (_ url: URL?) -> Void
    let onFirstBuffer: () -> Void
    let onFirstStream: () -> Void
    let onRecorderStop: (_ cause: String?) -> Void
    let onBackpressure: (_ liveSeconds: Double, _ consecutiveDrops: Int) -> Void
    let onMemoIdChange: () -> Void
    let onAppear: () -> Void
    let onTask: () -> Void
    let onDisappear: () -> Void
    // Alerts
    @Binding var enhancementError: String?
    @Binding var showClearConfirm: Bool
    let onClearConfirmed: () -> Void

    @Binding var isRecording: Bool
    @Binding var isPlaying: Bool
    let memoId: PersistentIdentifier
    let memoURL: URL?

    func body(content: Content) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .recordingStateChanged)) { notification in
            let timestamp = Date().timeIntervalSince1970
            Log.state.info("RecordingHandlersModifier: Notification RECEIVED at timestamp=\(timestamp, privacy: .public)")
            guard let oldValue = notification.userInfo?["oldValue"] as? Bool,
                  let newValue = notification.userInfo?["newValue"] as? Bool else {
                Log.state.error("RecordingHandlersModifier: Invalid notification userInfo - keys=\(notification.userInfo?.keys.map { $0.description }.joined(separator: ", ") ?? "nil", privacy: .public)")
                return
            }
            Log.state.info("RecordingHandlersModifier: onReceive triggered at timestamp=\(timestamp, privacy: .public) - old=\(oldValue ? "true" : "false", privacy: .public) new=\(newValue ? "true" : "false", privacy: .public)")
            Log.state.info("RecordingHandlersModifier: Calling onRecordingChange callback...")
            onRecordingChange(oldValue, newValue)
            Log.state.info("RecordingHandlersModifier: onRecordingChange callback completed")
        }
        .onChange(of: isPlaying) {
            onPlayingChange()
        }
        .onChange(of: memoURL) { _, newURL in
            onMemoURLChange(newURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: Recorder.firstBufferNotification)) { _ in
            onFirstBuffer()
        }
        .onReceive(NotificationCenter.default.publisher(for: SpokenWordTranscriber.firstStreamNotification)) { _ in
            onFirstStream()
        }
        .onReceive(NotificationCenter.default.publisher(for: Recorder.didStopWithCauseNotification)) { notif in
            onRecorderStop(notif.userInfo?["cause"] as? String)
        }
        .onReceive(NotificationCenter.default.publisher(for: DiarizationManager.backpressureNotification)) { notif in
            let live = notif.userInfo?["liveSeconds"] as? Double ?? .nan
            let drops = notif.userInfo?["consecutive"] as? Int ?? 0
            if live.isFinite { onBackpressure(live, drops) }
        }
        .onChange(of: memoId) { _, _ in
            onMemoIdChange()
        }
        .task(id: memoId) {
            // Run once per unique memo.id to prevent redundant initialization
            onAppear()
        }
        .task {
            onTask()
        }
        .onDisappear {
            onDisappear()
        }
        .alert("Erro de aprimoramento", isPresented: Binding<Bool>(
            get: { enhancementError != nil },
            set: { if !$0 { enhancementError = nil } }
        )) {
            Button("OK") { enhancementError = nil }
        } message: {
            if let msg = enhancementError { Text(msg) }
        }
        .alert("Limpar transcrição?", isPresented: $showClearConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Limpar", role: .destructive) { onClearConfirmed() }
        } message: {
            Text("Isso removerá o texto, o resumo e os segmentos de falantes.")
        }
    }
}

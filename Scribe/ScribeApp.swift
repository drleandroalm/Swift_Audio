import SwiftData
import SwiftUI
import os
import AVFoundation
#if os(macOS)
import AppKit
#endif

@main
struct SwiftTranscriptionSampleApp: App {
    init() {
        Log.state.info("ScribeApp: Inicializando aplicativo")

        // Check and request microphone permissions
        checkMicrophonePermissions()

        // Preload ML models off-main to avoid cold-start hitches during recording
        ModelWarmupService.shared.warmupIfNeeded()

        #if DEBUG && os(macOS)
        // Activate app when launching from command line with SS_AUTO_RECORD
        if ProcessInfo.processInfo.environment["SS_AUTO_RECORD"] == "1" {
            Log.state.info("ScribeApp: SS_AUTO_RECORD detectado, ativando aplicativo")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                Log.state.info("ScribeApp: Aplicativo ativado")
            }
        }
        #endif
    }
    @State private var settings = AppSettings()
    @State private var diarizationManager = DiarizationManager()

    /// Check microphone permission status and request if needed
    private func checkMicrophonePermissions() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.state.info("ScribeApp: Microphone permission status = \(String(describing: status), privacy: .public)")

        switch status {
        case .authorized:
            Log.state.info("ScribeApp: Microphone access authorized")
        case .notDetermined:
            Log.state.info("ScribeApp: Requesting microphone access")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Log.state.info("ScribeApp: Microphone access \(granted ? "granted" : "denied", privacy: .public)")
            }
        case .denied, .restricted:
            Log.state.warning("ScribeApp: Microphone access denied or restricted")
        @unknown default:
            Log.state.error("ScribeApp: Unknown microphone permission status")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(diarizationManager)
                .preferredColorScheme(settings.colorScheme)
                .onOpenURL { url in
                    #if os(macOS)
                    if settings.allowURLRecordTrigger, url.scheme?.lowercased() == "swiftscribe" {
                        if url.host?.lowercased() == "record" || url.path.lowercased().contains("record") {
                            NotificationCenter.default.post(name: Notification.Name("SSTriggerRecordFromURL"), object: nil)
                        }
                    }
                    #endif
                }
                .task {
                    // Ensure warmup before any recording UI becomes enabled
                    ModelWarmupService.shared.warmupIfNeeded()
                }
        }
        .modelContainer(for: [Memo.self, Speaker.self, SpeakerSegment.self])

        #if os(macOS)
            Settings {
                SettingsView(settings: settings)
            }
        #endif
    }
}

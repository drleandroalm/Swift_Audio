import Foundation
#if os(iOS)
import AVFAudio
#endif

import os

enum MicrophoneSelector {
    struct Device: Identifiable, Equatable {
        let id: String   // macOS: AudioDeviceID string; iOS: AVAudioSessionPortDescription.uid
        let name: String
    }

    // Apply selection based on settings. On macOS, this may attempt to change default system input.
    static func applySelectionIfNeeded(_ settings: AppSettings) {
        #if os(macOS)
        if settings.micManualOverrideEnabled, let idStr = settings.micSelectedDeviceId, let id = UInt32(idStr) {
            Logger(subsystem: "com.swift.examples.scribe", category: "AudioPipeline").info("Mic override enabled; selecting device id=\(idStr, privacy: .public)")
            AudioDeviceManager.setDefaultInput(id)
        } else {
            // Smart selection: mimic current system default; if absent, prefer built-in
            Logger(subsystem: "com.swift.examples.scribe", category: "AudioPipeline").info("Mic override disabled; selecting built-in/default input")
            AudioDeviceManager.selectBuiltInMicIfAvailable()
        }
        #else
        let session = AVAudioSession.sharedInstance()
        if settings.micManualOverrideEnabled, let uid = settings.micSelectedDeviceId,
           let inputs = session.availableInputs,
           let target = inputs.first(where: { $0.uid == uid }) {
            Logger(subsystem: "com.swift.examples.scribe", category: "AudioPipeline").info("Mic override enabled; selecting input uid=\(uid, privacy: .public) name=\(target.portName, privacy: .public)")
            try? session.setPreferredInput(target)
        } else {
            // Clear any preferred override to follow system route management
            Logger(subsystem: "com.swift.examples.scribe", category: "AudioPipeline").info("Mic override disabled; clearing preferred input to follow system route")
            try? session.setPreferredInput(nil)
        }
        #endif
    }

    // Enumerate devices for UI pickers
    static func availableDevices() -> [Device] {
        #if os(macOS)
        return AudioDeviceManager.availableInputDevices().map { Device(id: String($0.id), name: $0.name) }
        #else
        let session = AVAudioSession.sharedInstance()
        return (session.availableInputs ?? []).map { Device(id: $0.uid, name: $0.portName) }
        #endif
    }

    static func currentDeviceName() -> String? {
        #if os(macOS)
        return AudioDeviceManager.currentDefaultInput()?.name
        #else
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.inputs.first?.portName
        #endif
    }
}

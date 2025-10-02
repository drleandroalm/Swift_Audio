import Foundation
#if os(macOS)
import CoreAudio
import os

struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let name: String
}

enum AudioDeviceManager {
    // MARK: - Device Enumeration / Selection
    static func availableInputDevices() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize)
        guard status == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }

        var results: [AudioInputDevice] = []
        for dev in deviceIDs {
            var inputAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfgSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(dev, &inputAddr, 0, nil, &cfgSize) != noErr || cfgSize == 0 { continue }
            let bufListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(cfgSize))
            defer { bufListPtr.deallocate() }
            if AudioObjectGetPropertyData(dev, &inputAddr, 0, nil, &cfgSize, bufListPtr) != noErr { continue }
            let abl = UnsafeMutableAudioBufferListPointer(bufListPtr)
            let totalChannels = abl.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard totalChannels > 0 else { continue }

            // Name
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(dev, &nameAddr, 0, nil, &nameSize, &name) != noErr { continue }

            results.append(AudioInputDevice(id: dev, name: name as String))
        }
        return results
    }

    static func currentDefaultInput() -> AudioInputDevice? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        let list = availableInputDevices()
        return list.first(where: { $0.id == dev })
    }

    static func setDefaultInput(_ deviceID: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &dev)
        if status != noErr {
            print("[AudioDeviceManager] Failed to set default input, status=\(status)")
        }
    }

    static func selectBuiltInMicIfAvailable() {
        let devices = availableInputDevices()
        guard !devices.isEmpty else { return }
        if let current = currentDefaultInput() {
            print("[AudioDeviceManager] Current input: \(current.name)")
            if current.name.localizedCaseInsensitiveContains("built-in") || current.name.localizedCaseInsensitiveContains("interno") {
                return
            }
        }
        if let builtin = devices.first(where: { $0.name.localizedCaseInsensitiveContains("built-in") || $0.name.localizedCaseInsensitiveContains("interno") || $0.name.localizedCaseInsensitiveContains("microfone") }) {
            print("[AudioDeviceManager] Switching default input to: \(builtin.name)")
            setDefaultInput(builtin.id)
        }
    }

    // MARK: - Default Input Change Monitoring
    @MainActor private static var monitoring: Bool = false
    @MainActor private static var callbacks = [UUID: (AudioInputDevice?) -> Void]()
    @MainActor private static var listenerAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    @discardableResult
    @MainActor static func addDefaultInputObserver(_ cb: @escaping (AudioInputDevice?) -> Void) -> UUID {
        let id = UUID()
        callbacks[id] = cb
        startDefaultInputMonitoring()
        return id
    }

    @MainActor static func removeDefaultInputObserver(_ id: UUID) {
        callbacks.removeValue(forKey: id)
        if callbacks.isEmpty {
            stopDefaultInputMonitoring()
        }
    }

    @MainActor static func startDefaultInputMonitoring() {
        guard !monitoring else { return }
        var addr = listenerAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main
        ) { _, _ in
            let dev = currentDefaultInput()
            Logger(subsystem: "com.swift.examples.scribe", category: "AudioPipeline").notice("Default input changed → \(dev?.name ?? "<unknown>", privacy: .public)")
            for cb in callbacks.values { cb(dev) }
        }
        if status == noErr { monitoring = true } else {
            Logger(subsystem: "com.swift.examples.scribe", category: "AudioPipeline").error("Failed to start default input monitoring, status=\(status)")
        }
    }

    @MainActor static func stopDefaultInputMonitoring() {
        guard monitoring else { return }
        var addr = listenerAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main,
            { _, _ in }
        )
        monitoring = false
    }
}
#endif

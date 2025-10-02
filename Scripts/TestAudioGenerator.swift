#!/usr/bin/env swift

import AVFoundation
import Foundation

/// Comprehensive test audio generator with various durations and scenarios
/// Includes short (10s), medium (60s, 120s), and long (240s) samples for stress testing

print("🎵 Swift Scribe Test Audio Generator")
print("=" * 60)

let baseDir = "Audio_Files_Tests/TestSuite"
let sampleRate: Double = 16000.0

// MARK: - Audio Utilities

extension String {
    static func * (left: String, right: Int) -> String {
        String(repeating: left, count: right)
    }
}

func createFormat() -> AVAudioFormat? {
    AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )
}

func createBuffer(duration: Double) -> AVAudioPCMBuffer? {
    guard let format = createFormat() else { return nil }
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    buffer?.frameLength = frameCount
    return buffer
}

func generateSine(frequency: Double, duration: Double, amplitude: Float = 0.5, modulation: Double = 0.0) -> AVAudioPCMBuffer? {
    guard let buffer = createBuffer(duration: duration),
          let data = buffer.floatChannelData else { return nil }

    let twoPi = 2.0 * Double.pi
    for frame in 0..<Int(buffer.frameLength) {
        let t = Double(frame) / sampleRate
        var sample = Float(sin(twoPi * frequency * t))

        if modulation > 0 {
            let envelope = Float(1.0 + modulation * sin(twoPi * 5.0 * t))
            sample *= envelope
        }

        data[0][frame] = sample * amplitude
    }

    return buffer
}

func mixBuffers(_ buffers: [(AVAudioPCMBuffer, Float)]) -> AVAudioPCMBuffer? {
    guard !buffers.isEmpty,
          let first = buffers.first?.0,
          let mixed = createBuffer(duration: Double(first.frameLength) / sampleRate),
          let mixedData = mixed.floatChannelData else { return nil }

    for (buffer, weight) in buffers {
        guard let bufferData = buffer.floatChannelData else { continue }
        for frame in 0..<min(Int(buffer.frameLength), Int(mixed.frameLength)) {
            mixedData[0][frame] += bufferData[0][frame] * weight
        }
    }

    return mixed
}

func writeAudio(_ buffer: AVAudioPCMBuffer, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let file = try AVAudioFile(
        forWriting: url,
        settings: buffer.format.settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
    let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64 ?? 0
    let sizeMB = Double(size) / 1_048_576.0
    print(String(format: "  ✅ %@ (%.1fs, %.2f MB)", url.lastPathComponent, Double(buffer.frameLength) / sampleRate, sizeMB))
}

// MARK: - Test Sample Generation

print("\n📁 Creating test samples...")

// 1. Single Speaker (10s baseline)
print("\n[1/5] Single Speaker Samples (10s)")
if let clean = generateSine(frequency: 200, duration: 10, modulation: 0.3) {
    try writeAudio(clean, to: "\(baseDir)/single_speaker/clean_speech_10s.wav")
}

if let noisy = generateSine(frequency: 200, duration: 10, modulation: 0.3),
   let noise = generateSine(frequency: 8000, duration: 10, amplitude: 0.1) {
    if let mixed = mixBuffers([(noisy, 1.0), (noise, 0.2)]) {
        try writeAudio(mixed, to: "\(baseDir)/single_speaker/noisy_speech_10s.wav")
    }
}

if let whisper = generateSine(frequency: 200, duration: 10, amplitude: 0.2, modulation: 0.3) {
    try writeAudio(whisper, to: "\(baseDir)/single_speaker/whisper_speech_10s.wav")
}

if let rapid = generateSine(frequency: 250, duration: 10, modulation: 0.5) {
    try writeAudio(rapid, to: "\(baseDir)/single_speaker/rapid_speech_10s.wav")
}

// 2. Multi-Speaker (30s baseline)
print("\n[2/5] Multi-Speaker Samples (30s)")
// Two speakers alternating
if let s1 = generateSine(frequency: 180, duration: 15, modulation: 0.3),
   let s2 = generateSine(frequency: 220, duration: 15, modulation: 0.3) {
    // Create sequential speakers
    guard let combined = createBuffer(duration: 30),
          let combinedData = combined.floatChannelData,
          let s1Data = s1.floatChannelData,
          let s2Data = s2.floatChannelData else { fatalError() }

    for i in 0..<Int(s1.frameLength) {
        combinedData[0][i] = s1Data[0][i]
    }
    for i in 0..<Int(s2.frameLength) {
        combinedData[0][Int(s1.frameLength) + i] = s2Data[0][i]
    }

    try writeAudio(combined, to: "\(baseDir)/multi_speaker/two_speakers_turn_taking.wav")
}

// Overlapping speech
if let s1 = generateSine(frequency: 180, duration: 30, modulation: 0.3),
   let s2 = generateSine(frequency: 220, duration: 30, modulation: 0.3),
   let mixed = mixBuffers([(s1, 0.5), (s2, 0.5)]) {
    try writeAudio(mixed, to: "\(baseDir)/multi_speaker/two_speakers_overlap.wav")
}

// Three speakers
if let s1 = generateSine(frequency: 180, duration: 10, modulation: 0.3),
   let s2 = generateSine(frequency: 220, duration: 10, modulation: 0.3),
   let s3 = generateSine(frequency: 260, duration: 10, modulation: 0.3) {
    guard let combined = createBuffer(duration: 30),
          let combinedData = combined.floatChannelData else { fatalError() }

    let s1Data = s1.floatChannelData![0]
    let s2Data = s2.floatChannelData![0]
    let s3Data = s3.floatChannelData![0]

    for i in 0..<Int(s1.frameLength) {
        combinedData[0][i] = s1Data[i]
        combinedData[0][Int(s1.frameLength) + i] = s2Data[i]
        combinedData[0][Int(s1.frameLength) * 2 + i] = s3Data[i]
    }

    try writeAudio(combined, to: "\(baseDir)/multi_speaker/three_speakers_meeting.wav")
}

// 3. Edge Cases
print("\n[3/5] Edge Case Samples")
if let silence = createBuffer(duration: 10) {
    try writeAudio(silence, to: "\(baseDir)/edge_cases/silence_10s.wav")
}

if let tone = generateSine(frequency: 440, duration: 10) {
    try writeAudio(tone, to: "\(baseDir)/edge_cases/tone_440hz_10s.wav")
}

if let truncated = generateSine(frequency: 200, duration: 5, modulation: 0.3) {
    try writeAudio(truncated, to: "\(baseDir)/edge_cases/truncated_buffer.wav")
}

// 4. STRESS TESTS - Long Duration Samples (60s, 120s, 240s)
print("\n[4/5] Stress Test Samples (Long Duration)")

// 60s single speaker
if let long60 = generateSine(frequency: 200, duration: 60, modulation: 0.3) {
    try writeAudio(long60, to: "\(baseDir)/stress_tests/single_speaker_60s.wav")
}

// 120s two speakers alternating (60s each)
if let s1 = generateSine(frequency: 180, duration: 60, modulation: 0.3),
   let s2 = generateSine(frequency: 220, duration: 60, modulation: 0.3) {
    guard let combined = createBuffer(duration: 120),
          let combinedData = combined.floatChannelData else { fatalError() }

    let s1Data = s1.floatChannelData![0]
    let s2Data = s2.floatChannelData![0]

    for i in 0..<Int(s1.frameLength) {
        combinedData[0][i] = s1Data[i]
        combinedData[0][Int(s1.frameLength) + i] = s2Data[i]
    }

    try writeAudio(combined, to: "\(baseDir)/stress_tests/two_speakers_120s.wav")
}

// 240s multi-speaker meeting (3 speakers, 80s each)
if let s1 = generateSine(frequency: 180, duration: 80, modulation: 0.3),
   let s2 = generateSine(frequency: 220, duration: 80, modulation: 0.3),
   let s3 = generateSine(frequency: 260, duration: 80, modulation: 0.3) {
    guard let combined = createBuffer(duration: 240),
          let combinedData = combined.floatChannelData else { fatalError() }

    let s1Data = s1.floatChannelData![0]
    let s2Data = s2.floatChannelData![0]
    let s3Data = s3.floatChannelData![0]

    let segmentFrames = Int(s1.frameLength)
    for i in 0..<segmentFrames {
        combinedData[0][i] = s1Data[i]
        combinedData[0][segmentFrames + i] = s2Data[i]
        combinedData[0][segmentFrames * 2 + i] = s3Data[i]
    }

    try writeAudio(combined, to: "\(baseDir)/stress_tests/three_speakers_240s.wav")
}

// 5. Generate Checksums
print("\n[5/5] Generating Checksums")
let result = try? Foundation.Process.run(
    URL(fileURLWithPath: "/usr/bin/env"),
    arguments: ["bash", "-c", "cd \(baseDir) && shasum -a 256 */*.wav > golden_outputs/checksums.sha256"]
)
print("  ✅ checksums.sha256")

print("\n" + "=" * 60)
print("✨ Generation Complete!")
print("\n📊 Summary:")
print("   • Single speaker (10s): 4 samples")
print("   • Multi-speaker (30s): 3 samples")
print("   • Edge cases: 3 samples")
print("   • Stress tests (60s/120s/240s): 3 samples")
print("   • Total: 13 audio samples")
print("\n📂 Location: \(baseDir)/")

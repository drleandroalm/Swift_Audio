#!/usr/bin/env swift

import AVFoundation
import Foundation

// MARK: - Audio Generation

struct AudioGenerator {
    static let sampleRate: Double = 16000.0
    static let channelCount: UInt32 = 1

    /// Generate clean speech simulation (sine wave with speech-like modulation)
    static func generateCleanSpeech(duration: Double) -> AVAudioPCMBuffer? {
        return generateTone(frequency: 200, duration: duration, modulation: 0.3)
    }

    /// Generate noisy speech (clean speech + white noise)
    static func generateNoisySpeech(duration: Double, snr: Float = 10.0) -> AVAudioPCMBuffer? {
        guard let clean = generateCleanSpeech(duration: duration),
              let noise = generateWhiteNoise(duration: duration) else {
            return nil
        }
        return mixBuffers(clean, noise, ratio: snr / 100.0)
    }

    /// Generate whisper speech (low amplitude)
    static func generateWhisperSpeech(duration: Double) -> AVAudioPCMBuffer? {
        guard let speech = generateCleanSpeech(duration: duration) else { return nil }
        return scaleAmplitude(speech, factor: 0.2)
    }

    /// Generate rapid speech (higher frequency modulation)
    static func generateRapidSpeech(duration: Double) -> AVAudioPCMBuffer? {
        return generateTone(frequency: 250, duration: duration, modulation: 0.5)
    }

    /// Generate two speakers taking turns
    static func generateTwoSpeakersTurnTaking(duration: Double) -> AVAudioPCMBuffer? {
        guard let speaker1 = generateTone(frequency: 180, duration: duration / 2, modulation: 0.3),
              let speaker2 = generateTone(frequency: 220, duration: duration / 2, modulation: 0.3) else {
            return nil
        }
        return concatenateBuffers([speaker1, speaker2])
    }

    /// Generate overlapping speech
    static func generateOverlappingSpeech(duration: Double) -> AVAudioPCMBuffer? {
        guard let speaker1 = generateTone(frequency: 180, duration: duration, modulation: 0.3),
              let speaker2 = generateTone(frequency: 220, duration: duration, modulation: 0.3) else {
            return nil
        }
        return mixBuffers(speaker1, speaker2, ratio: 0.5)
    }

    /// Generate three speakers meeting
    static func generateThreeSpeakers(duration: Double) -> AVAudioPCMBuffer? {
        let segmentDuration = duration / 3
        guard let s1 = generateTone(frequency: 180, duration: segmentDuration, modulation: 0.3),
              let s2 = generateTone(frequency: 220, duration: segmentDuration, modulation: 0.3),
              let s3 = generateTone(frequency: 260, duration: segmentDuration, modulation: 0.3) else {
            return nil
        }
        return concatenateBuffers([s1, s2, s3])
    }

    /// Generate silence
    static func generateSilence(duration: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else { return nil }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        // Zero-filled by default
        return buffer
    }

    /// Generate pure tone (sine wave)
    static func generateTone(frequency: Double, duration: Double, modulation: Double = 0.0) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else { return nil }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = frameCount

        let twoPi = 2.0 * Double.pi
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            // Base sine wave
            var sample = Float(sin(twoPi * frequency * t))

            // Add speech-like amplitude modulation
            if modulation > 0 {
                let modFreq = 5.0 // 5 Hz modulation (syllable-like)
                let envelope = Float(1.0 + modulation * sin(twoPi * modFreq * t))
                sample *= envelope
            }

            channelData[0][frame] = sample * 0.5 // Scale to prevent clipping
        }

        return buffer
    }

    /// Generate white noise
    static func generateWhiteNoise(duration: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else { return nil }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            channelData[0][frame] = Float.random(in: -0.3...0.3)
        }

        return buffer
    }

    /// Mix two buffers
    static func mixBuffers(_ buffer1: AVAudioPCMBuffer, _ buffer2: AVAudioPCMBuffer, ratio: Float) -> AVAudioPCMBuffer? {
        guard buffer1.format == buffer2.format,
              let channelData1 = buffer1.floatChannelData,
              let channelData2 = buffer2.floatChannelData,
              let mixed = AVAudioPCMBuffer(pcmFormat: buffer1.format, frameCapacity: buffer1.frameCapacity),
              let mixedData = mixed.floatChannelData else {
            return nil
        }

        let frameCount = min(buffer1.frameLength, buffer2.frameLength)
        mixed.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            mixedData[0][frame] = channelData1[0][frame] * (1.0 - ratio) + channelData2[0][frame] * ratio
        }

        return mixed
    }

    /// Scale amplitude
    static func scaleAmplitude(_ buffer: AVAudioPCMBuffer, factor: Float) -> AVAudioPCMBuffer? {
        guard let channelData = buffer.floatChannelData,
              let scaled = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity),
              let scaledData = scaled.floatChannelData else {
            return nil
        }

        scaled.frameLength = buffer.frameLength

        for frame in 0..<Int(buffer.frameLength) {
            scaledData[0][frame] = channelData[0][frame] * factor
        }

        return scaled
    }

    /// Concatenate buffers
    static func concatenateBuffers(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard !buffers.isEmpty else { return nil }

        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard let combined = AVAudioPCMBuffer(
            pcmFormat: buffers[0].format,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ), let combinedData = combined.floatChannelData else {
            return nil
        }

        var offset = 0
        for buffer in buffers {
            guard let bufferData = buffer.floatChannelData else { continue }
            for frame in 0..<Int(buffer.frameLength) {
                combinedData[0][offset + frame] = bufferData[0][frame]
            }
            offset += Int(buffer.frameLength)
        }

        combined.frameLength = AVAudioFrameCount(totalFrames)
        return combined
    }
}

// MARK: - File Writing

func writeBuffer(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
    let file = try AVAudioFile(
        forWriting: url,
        settings: buffer.format.settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
    print("✅ Generated: \(url.lastPathComponent) (\(buffer.frameLength) frames, \(String(format: "%.1f", Double(buffer.frameLength) / 16000.0))s)")
}

// MARK: - Main

let baseDir = "Audio_Files_Tests/TestSuite"

// Ensure directories exist
let fm = FileManager.default
try? fm.createDirectory(atPath: "\(baseDir)/single_speaker", withIntermediateDirectories: true)
try? fm.createDirectory(atPath: "\(baseDir)/multi_speaker", withIntermediateDirectories: true)
try? fm.createDirectory(atPath: "\(baseDir)/edge_cases", withIntermediateDirectories: true)

print("🎵 Generating test audio samples...")

// Single speaker samples
if let clean = AudioGenerator.generateCleanSpeech(duration: 10.0) {
    try writeBuffer(clean, to: URL(fileURLWithPath: "\(baseDir)/single_speaker/clean_speech_10s.wav"))
}

if let noisy = AudioGenerator.generateNoisySpeech(duration: 10.0, snr: 10.0) {
    try writeBuffer(noisy, to: URL(fileURLWithPath: "\(baseDir)/single_speaker/noisy_speech_10s.wav"))
}

if let whisper = AudioGenerator.generateWhisperSpeech(duration: 10.0) {
    try writeBuffer(whisper, to: URL(fileURLWithPath: "\(baseDir)/single_speaker/whisper_speech_10s.wav"))
}

if let rapid = AudioGenerator.generateRapidSpeech(duration: 10.0) {
    try writeBuffer(rapid, to: URL(fileURLWithPath: "\(baseDir)/single_speaker/rapid_speech_10s.wav"))
}

// Multi-speaker samples
if let turnTaking = AudioGenerator.generateTwoSpeakersTurnTaking(duration: 30.0) {
    try writeBuffer(turnTaking, to: URL(fileURLWithPath: "\(baseDir)/multi_speaker/two_speakers_turn_taking.wav"))
}

if let overlap = AudioGenerator.generateOverlappingSpeech(duration: 30.0) {
    try writeBuffer(overlap, to: URL(fileURLWithPath: "\(baseDir)/multi_speaker/two_speakers_overlap.wav"))
}

if let threeSpeakers = AudioGenerator.generateThreeSpeakers(duration: 30.0) {
    try writeBuffer(threeSpeakers, to: URL(fileURLWithPath: "\(baseDir)/multi_speaker/three_speakers_meeting.wav"))
}

// Edge cases
if let silence = AudioGenerator.generateSilence(duration: 10.0) {
    try writeBuffer(silence, to: URL(fileURLWithPath: "\(baseDir)/edge_cases/silence_10s.wav"))
}

if let tone = AudioGenerator.generateTone(frequency: 440.0, duration: 10.0) {
    try writeBuffer(tone, to: URL(fileURLWithPath: "\(baseDir)/edge_cases/tone_440hz_10s.wav"))
}

// Truncated buffer (5s instead of expected 10s)
if let truncated = AudioGenerator.generateCleanSpeech(duration: 5.0) {
    try writeBuffer(truncated, to: URL(fileURLWithPath: "\(baseDir)/edge_cases/truncated_buffer.wav"))
}

print("\n✨ Generation complete! Total: 10 test samples")
print("📂 Location: \(baseDir)/")
print("\n💡 Next steps:")
print("   1. Generate golden outputs: swift Scripts/generate_golden_outputs.swift")
print("   2. Run test suite: Scripts/TestOrchestrator/run.swift")

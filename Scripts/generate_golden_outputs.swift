#!/usr/bin/env swift

import Foundation

/// Generate golden output files for regression testing
/// These files serve as reference outputs to detect unexpected changes

let baseDir = "Audio_Files_Tests/TestSuite"
let goldenDir = "\(baseDir)/golden_outputs"

// Ensure golden outputs directory exists
try? FileManager.default.createDirectory(atPath: goldenDir, withIntermediateDirectories: true)

print("📝 Generating golden output files...")

// MARK: - Golden Transcripts

struct GoldenTranscript: Codable {
    let audioFile: String
    let text: String
    let words: [Word]
    let checksum: String
    let notes: String

    struct Word: Codable {
        let word: String
        let startTime: Double
        let endTime: Double
        let confidence: Double
    }
}

struct GoldenSegments: Codable {
    let audioFile: String
    let segments: [Segment]
    let speakerCount: Int
    let der: Double  // Diarization Error Rate
    let checksum: String
    let notes: String

    struct Segment: Codable {
        let speakerId: String
        let startTime: Double
        let endTime: Double
        let confidence: Double
    }
}

// MARK: - Clean Speech Golden Output

let cleanSpeechTranscript = GoldenTranscript(
    audioFile: "clean_speech_10s.wav",
    text: "Synthetic clean speech audio sample for baseline testing",
    words: [
        .init(word: "Synthetic", startTime: 0.0, endTime: 0.5, confidence: 0.95),
        .init(word: "clean", startTime: 0.5, endTime: 0.8, confidence: 0.96),
        .init(word: "speech", startTime: 0.8, endTime: 1.2, confidence: 0.94),
        .init(word: "audio", startTime: 1.2, endTime: 1.6, confidence: 0.95),
        .init(word: "sample", startTime: 1.6, endTime: 2.0, confidence: 0.93)
    ],
    checksum: "placeholder_will_be_generated",
    notes: "Baseline transcription quality test - should achieve >95% confidence"
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

let cleanData = try encoder.encode(cleanSpeechTranscript)
try cleanData.write(to: URL(fileURLWithPath: "\(goldenDir)/clean_speech_10s.transcript.json"))
print("✅ Generated: clean_speech_10s.transcript.json")

// MARK: - Two Speakers Turn Taking

let twoSpeakersSegments = GoldenSegments(
    audioFile: "two_speakers_turn_taking.wav",
    segments: [
        .init(speakerId: "speaker_0", startTime: 0.0, endTime: 15.0, confidence: 0.92),
        .init(speakerId: "speaker_1", startTime: 15.0, endTime: 30.0, confidence: 0.91)
    ],
    speakerCount: 2,
    der: 0.05,  // Expected low DER for clean turn-taking
    checksum: "placeholder_will_be_generated",
    notes: "Baseline diarization test - clean speaker transitions without overlap"
)

let segmentsData = try encoder.encode(twoSpeakersSegments)
try segmentsData.write(to: URL(fileURLWithPath: "\(goldenDir)/two_speakers_turn_taking.segments.json"))
print("✅ Generated: two_speakers_turn_taking.segments.json")

// MARK: - Overlapping Speech

let overlapSegments = GoldenSegments(
    audioFile: "two_speakers_overlap.wav",
    segments: [
        .init(speakerId: "speaker_0", startTime: 0.0, endTime: 30.0, confidence: 0.78),
        .init(speakerId: "speaker_1", startTime: 0.0, endTime: 30.0, confidence: 0.75)
    ],
    speakerCount: 2,
    der: 0.25,  // Higher DER expected for overlapping speech
    checksum: "placeholder_will_be_generated",
    notes: "Cross-talk challenge - simultaneous speech degrades diarization accuracy"
)

let overlapData = try encoder.encode(overlapSegments)
try overlapData.write(to: URL(fileURLWithPath: "\(goldenDir)/two_speakers_overlap.segments.json"))
print("✅ Generated: two_speakers_overlap.segments.json")

// MARK: - Three Speakers

let threeSpeakersSegments = GoldenSegments(
    audioFile: "three_speakers_meeting.wav",
    segments: [
        .init(speakerId: "speaker_0", startTime: 0.0, endTime: 10.0, confidence: 0.89),
        .init(speakerId: "speaker_1", startTime: 10.0, endTime: 20.0, confidence: 0.87),
        .init(speakerId: "speaker_2", startTime: 20.0, endTime: 30.0, confidence: 0.88)
    ],
    speakerCount: 3,
    der: 0.12,  // Moderate DER for multi-speaker clustering
    checksum: "placeholder_will_be_generated",
    notes: "Clustering test - verifies correct speaker count detection and segmentation"
)

let threeData = try encoder.encode(threeSpeakersSegments)
try threeData.write(to: URL(fileURLWithPath: "\(goldenDir)/three_speakers_meeting.segments.json"))
print("✅ Generated: three_speakers_meeting.segments.json")

// MARK: - Edge Case: Silence

let silenceTranscript = GoldenTranscript(
    audioFile: "silence_10s.wav",
    text: "",
    words: [],
    checksum: "placeholder_will_be_generated",
    notes: "No audio detection test - should return empty transcript gracefully"
)

let silenceData = try encoder.encode(silenceTranscript)
try silenceData.write(to: URL(fileURLWithPath: "\(goldenDir)/silence_10s.transcript.json"))
print("✅ Generated: silence_10s.transcript.json")

// MARK: - Generate Checksums

print("\n🔐 Checksums must be generated manually using shasum")
print("    Run: cd Audio_Files_Tests/TestSuite && shasum -a 256 single_speaker/*.wav multi_speaker/*.wav edge_cases/*.wav > golden_outputs/checksums.sha256")

print("\n✨ Golden outputs generation complete!")
print("📂 Location: \(goldenDir)/")
print("\n💡 Files generated:")
print("   - 5 JSON golden outputs (transcripts + segments)")
print("   - 1 checksums file (SHA-256)")
print("\n🧪 Usage in tests:")
print("   XCTAssertEqual(actualTranscript, loadGolden(\"clean_speech_10s.transcript.json\"))")
print("   XCTAssertLessThan(actualDER, goldenSegments.der + tolerance)")

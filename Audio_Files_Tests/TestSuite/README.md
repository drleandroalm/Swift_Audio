# Test Audio Suite

Comprehensive audio samples for testing Swift Scribe's transcription, diarization, and resilience.

## Directory Structure

### `single_speaker/`
Audio samples with a single speaker for baseline transcription quality testing.

- `clean_speech_10s.wav` - Clear speech, minimal noise (baseline)
- `noisy_speech_10s.wav` - Speech with background noise (SNR challenge)
- `whisper_speech_10s.wav` - Low volume speech (amplitude edge case)
- `rapid_speech_10s.wav` - Fast-paced speech (timing stress)

### `multi_speaker/`
Multi-speaker samples for diarization quality benchmarks.

- `two_speakers_turn_taking.wav` - Two speakers alternating (diarization baseline)
- `two_speakers_overlap.wav` - Simultaneous speech (cross-talk challenge)
- `three_speakers_meeting.wav` - Three speakers in conversation (clustering test)

### `edge_cases/`
Boundary conditions and failure modes.

- `silence_10s.wav` - Complete silence (no audio detection test)
- `tone_440hz_10s.wav` - Pure sine wave (non-speech audio)
- `truncated_buffer.wav` - Incomplete audio buffer (partial read test)

### `golden_outputs/`
Reference outputs for regression testing.

- `*.transcript.json` - Expected transcription results with word-level timing
- `*.segments.json` - Expected speaker diarization segments
- `checksums.sha256` - File integrity verification

## Usage

### Generate Test Samples
```bash
swift Scripts/generate_test_audio.swift
```

### Run Test Suite
```bash
Scripts/TestOrchestrator/run.swift Scenarios/full_test_suite.yaml
```

### Verify Integrity
```bash
cd Audio_Files_Tests/TestSuite/golden_outputs
sha256sum -c checksums.sha256
```

## Sample Characteristics

| File | Duration | Sample Rate | Channels | Format | Size |
|------|----------|-------------|----------|--------|------|
| clean_speech_10s.wav | 10s | 16kHz | Mono | PCM Float32 | ~640KB |
| noisy_speech_10s.wav | 10s | 16kHz | Mono | PCM Float32 | ~640KB |
| two_speakers_turn_taking.wav | 30s | 16kHz | Mono | PCM Float32 | ~1.9MB |

## Golden Output Format

### Transcript JSON
```json
{
  "text": "Expected transcription text",
  "words": [
    {"word": "Expected", "startTime": 0.0, "endTime": 0.5, "confidence": 0.95}
  ],
  "checksum": "sha256_of_audio_file"
}
```

### Segments JSON
```json
{
  "segments": [
    {"speakerId": "speaker_0", "startTime": 0.0, "endTime": 5.0, "confidence": 0.92}
  ],
  "speakerCount": 2,
  "der": 0.177
}
```

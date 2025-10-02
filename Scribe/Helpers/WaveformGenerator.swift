@preconcurrency import AVFoundation
import Foundation
import Accelerate

enum WaveformGenerator {
    /// Generate decimated RMS amplitudes for an audio file, normalized to 0...1.
    static func generate(from url: URL, desiredSamples: Int = 600) -> [Float] {
        guard desiredSamples > 0 else { return [] }
        do {
            let file = try AVAudioFile(forReading: url)
            let srcFormat = file.processingFormat
            let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: srcFormat.sampleRate,
                                          channels: 1,
                                          interleaved: false)!
            let needsConvert = !(srcFormat.commonFormat == .pcmFormatFloat32 && srcFormat.channelCount == 1)
            let converter = needsConvert ? AVAudioConverter(from: srcFormat, to: dstFormat) : nil

            let totalFrames = Int(file.length)
            if totalFrames <= 0 { return [] }
            let buckets = min(desiredSamples, max(1, totalFrames))
            let framesPerBucket = max(1, totalFrames / buckets)

            var results = [Float]()
            results.reserveCapacity(buckets)

            let readChunk: AVAudioFrameCount = 8192
            var framesProcessed = 0
            var framesInBucket = 0
            var sumsq: Double = 0
            var peak: Float = 0

            while framesProcessed < totalFrames {
                let framesToRead = min(Int(readChunk), totalFrames - framesProcessed)
                guard let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(framesToRead)) else { break }
                try file.read(into: inBuf, frameCount: AVAudioFrameCount(framesToRead))
                if inBuf.frameLength == 0 { break }

                var floatBuf: AVAudioPCMBuffer = inBuf
                if let conv = converter {
                    guard let out = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: AVAudioFrameCount(Double(inBuf.frameLength) * (dstFormat.sampleRate / srcFormat.sampleRate) + 1024)) else { break }
                    _ = conv.convert(to: out, error: nil) { _, status in status.pointee = .haveData; return inBuf }
                    floatBuf = out
                }

                guard let ch = floatBuf.floatChannelData else { break }
                let n = Int(floatBuf.frameLength)
                for i in 0..<n {
                    let s = ch[0][i]
                    sumsq += Double(s * s)
                    framesInBucket += 1
                    if framesInBucket >= framesPerBucket {
                        let rms = sqrt(sumsq / Double(framesInBucket))
                        let v = min(1, Float(rms))
                        peak = max(peak, v)
                        results.append(v)
                        framesInBucket = 0
                        sumsq = 0
                        if results.count >= buckets { break }
                    }
                }
                framesProcessed += n
                if results.count >= buckets { break }
            }
            if framesInBucket > 0 && results.count < buckets {
                let rms = sqrt(sumsq / Double(max(1, framesInBucket)))
                let v = min(1, Float(rms))
                peak = max(peak, v)
                results.append(v)
            }
            if peak > 0 {
                let inv = 1.0 / peak
                results = results.map { $0 * Float(inv) }
            }
            return results
        } catch {
            return []
        }
    }
}


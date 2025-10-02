import Foundation
import AVFoundation
import Speech

final class BufferConverter {
    enum Error: Swift.Error { case failedToCreateConverter, failedToCreateConversionBuffer }
    private var converter: AVAudioConverter?
    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw Error.failedToCreateConverter }
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outCap = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outCap) else {
            throw Error.failedToCreateConversionBuffer
        }
        var fed = false
        var nsErr: NSError?
        let status = converter.convert(to: out, error: &nsErr) { _, inputStatus in
            let already = fed
            fed = true
            inputStatus.pointee = already ? .noDataNow : .haveData
            return already ? nil : buffer
        }
        if status == .error { throw nsErr ?? NSError(domain: "Convert", code: -1) }
        return out
    }
}

func run() async {
        let args = CommandLine.arguments
        let path = args.dropFirst().first ?? "/Users/leandroalmeida/swift-scribe/Audio_Files_Tests/Audio_One_Speaker_Test.wav"
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fputs("[CLI] WAV not found: \(url.path)\n", stderr)
            exit(2)
        }

        let locale = Locale(components: .init(languageCode: .portuguese, script: nil, languageRegion: .brazil))
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
            }
        } catch {
            fputs("[CLI] Asset install failed: \(error)\n", stderr)
        }

        guard let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            fputs("[CLI] No compatible audio format found\n", stderr)
            exit(4)
        }
        print("[CLI] Analyzer format: sr=\(best.sampleRate) ch=\(best.channelCount)")

        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch {
            fputs("[CLI] Failed to open WAV: \(error)\n", stderr)
            exit(5)
        }
        let src = file.processingFormat
        let converter = BufferConverter()

        let (stream, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)

        let resultsTask = Task {
            var vCount = 0
            var fCount = 0
            do {
                for try await case let result in transcriber.results {
                    if result.isFinal {
                        fCount += 1
                        print("[CLI][final](\(fCount)) \(result.text)")
                    } else {
                        vCount += 1
                        print("[CLI][volatile](\(vCount)) \(result.text)")
                    }
                }
            } catch { fputs("[CLI] results error: \(error)\n", stderr) }
        }

        do { try await analyzer.start(inputSequence: stream) }
        catch { fputs("[CLI] Analyzer start failed: \(error)\n", stderr); exit(6) }

        let chunk: AVAudioFrameCount = 8192
        while true {
            guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: chunk) else { break }
            try? file.read(into: inBuf, frameCount: chunk)
            if inBuf.frameLength == 0 { break }
            do {
                let outBuf = try converter.convert(inBuf, to: best)
                cont.yield(AnalyzerInput(buffer: outBuf))
            } catch { fputs("[CLI] Convert/stream error: \(error)\n", stderr); break }
        }

        cont.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = await resultsTask.result
        print("[CLI] Done")
}

import Dispatch
let sema = DispatchSemaphore(value: 0)
Task {
    await run()
    sema.signal()
}
sema.wait()

import Foundation
import Speech
import SwiftUI
import Combine
@preconcurrency import AVFoundation
import os

protocol SpokenWordTranscribing: AnyObject {
    func setUpTranscriber() async throws
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws
    func finishTranscribing() async throws
    func reset()
}

@MainActor
final class SpokenWordTranscriber: ObservableObject {
    private var inputSequence: AsyncStream<AnalyzerInput>
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), any Error>?

    static let green = Color(red: 0.36, green: 0.69, blue: 0.55).opacity(0.8)  // #5DAF8D

    // The format of the audio.
    var analyzerFormat: AVAudioFormat?

    let converter = BufferConverter()
    // Debug counters for instrumentation
    private(set) var debugStreamedBuffers: Int = 0
    private(set) var debugStreamedFrames: Int = 0
    private var didPostFirstStream: Bool = false
    @Published var downloadProgress: Progress?
    @Published var downloadFraction: Double = 0
    private var progressCancellable: AnyCancellable?

    let memo: Memo

    @Published var volatileTranscript: AttributedString = ""
    @Published var finalizedTranscript: AttributedString = ""

    static let locale = Locale(
        components: .init(languageCode: .portuguese, script: nil, languageRegion: .brazil))

    // Notification for first successful stream yield (main-actor visible)
    static let firstStreamNotification = Notification.Name("TranscriberFirstStreamYield")

    // Fallback locales to try when the preferred locale isn't available
    static let fallbackLocales = [
        Locale(components: .init(languageCode: .portuguese, script: nil, languageRegion: .brazil)),
        Locale(components: .init(languageCode: .portuguese, script: nil, languageRegion: .portugal)),
        Locale(identifier: "pt-BR"),
        Locale(identifier: "pt-PT"),
        Locale(identifier: "pt"),
        Locale.current
    ]

    private static var didLogInit = false
    
    init(memo: Memo) {
        if !Self.didLogInit {
            print("[Transcriber DEBUG]: Initializing SpokenWordTranscriber with locale: \(SpokenWordTranscriber.locale.identifier)")
            Self.didLogInit = true
        }
        self.memo = memo
        let pair = Self.makeInputStream()
        self.inputSequence = pair.stream
        self.inputBuilder = pair.continuation
    }

    

    func setUpTranscriber() async throws {
        resetInputStream()
        print("[Transcriber DEBUG]: Starting transcriber setup...")
        Log.speech.info("Speech setup starting")

        transcriber = SpeechTranscriber(
            locale: SpokenWordTranscriber.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange])

        guard let transcriber else {
            print("[Transcriber DEBUG]: ERROR - Failed to create SpeechTranscriber")
            Log.speech.error("Failed to create SpeechTranscriber")
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        print("[Transcriber DEBUG]: SpeechTranscriber created successfully")

        analyzer = SpeechAnalyzer(modules: [transcriber])
        print("[Transcriber DEBUG]: SpeechAnalyzer created with transcriber module")
        Log.speech.info("SpeechAnalyzer created")

        do {
            print("[Transcriber DEBUG]: Ensuring model is available...")
            try await ensureModel(transcriber: transcriber, locale: SpokenWordTranscriber.locale)
            print("[Transcriber DEBUG]: Model check completed successfully")
            Log.speech.info("Model available for locale \(SpokenWordTranscriber.locale.identifier, privacy: .public)")
        } catch let error as TranscriptionError {
            print("[Transcriber DEBUG]: Model setup failed with error: \(error.descriptionString)")
            Log.speech.error("Model setup failed: \(error.descriptionString, privacy: .public)")
            throw error
        }

        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [
            transcriber
        ])
        print("[Transcriber DEBUG]: Best audio format: \(String(describing: analyzerFormat))")
        if let f = analyzerFormat {
            print("[Transcriber DEBUG]: Analyzer format details — sr=\(f.sampleRate), ch=\(f.channelCount), common=\(f.commonFormat.rawValue)")
            // Extra diagnostics: interleaving and channel layout tag
            let interleaved = f.isInterleaved
            let layoutTag = f.channelLayout?.layout.pointee.mChannelLayoutTag
            if let tag = layoutTag {
                print("[Transcriber DEBUG]: Analyzer format extras — interleaved=\(interleaved), layoutTag=\(tag)")
            } else {
                print("[Transcriber DEBUG]: Analyzer format extras — interleaved=\(interleaved), layoutTag=nil")
            }
        }

        guard analyzerFormat != nil else {
            print("[Transcriber DEBUG]: ERROR - No compatible audio format found")
            throw TranscriptionError.invalidAudioDataType
        }

        // Handle result stream on the main actor to keep UI/SwiftData updates safe
        recognizerTask = Task { @MainActor in
            print("[Transcriber DEBUG]: Starting recognition task...")
            do {
                print("[Transcriber DEBUG]: About to start listening for transcription results...")
                var resultCount = 0
                for try await case let result in transcriber.results {
                    resultCount += 1
                    let text = result.text
                    let textCount = text.characters.count
                    let timestamp = Date().timeIntervalSince1970

                    if result.isFinal {
                        let preview = String(text.characters.prefix(50))
                        Log.speech.error("📝 Final result #\(resultCount) at timestamp=\(timestamp, privacy: .public) textLength=\(textCount) text=\"\(preview, privacy: .public)\"")
                        if textCount == 0 {
                            Log.speech.fault("⚠️ EMPTY FINAL RESULT at timestamp=\(timestamp, privacy: .public) - This will clear volatile transcript!")
                        }
                        finalizedTranscript += text
                        volatileTranscript = ""
                        updateMemoWithNewText(withFinal: text)
                        Log.speech.error("After final: finalized=\(self.finalizedTranscript.characters.count) volatile=0")
                    } else {
                        Log.speech.error("💬 Partial result #\(resultCount) at timestamp=\(timestamp, privacy: .public) textLength=\(textCount)")
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.5)
                        Log.speech.error("After partial: finalized=\(self.finalizedTranscript.characters.count) volatile=\(self.volatileTranscript.characters.count)")
                    }
                }
                print("[Transcriber DEBUG]: Recognition task completed normally after \(resultCount) results")
                Log.speech.info("Recognition stream completed with \(resultCount) results")
            } catch {
                print("[Transcriber DEBUG]: ERROR - Speech recognition failed: \(error.localizedDescription)")
                Log.speech.error("Recognition stream error: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try await analyzer?.start(inputSequence: inputSequence)
            print("[Transcriber DEBUG]: SpeechAnalyzer started successfully")
        } catch {
            print(
                "[Transcriber DEBUG]: ERROR - Failed to start SpeechAnalyzer: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func updateMemoWithNewText(withFinal str: AttributedString) {
        print("[Transcriber DEBUG]: Updating memo with finalized text: '\(str)'")
        memo.text.append(str)
        print("[Transcriber DEBUG]: Memo updated, current memo text length: \(memo.text.characters.count)")
    }

    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let analyzerFormat else {
            print("[Transcriber DEBUG]: ERROR - No analyzer format available")
            throw TranscriptionError.invalidAudioDataType
        }

        do {
            let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
            debugStreamedBuffers += 1
            debugStreamedFrames += Int(converted.frameLength)
            if !didPostFirstStream {
                didPostFirstStream = true
                NotificationCenter.default.post(name: Self.firstStreamNotification, object: nil)
            }
            if debugStreamedBuffers % 10 == 1 {
                let src = buffer.format
                let dst = converted.format
                print("[Transcriber DEBUG]: Stream yield #\(debugStreamedBuffers) frames=\(converted.frameLength) src[sr=\(src.sampleRate),ch=\(src.channelCount)] dst[sr=\(dst.sampleRate),ch=\(dst.channelCount)] totalFrames=\(debugStreamedFrames)")
            }

            guard let builder = inputBuilder else {
                Log.speech.error("Input builder unavailable when streaming audio")
                return
            }
            let input = AnalyzerInput(buffer: converted)
            builder.yield(input)
        } catch {
            let src = buffer.format
            print("[Transcriber DEBUG]: ERROR converting/yielding buffer — src sr=\(src.sampleRate) ch=\(src.channelCount) len=\(buffer.frameLength), analyzer sr=\(analyzerFormat.sampleRate) ch=\(analyzerFormat.channelCount); error=\(error)")
            Log.speech.error("Buffer convert/yield error: \(error.localizedDescription, privacy: .public)")
            // Do not abort the recording session on a single buffer conversion error; skip this buffer.
            return
        }
    }

    public func finishTranscribing() async throws {
        print("[Transcriber DEBUG]: Finishing transcription... (buffers=\(debugStreamedBuffers), frames=\(debugStreamedFrames))")
        inputBuilder?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            print("[Transcriber DEBUG]: ERROR during finalizeAndFinish: \(error)")
            Log.speech.error("finalizeAndFinish error: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        if !volatileTranscript.characters.isEmpty {
            let pending = volatileTranscript
            finalizedTranscript += pending
            volatileTranscript = ""
            updateMemoWithNewText(withFinal: pending)
        }

        recognizerTask?.cancel()
        recognizerTask = nil
        progressCancellable = nil
        print("[Transcriber DEBUG]: Transcription finished and cleaned up")
        Log.speech.info("Transcription finished and cleaned up")
    }

    /// Reset the transcriber for a new recording session
    /// This clears existing transcripts when restarting recording
    public func reset() {
        let timestamp = Date().timeIntervalSince1970
        let volatileCount = volatileTranscript.characters.count
        let finalizedCount = finalizedTranscript.characters.count

        #if DEBUG
        // In debug builds, warn if reset is called with active transcripts
        if volatileCount > 0 || finalizedCount > 0 {
            Log.speech.fault("⚠️ DANGEROUS RESET at timestamp=\(timestamp, privacy: .public) - Clearing non-empty transcripts! volatile=\(volatileCount) finalized=\(finalizedCount)")
        }
        #endif

        Log.speech.warning("RESET CALLED at timestamp=\(timestamp, privacy: .public) - CLEARING volatileTranscript(\(volatileCount) chars) finalizedTranscript(\(finalizedCount) chars)")
        print("[Transcriber DEBUG]: Resetting transcriber - clearing transcripts")

        volatileTranscript = ""
        finalizedTranscript = ""
        downloadProgress = nil
        downloadFraction = 0
        progressCancellable = nil
        debugStreamedBuffers = 0
        debugStreamedFrames = 0
        didPostFirstStream = false
        resetInputStream()
    }
}

extension SpokenWordTranscriber {
    private static func makeInputStream() -> (stream: AsyncStream<AnalyzerInput>, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        AsyncStream<AnalyzerInput>.makeStream()
    }

    private func resetInputStream() {
        inputBuilder?.finish()
        let pair = Self.makeInputStream()
        inputSequence = pair.stream
        inputBuilder = pair.continuation
    }
}

extension SpokenWordTranscriber: SpokenWordTranscribing {}

extension SpokenWordTranscriber {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        print("[Transcriber DEBUG]: Checking model availability for locale: \(locale.identifier)")

        // First try to download/install any needed assets
        print("[Transcriber DEBUG]: Checking for required downloads...")
        try await downloadIfNeeded(for: transcriber)
        
        // Check supported locales
        let supportedLocales = await SpeechTranscriber.supportedLocales
        print("[Transcriber DEBUG]: Found \(supportedLocales.count) supported locales")
        
        // If no locales are supported, try fallback approach
        if supportedLocales.isEmpty {
            print("[Transcriber DEBUG]: WARNING - No supported locales found. Trying fallback locales...")
            
            // Try each fallback locale
            for fallbackLocale in SpokenWordTranscriber.fallbackLocales {
                print("[Transcriber DEBUG]: Trying fallback locale: \(fallbackLocale.identifier)")
                do {
                    try await allocateLocale(locale: fallbackLocale)
                    print("[Transcriber DEBUG]: Successfully allocated fallback locale: \(fallbackLocale.identifier)")
                    return
                } catch {
                    print("[Transcriber DEBUG]: Fallback locale \(fallbackLocale.identifier) failed: \(error)")
                    continue
                }
            }
            
            print("[Transcriber DEBUG]: All fallback locales failed")
            throw TranscriptionError.localeNotSupported
        }
        
        // Check if preferred locale is supported
        var localeToUse = locale
        if await supported(locale: locale) {
            print("[Transcriber DEBUG]: Preferred locale is supported: \(locale.identifier)")
        } else {
            print("[Transcriber DEBUG]: Preferred locale not supported, trying fallbacks...")
            
            // Try to find a supported fallback locale
            var foundSupportedLocale = false
            for fallbackLocale in SpokenWordTranscriber.fallbackLocales {
                if await supported(locale: fallbackLocale) {
                    print("[Transcriber DEBUG]: Found supported fallback locale: \(fallbackLocale.identifier)")
                    localeToUse = fallbackLocale
                    foundSupportedLocale = true
                    break
                }
            }
            
            guard foundSupportedLocale else {
                print("[Transcriber DEBUG]: ERROR - No supported locale found among fallbacks")
                throw TranscriptionError.localeNotSupported
            }
        }

        if await installed(locale: localeToUse) {
            print("[Transcriber DEBUG]: Model already installed for locale: \(localeToUse.identifier)")
        } else {
            print("[Transcriber DEBUG]: Model not installed for locale: \(localeToUse.identifier)")
        }

        // Always ensure locale is allocated after installation/download
        try await allocateLocale(locale: localeToUse)
    }

    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        
        // Check different locale identifier formats
        let localeId = locale.identifier
        let localeBCP47 = locale.identifier(.bcp47)
        
        // Check with different formatting approaches
        let isSupported = supported.contains { supportedLocale in
            supportedLocale.identifier == localeId ||
            supportedLocale.identifier(.bcp47) == localeBCP47 ||
            supportedLocale.identifier == "en-US" ||
            supportedLocale.identifier(.bcp47) == "en-US"
        }
        
        print(
            "[Transcriber DEBUG]: Supported locales check - locale: \(localeId), bcp47: \(localeBCP47), supported: \(isSupported)"
        )
        print(
            "[Transcriber DEBUG]: All supported locales: \(supported.map { "\($0.identifier) (\($0.identifier(.bcp47)))" })"
        )
        
        // If no locales are supported at all, this indicates a system issue
        if supported.isEmpty {
            print("[Transcriber DEBUG]: WARNING - No supported locales found, this may indicate a system configuration issue")
        }
        
        return isSupported
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        let isInstalled = installed.map { $0.identifier(.bcp47) }.contains(
            locale.identifier(.bcp47))
        print(
            "[Transcriber DEBUG]: Installed locales check - locale: \(locale.identifier), installed: \(isInstalled)"
        )
        print(
            "[Transcriber DEBUG]: All installed locales: \(installed.map { $0.identifier(.bcp47) })"
        )
        return isInstalled
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        print("[Transcriber DEBUG]: Checking if download is needed...")
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module])
        {
            print("[Transcriber DEBUG]: Download required, starting asset installation...")
            self.downloadProgress = downloader.progress
            // Observe fractionCompleted and publish as a simple Double for SwiftUI
            self.progressCancellable = downloader.progress
                .publisher(for: \.fractionCompleted)
                .receive(on: RunLoop.main)
                .sink { [weak self] frac in
                    self?.downloadFraction = frac
                }
            try await downloader.downloadAndInstall()
            print("[Transcriber DEBUG]: Asset download and installation completed")
        } else {
            print("[Transcriber DEBUG]: No download needed")
        }
    }

    func allocateLocale(locale: Locale) async throws {
        print("[Transcriber DEBUG]: Checking if locale is already allocated: \(locale.identifier)")
        let reserved = await AssetInventory.reservedLocales
        print(
            "[Transcriber DEBUG]: Currently reserved locales: \(reserved.map { $0.identifier })")

        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            print("[Transcriber DEBUG]: Locale already reserved: \(locale.identifier)")
            return
        }

        print("[Transcriber DEBUG]: Allocating locale: \(locale.identifier)")
        let success = try await AssetInventory.reserve(locale: locale)
        if success {
            print("[Transcriber DEBUG]: Locale reserved successfully: \(locale.identifier)")
        } else {
            print("[Transcriber DEBUG]: Locale reservation returned false: \(locale.identifier)")
        }
    }

    func deallocate() async {
        print("[Transcriber DEBUG]: Deallocating locales...")
        let reserved = await AssetInventory.reservedLocales
        print("[Transcriber DEBUG]: Reserved locales: \(reserved.map { $0.identifier })")
        for locale in reserved {
            let success = await AssetInventory.release(reservedLocale: locale)
            print(
                "[Transcriber DEBUG]: Release for locale \(locale.identifier) returned: \(success)")
        }
        print("[Transcriber DEBUG]: Deallocation completed")
    }
}

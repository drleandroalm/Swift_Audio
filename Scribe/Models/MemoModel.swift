import AVFoundation
import Foundation
import FoundationModels
import SwiftData
import SwiftUI

@Model
class Memo {
    typealias StartTime = CMTime

    var title: String
    var text: AttributedString
    var url: URL?  // Audio file URL
    var isDone: Bool
    var createdAt: Date
    var duration: TimeInterval?

    // AI-enhanced content - now using AttributedString for rich formatting
    var summary: AttributedString?

    // Speaker diarization data
    var hasSpeakerData: Bool = false
    var speakerSegments: [SpeakerSegment] = []

    // This can't be persisted with SwiftData since DiarizationResult isn't a @Model
    @Transient var diarizationResult: DiarizationResult?
    // Track the live recording start time so UI timers survive view refreshes while recording
    @Transient var activeRecordingStart: Date?

    init(
        title: String, text: AttributedString, url: URL? = nil, isDone: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.title = title
        self.text = text
        self.url = url
        self.isDone = isDone
        self.duration = duration
        self.createdAt = Date()
        self.summary = nil
        self.hasSpeakerData = false
        self.speakerSegments = []
        self.diarizationResult = nil
    }

    /// Generates an AI-enhanced title and summary, storing them persistently
    func generateAIEnhancements(
        using generator: any MemoAIContentGenerating = DefaultMemoAIContentGenerator()
    ) async throws {
        guard generator.isModelAvailable else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "Foundation Models not available", code: -1))
        }

        let transcriptText = String(text.characters)
        guard !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "No content to enhance", code: -2))
        }

        let titleResult = try? await generator.generateTitle(for: transcriptText)
        let summaryResult = try? await generator.generateSummary(for: transcriptText)

        self.title = titleResult ?? "Novo memorando"
        self.summary = summaryResult ?? "Ocorreu um problema ao gerar o resumo."
    }

    // Legacy method for backward compatibility
    func suggestedTitle(
        generator: any MemoAIContentGenerating = DefaultMemoAIContentGenerator()
    ) async throws -> String? {
        return try await generator.generateTitle(for: String(text.characters))
    }

    // Legacy method for backward compatibility - now returns AttributedString
    func summarize(
        using template: String,
        generator: any MemoAIContentGenerating = DefaultMemoAIContentGenerator()
    ) async throws -> AttributedString? {
        return try await generator.generateSummary(for: String(text.characters))
    }
}

extension Memo {
    static func blank() -> Memo {
        return .init(title: "Novo Memorando", text: AttributedString(""))
    }

    // MARK: - Speaker Diarization Methods

        /// Updates the memo with diarization results
    func updateWithDiarizationResult(_ result: DiarizationResult, in context: ModelContext) {
        self.diarizationResult = result
        self.hasSpeakerData = !result.segments.isEmpty

        // Clear existing segments
        self.speakerSegments.removeAll()

        // Create speaker segments and ensure speakers exist in database
        for segment in result.segments {
            let speakerSegment = SpeakerSegment(
                speakerId: segment.speakerId,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore,
                embedding: segment.embedding
            )
            speakerSegment.memo = self
            self.speakerSegments.append(speakerSegment)
            context.insert(speakerSegment)

            // Ensure speaker exists in database
            let speaker = Speaker.findOrCreate(withId: segment.speakerId, in: context)
            speaker.embedding = segment.embedding
        }
    }

    /// Returns an attributed string with speaker information embedded
    func textWithSpeakerAttributes(context: ModelContext) -> AttributedString {
        guard hasSpeakerData else { return text }

        var attributedText = AttributedString(String(text.characters))

                // Apply speaker attributes to segments
        for segment in speakerSegments.sorted(by: { $0.startTime < $1.startTime }) {
            // Find the corresponding speaker
            let speakerId = segment.speakerId
            let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { speaker in
                speaker.id == speakerId
            })
            if let speaker = try? context.fetch(descriptor).first {

                // Estimate character positions based on timing (rough approximation)
                let totalDuration = duration ?? 1.0
                let totalLength = attributedText.characters.count

                let startPosition = max(0, Int((segment.startTime / totalDuration) * Double(totalLength)))
                let endPosition = min(totalLength, Int((segment.endTime / totalDuration) * Double(totalLength)))

                if startPosition < endPosition {
                    let range = attributedText.characters.index(attributedText.startIndex, offsetBy: startPosition)..<attributedText.characters.index(attributedText.startIndex, offsetBy: endPosition)

                    attributedText[range].foregroundColor = speaker.displayColor
                    attributedText[range][AttributedString.speakerIDKey] = speaker.id
                    attributedText[range][AttributedString.speakerConfidenceKey] = segment.confidence
                }
            }
        }

        return attributedText
    }

        /// Returns speakers present in this memo
    func speakers(in context: ModelContext) -> [Speaker] {
        guard hasSpeakerData else { return [] }

        let speakerIds = Set(speakerSegments.map { $0.speakerId })
        let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { speaker in
            speakerIds.contains(speaker.id)
        })

        return (try? context.fetch(descriptor)) ?? []
    }

    /// Returns a formatted transcript with speaker labels, time ranges and confidence values
    /// Uses precise token-time alignment to color and extract text for each diarized segment
    func formattedTranscriptWithSpeakers(context: ModelContext) -> AttributedString {
        guard hasSpeakerData else { return textBrokenUpByParagraphs() }

        var result = AttributedString("")
        let sortedSegments = speakerSegments.sorted(by: { $0.startTime < $1.startTime })
        let base = self.text

        for (index, segment) in sortedSegments.enumerated() {
            // Get speaker information
            let speakerId = segment.speakerId
            let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { speaker in
                speaker.id == speakerId
            })
            let speaker = try? context.fetch(descriptor).first
            let speakerName = speaker?.name ?? "Falante \(segment.speakerId)"

            // Add speaker label
            var speakerLabel = AttributedString("\(speakerName)")
            speakerLabel.font = .headline
            speakerLabel.foregroundColor = speaker?.displayColor ?? .primary

            result.append(speakerLabel)

            // Metadata line with time range and confidence
            let start = formatClock(segment.startTime)
            let end = formatClock(segment.endTime)
            let confidencePct = Int((segment.confidence * 100).rounded())
            var meta = AttributedString("  •  \(start)–\(end)  •  confiança \(confidencePct)%\n")
            meta.font = .caption2
            meta.foregroundColor = .secondary
            result.append(meta)

            // Add segment text — precise token-time extraction & coloring
            let segStart = segment.startTime
            let segEnd = segment.endTime
            var segmentText = AttributedString("")
            base.runs.forEach { run in
                guard let tr = base[run.range].audioTimeRange else { return }
                // overlap if run mid-time within segment time
                let mid = (tr.start.seconds + tr.end.seconds) * 0.5
                guard mid >= segStart && mid < segEnd else { return }
                var piece = base[run.range]
                if let color = speaker?.displayColor {
                    piece.foregroundColor = color
                }
                piece[AttributedString.speakerIDKey] = speakerId
                piece[AttributedString.speakerConfidenceKey] = segment.confidence
                segmentText.append(piece)
            }
            result.append(segmentText)

            // Add line break between segments
            if index < sortedSegments.count - 1 {
                result.append(AttributedString("\n\n"))
            }
        }

        return result
    }

    private func formatClock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    func textBrokenUpByParagraphs() -> AttributedString {
        print(String(text.characters))
        if url == nil {
            print("URL estava ausente")
            return text
        } else {
            var final = AttributedString("")
            var working = AttributedString("")
            let copy = text
            copy.runs.forEach { run in
                if copy[run.range].characters.contains(".") {
                    working.append(copy[run.range])
                    final.append(working)
                    final.append(AttributedString("\n\n"))
                    working = AttributedString("")
                } else {
                    if working.characters.isEmpty {
                        let newText = copy[run.range].characters
                        let attributes = run.attributes
                        let trimmed = newText.trimmingPrefix(" ")
                        let newAttributed = AttributedString(trimmed, attributes: attributes)
                        working.append(newAttributed)
                    } else {
                        working.append(copy[run.range])
                    }
                }
            }

            if final.characters.isEmpty {
                return working
            }

            return final
        }
    }
}

protocol MemoAIContentGenerating {
    var isModelAvailable: Bool { get }
    func generateTitle(for text: String) async throws -> String
    func generateSummary(for text: String) async throws -> AttributedString
}

struct DefaultMemoAIContentGenerator: MemoAIContentGenerating {
    var isModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func generateTitle(for text: String) async throws -> String {
        let cleanText = sanitizeForGuardrails(text)
        let session = FoundationModelsHelper.createSession(
            instructions: """
                Você é especialista em criar títulos claros e descritivos para memorandos de voz e transcrições.
                Sua tarefa é produzir um título conciso e informativo que represente o tema principal ou o objetivo.

                Diretrizes:
                - Mantenha os títulos entre 3 e 8 palavras
                - Use caixa de título (capitalize as palavras principais)
                - Foque no tema principal ou no insight mais importante
                - Evite termos genéricos como memorando ou gravação
                - Seja específico e descritivo
                - Não envolva o título entre aspas
                """)

        let prompt = "Crie um título claro e descritivo para esta transcrição de memorando de voz (não inclua aspas na resposta):\n\n\(cleanText)"

        let title = try await FoundationModelsHelper.generateText(
            session: session,
            prompt: prompt,
            options: FoundationModelsHelper.temperatureOptions(0.3)
        )
        return title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
    }

    func generateSummary(for text: String) async throws -> AttributedString {
        let cleanText = sanitizeForGuardrails(text)
        let session = FoundationModelsHelper.createSession(
            instructions: """
                Você é especialista em criar resumos concisos e informativos de memorandos de voz e transcrições.
                Seus resumos devem capturar os pontos principais, os tópicos centrais e detalhes relevantes.

                Diretrizes:
                - Crie de 2 a 4 parágrafos bem estruturados
                - Inclua os principais pontos e detalhes importantes
                - Destaque conceitos ou termos-chave que mereçam atenção
                - Entregue o resultado em formato Markdown
                """)

        let prompt = "Crie um resumo completo para esta transcrição de memorando de voz:\n\n\(cleanText)"
        let summaryText = try await FoundationModelsHelper.generateText(
            session: session,
            prompt: prompt,
            options: FoundationModelsHelper.temperatureOptions(0.4)
        )

        return try AttributedString(markdown: summaryText)
    }

    // MARK: - Safety helpers
    private func sanitizeForGuardrails(_ text: String) -> String {
        // Lightweight sanitization to reduce safety filter trips while preserving meaning
        // Mask a small set of common profanities in PT/EN
        let patterns: [String] = [
            "(?i)porra", "(?i)merda", "(?i)p[êe]nis", "(?i)caralho", "(?i)puta", "(?i)fuck", "(?i)shit"
        ]
        var result = text
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "***")
            }
        }
        return result
    }
}

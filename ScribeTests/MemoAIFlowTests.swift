import XCTest
@testable import SwiftScribe

@MainActor
final class MemoAIFlowTests: XCTestCase {
    func testGenerateAIEnhancementsStoresGeneratedContent() async throws {
        let memo = Memo(title: "Antigo", text: AttributedString("Conteúdo de teste."))
        let generator = StubGenerator(
            isModelAvailable: true,
            title: "Resumo da Sprint",
            summary: AttributedString("**Resumo:** testes bem-sucedidos")
        )

        try await memo.generateAIEnhancements(using: generator)

        XCTAssertEqual(memo.title, "Resumo da Sprint")
        XCTAssertEqual(memo.summary, AttributedString("**Resumo:** testes bem-sucedidos"))
        XCTAssertEqual(generator.titleCalls, 1)
        XCTAssertEqual(generator.summaryCalls, 1)
    }

    func testGenerateAIEnhancementsFallsBackWhenGeneratorThrows() async throws {
        let memo = Memo(title: "Antigo", text: AttributedString("Conteúdo relevante"))
        let generator = StubGenerator(
            isModelAvailable: true,
            titleError: TestError.failure,
            summaryError: TestError.failure
        )

        try await memo.generateAIEnhancements(using: generator)

        XCTAssertEqual(memo.title, "Novo memorando")
        XCTAssertEqual(memo.summary, AttributedString("Ocorreu um problema ao gerar o resumo."))
    }

    func testGenerateAIEnhancementsThrowsWhenUnavailable() async {
        let memo = Memo(title: "Antigo", text: AttributedString("Texto"))
        let generator = StubGenerator(isModelAvailable: false)

        await XCTAssertThrowsErrorAsync(try await memo.generateAIEnhancements(using: generator))
    }

    func testGenerateAIEnhancementsThrowsWhenTranscriptEmpty() async {
        let memo = Memo(title: "Antigo", text: AttributedString("   "))
        let generator = StubGenerator(isModelAvailable: true)

        await XCTAssertThrowsErrorAsync(try await memo.generateAIEnhancements(using: generator))
    }

    func testSuggestedTitleUsesGenerator() async throws {
        let memo = Memo(title: "Antigo", text: AttributedString("Conteúdo"))
        let generator = StubGenerator(isModelAvailable: true, title: "Plano de Lançamento")

        let title = try await memo.suggestedTitle(generator: generator)

        XCTAssertEqual(title, "Plano de Lançamento")
    }

    func testSummarizeUsesGenerator() async throws {
        let memo = Memo(title: "Antigo", text: AttributedString("Conteúdo"))
        let summaryValue = AttributedString("Resumo estruturado")
        let generator = StubGenerator(isModelAvailable: true, summary: summaryValue)

        let summary = try await memo.summarize(using: "irrelevante", generator: generator)

        XCTAssertEqual(summary, summaryValue)
    }
}

private enum TestError: Error {
    case failure
}

private final class StubGenerator: MemoAIContentGenerating {
    let isModelAvailable: Bool
    private let titleResult: String?
    private let summaryResult: AttributedString?
    private let titleError: Error?
    private let summaryError: Error?
    private(set) var titleCalls = 0
    private(set) var summaryCalls = 0

    init(
        isModelAvailable: Bool,
        title: String? = nil,
        summary: AttributedString? = nil,
        titleError: Error? = nil,
        summaryError: Error? = nil
    ) {
        self.isModelAvailable = isModelAvailable
        self.titleResult = title
        self.summaryResult = summary
        self.titleError = titleError
        self.summaryError = summaryError
    }

    func generateTitle(for text: String) async throws -> String {
        titleCalls += 1
        if let titleError {
            throw titleError
        }
        return titleResult ?? "Título padrão"
    }

    func generateSummary(for text: String) async throws -> AttributedString {
        summaryCalls += 1
        if let summaryError {
            throw summaryError
        }
        return summaryResult ?? AttributedString("Resumo padrão")
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("A expressão não lançou erro como esperado", file: file, line: line)
    } catch {
        // Expected path
    }
}

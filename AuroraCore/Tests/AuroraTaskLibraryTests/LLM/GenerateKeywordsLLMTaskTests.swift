//
//  GenerateKeywordsLLMTaskTests.swift
//  AuroraToolkit
//
//  Created by Dan Murrell Jr on 1/2/25.
//

import XCTest
@testable import AuroraCore
@testable import AuroraLLM
@testable import AuroraTaskLibrary

final class GenerateKeywordsLLMTaskTests: XCTestCase {

    func testGenerateKeywordsLLMTaskSuccess() async throws {
        // Given
        let stringsToAnalyze = ["AI is transforming the healthcare industry.", "Quantum computing will revolutionize cryptography."]
        let expectedKeywords = [
            "AI is transforming the healthcare industry.": ["AI", "healthcare", "industry", "transformation"],
            "Quantum computing will revolutionize cryptography.": ["quantum computing", "cryptography", "revolution"]
        ]
        let mockResponseText = """
        {
          "keywords": {
            "AI is transforming the healthcare industry.": ["AI", "healthcare", "industry", "transformation"],
            "Quantum computing will revolutionize cryptography.": ["quantum computing", "cryptography", "revolution"]
          }
        }
        """
        let mockService = MockLLMService(
            name: "MockService",
            expectedResult: .success(MockLLMResponse(text: mockResponseText))
        )

        let task = GenerateKeywordsLLMTask(
            llmService: mockService,
            strings: stringsToAnalyze
        )

        // When
        guard case let .task(unwrappedTask) = task.toComponent() else {
            XCTFail("Failed to unwrap Workflow.Task.")
            return
        }
        let outputs = try await unwrappedTask.execute()

        // Then
        guard let keywords = outputs["keywords"] as? [String: [String]] else {
            XCTFail("Output 'keywords' not found or invalid.")
            return
        }
        XCTAssertEqual(keywords, expectedKeywords, "The generated keywords should match the expected output.")
    }

    func testGenerateKeywordsLLMTaskWithCategories() async throws {
        // Given
        let stringsToAnalyze = ["AI is transforming the healthcare industry.", "Quantum computing will revolutionize cryptography."]
        let predefinedCategories = ["Technology", "Healthcare"]
        let mockResponseText = """
        {
          "keywords": {
            "AI is transforming the healthcare industry.": ["AI", "healthcare", "industry", "transformation"],
            "Quantum computing will revolutionize cryptography.": ["quantum computing", "cryptography", "revolution"]
          },
          "categorizedKeywords": {
            "Technology": ["quantum computing", "cryptography", "AI"],
            "Healthcare": ["healthcare", "industry", "transformation"]
          }
        }
        """
        let mockService = MockLLMService(
            name: "MockService",
            expectedResult: .success(MockLLMResponse(text: mockResponseText))
        )

        let task = GenerateKeywordsLLMTask(
            llmService: mockService,
            strings: stringsToAnalyze,
            categories: predefinedCategories
        )

        // When
        guard case let .task(unwrappedTask) = task.toComponent() else {
            XCTFail("Failed to unwrap Workflow.Task.")
            return
        }
        let outputs = try await unwrappedTask.execute()

        // Then
        guard let categorizedKeywords = outputs["categorizedKeywords"] as? [String: [String]] else {
            XCTFail("Output 'categorizedKeywords' not found or invalid.")
            return
        }
        XCTAssertEqual(categorizedKeywords["Technology"], ["quantum computing", "cryptography", "AI"], "Technology keywords should match.")
        XCTAssertEqual(categorizedKeywords["Healthcare"], ["healthcare", "industry", "transformation"], "Healthcare keywords should match.")
    }

    func testGenerateKeywordsLLMTaskEmptyInput() async {
        // Given
        let mockService = MockLLMService(
            name: "MockService",
            expectedResult: .success(MockLLMResponse(text: "{}"))
        )
        let task = GenerateKeywordsLLMTask(
            llmService: mockService,
            strings: []
        )

        // When/Then
        do {
            guard case let .task(unwrappedTask) = task.toComponent() else {
                XCTFail("Failed to unwrap Workflow.Task.")
                return
            }
            _ = try await unwrappedTask.execute()
            XCTFail("Expected an error to be thrown for empty input, but no error was thrown.")
        } catch {
            XCTAssertEqual((error as NSError).domain, "GenerateKeywordsLLMTask", "Error domain should match.")
            XCTAssertEqual((error as NSError).code, 1, "Error code should match for empty input.")
        }
    }

    func testGenerateKeywordsLLMTaskIntegrationWithOllama() async throws {
        // Given
        let stringsToAnalyze = [
            "Self-driving cars are shaping the future of transportation.",
            "Renewable energy sources like solar and wind are crucial for sustainability."
        ]

        let ollamaService = OllamaService(name: "OllamaTest")
        let task = GenerateKeywordsLLMTask(llmService: ollamaService, strings: stringsToAnalyze)

        // When
        guard case let .task(unwrappedTask) = task.toComponent() else {
            XCTFail("Failed to unwrap Workflow.Task.")
            return
        }
        let outputs = try await unwrappedTask.execute()

        // Then
        guard let keywords = outputs["keywords"] as? [String: [String]] else {
            XCTFail("Output 'keywords' not found or invalid.")
            return
        }

        // Verify at least one keyword per string
        for string in stringsToAnalyze {
            XCTAssertFalse(keywords[string]?.isEmpty ?? true, "Keywords for '\(string)' should not be empty.")
        }

        // Print results for inspection
        print("Integration test results: \(keywords)")
    }
}

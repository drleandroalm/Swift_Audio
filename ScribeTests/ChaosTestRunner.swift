import Foundation
import XCTest
@testable import SwiftScribe

/// Chaos Test Runner - Orchestrates execution of all chaos scenarios
/// Generates comprehensive resilience scorecard with detailed metrics
///
/// **Usage**:
/// ```swift
/// let runner = ChaosTestRunner()
/// let results = await runner.runAllScenarios()
/// let scorecard = runner.generateScorecard(results)
/// try runner.saveScorecard(scorecard, to: "test_artifacts/ResilienceScorecard.json")
/// ```
///
/// **Output**: JSON scorecard with per-scenario metrics and overall resilience score
@MainActor
class ChaosTestRunner {

    // MARK: - Types

    /// Result of a single chaos scenario execution
    struct ScenarioResult: Codable {
        let scenario: String
        let category: String
        let passed: Bool
        let recoveryTimeMs: Double
        let userImpact: String
        let resilienceScore: Double
        let error: String?
        let details: [String: CodableValue]

        enum CodingKeys: String, CodingKey {
            case scenario, category, passed
            case recoveryTimeMs = "recovery_time_ms"
            case userImpact = "user_impact"
            case resilienceScore = "resilience_score"
            case error, details
        }
    }

    /// Resilience scorecard output format
    struct ResilienceScorecard: Codable {
        let testRun: TestRunMetadata
        let scenarios: [ScenarioResult]
        let categoryScores: [String: Double]
        let recommendations: [String]

        struct TestRunMetadata: Codable {
            let timestamp: String
            let durationSeconds: Double
            let scenariosExecuted: Int
            let scenariosPassed: Int
            let overallResilienceScore: Double

            enum CodingKeys: String, CodingKey {
                case timestamp
                case durationSeconds = "duration_seconds"
                case scenariosExecuted = "scenarios_executed"
                case scenariosPassed = "scenarios_passed"
                case overallResilienceScore = "overall_resilience_score"
            }
        }

        enum CodingKeys: String, CodingKey {
            case testRun = "test_run"
            case scenarios
            case categoryScores = "category_scores"
            case recommendations
        }
    }

    /// Codable wrapper for heterogeneous dictionary values
    enum CodableValue: Codable {
        case int(Int)
        case double(Double)
        case string(String)
        case bool(Bool)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else if let doubleValue = try? container.decode(Double.self) {
                self = .double(doubleValue)
            } else if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let boolValue = try? container.decode(Bool.self) {
                self = .bool(boolValue)
            } else {
                throw DecodingError.typeMismatch(
                    CodableValue.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            }
        }
    }

    // MARK: - Properties

    private let testSuite: XCTestSuite

    // MARK: - Initialization

    init() {
        // Get ChaosScenarios test suite
        self.testSuite = ChaosScenarios.defaultTestSuite
    }

    // MARK: - Scenario Execution

    /// Run all chaos scenarios and collect results
    /// Returns array of scenario results with metrics
    func runAllScenarios() async -> [ScenarioResult] {
        var results: [ScenarioResult] = []

        print("[ChaosRunner] Starting chaos engineering test suite...")
        print("[ChaosRunner] Total scenarios: \(testSuite.testCaseCount)")

        let overallStartTime = CFAbsoluteTimeGetCurrent()

        for test in testSuite.tests {
            guard let testCase = test as? XCTestCase else { continue }

            // Reset chaos state before each scenario
            ChaosFlags.reset()
            ChaosMetrics.current.reset()

            print("[ChaosRunner] Running: \(testCase.name)")

            let scenarioStartTime = CFAbsoluteTimeGetCurrent()

            // Run the test
            testCase.run()

            let scenarioDuration = (CFAbsoluteTimeGetCurrent() - scenarioStartTime) * 1000

            // Collect results
            let result = buildScenarioResult(
                testCase: testCase,
                durationMs: scenarioDuration
            )

            results.append(result)

            print("[ChaosRunner] Completed: \(testCase.name) - Score: \(String(format: "%.1f", result.resilienceScore))")
        }

        let overallDuration = CFAbsoluteTimeGetCurrent() - overallStartTime
        print("[ChaosRunner] All scenarios completed in \(String(format: "%.1f", overallDuration))s")

        return results
    }

    /// Build scenario result from test case execution
    private func buildScenarioResult(testCase: XCTestCase, durationMs: Double) -> ScenarioResult {
        let testName = extractScenarioName(from: testCase.name)
        let category = extractCategory(from: testName)
        let passed = testCase.testRun?.hasSucceeded ?? false
        let metrics = ChaosMetrics.current

        // Use metrics recovery time if available, otherwise use test duration
        let recoveryTime = metrics.recoveryTimeMs > 0 ? metrics.recoveryTimeMs : durationMs

        let resilienceScore = metrics.calculateResilienceScore()

        // Collect error if test failed
        var errorMessage: String?
        if let failures = testCase.testRun?.failures, !failures.isEmpty {
            errorMessage = failures.map { $0.compactDescription }.joined(separator: "; ")
        }

        // Build detailed metrics
        let details = buildDetailsDict(metrics: metrics)

        return ScenarioResult(
            scenario: testName,
            category: category,
            passed: passed,
            recoveryTimeMs: recoveryTime,
            userImpact: metrics.userImpact.rawValue,
            resilienceScore: resilienceScore,
            error: errorMessage,
            details: details
        )
    }

    /// Extract scenario name from test method name
    private func extractScenarioName(from testName: String) -> String {
        // Format: "-[ChaosScenarios test_Chaos01_BufferOverflow_GracefulRejection]"
        // Extract: "BufferOverflow"
        let components = testName.components(separatedBy: "_")
        if components.count >= 3 {
            return components[2] // "BufferOverflow"
        }
        return testName
    }

    /// Extract category from scenario name
    private func extractCategory(from scenarioName: String) -> String {
        // Map scenario names to categories
        let audioPipeline = ["BufferOverflow", "FormatMismatch", "FirstBufferTimeout",
                            "ConverterFailure", "RouteChangeDuringRecording", "CorruptAudioBuffers"]
        let mlModel = ["MissingSegmentationModel", "InvalidEmbeddings", "ANEAllocationFailure"]
        let speechFramework = ["LocaleUnavailable", "ModelDownloadFailure", "EmptyTranscriptionResults"]
        let swiftData = ["SaveFailure", "ConcurrentWriteConflict"]
        let systemResources = ["MemoryPressure", "PermissionDenial"]

        if audioPipeline.contains(scenarioName) {
            return "Audio Pipeline"
        } else if mlModel.contains(scenarioName) {
            return "ML Model"
        } else if speechFramework.contains(scenarioName) {
            return "Speech Framework"
        } else if swiftData.contains(scenarioName) {
            return "SwiftData"
        } else if systemResources.contains(scenarioName) {
            return "System Resources"
        } else {
            return "Unknown"
        }
    }

    /// Build details dictionary from chaos metrics
    private func buildDetailsDict(metrics: ChaosMetrics) -> [String: CodableValue] {
        var details: [String: CodableValue] = [:]

        // Audio Pipeline
        if metrics.oversizedBuffersInjected > 0 {
            details["oversized_buffers_injected"] = .int(metrics.oversizedBuffersInjected)
            details["oversized_buffers_rejected"] = .int(metrics.oversizedBuffersRejected)
        }
        if metrics.corruptedBuffersInjected > 0 {
            details["corrupted_buffers_injected"] = .int(metrics.corruptedBuffersInjected)
            details["corrupted_buffers_dropped"] = .int(metrics.corruptedBuffersDropped)
        }
        if metrics.watchdogTimeoutsForced > 0 {
            details["watchdog_timeouts_forced"] = .int(metrics.watchdogTimeoutsForced)
            details["watchdog_recoveries_observed"] = .int(metrics.watchdogRecoveriesObserved)
        }
        if metrics.converterFailuresInjected > 0 {
            details["converter_failures_injected"] = .int(metrics.converterFailuresInjected)
            details["converter_fallbacks_observed"] = .int(metrics.converterFallbacksObserved)
        }
        if metrics.formatMismatchesInjected > 0 {
            details["format_mismatches_injected"] = .int(metrics.formatMismatchesInjected)
            details["format_conversions_successful"] = .int(metrics.formatConversionsSuccessful)
        }

        // ML Model
        if metrics.missingModelsInjected > 0 {
            details["missing_models_injected"] = .int(metrics.missingModelsInjected)
            details["model_load_graceful_degradations"] = .int(metrics.modelLoadGracefulDegradations)
        }
        if metrics.invalidEmbeddingsInjected > 0 {
            details["invalid_embeddings_injected"] = .int(metrics.invalidEmbeddingsInjected)
            details["invalid_embeddings_rejected"] = .int(metrics.invalidEmbeddingsRejected)
        }
        if metrics.aneFailuresInjected > 0 {
            details["ane_failures_injected"] = .int(metrics.aneFailuresInjected)
            details["ane_fallbacks_observed"] = .int(metrics.aneFallbacksObserved)
        }

        // Speech Framework
        if metrics.localeFailuresInjected > 0 {
            details["locale_failures_injected"] = .int(metrics.localeFailuresInjected)
            details["locale_fallbacks_observed"] = .int(metrics.localeFallbacksObserved)
        }
        if metrics.emptyResultsInjected > 0 {
            details["empty_results_injected"] = .int(metrics.emptyResultsInjected)
            details["empty_results_handled_gracefully"] = .int(metrics.emptyResultsHandledGracefully)
        }

        // SwiftData
        if metrics.saveFailuresInjected > 0 {
            details["save_failures_injected"] = .int(metrics.saveFailuresInjected)
            details["save_retries_observed"] = .int(metrics.saveRetriesObserved)
        }

        // System Resources
        if metrics.memoryPressureInjected {
            details["memory_pressure_injected"] = .bool(true)
            details["adaptive_backpressure_triggered"] = .bool(metrics.adaptiveBackpressureTriggered)
        }
        if metrics.permissionDenialsInjected > 0 {
            details["permission_denials_injected"] = .int(metrics.permissionDenialsInjected)
        }

        // General
        details["crashes"] = .int(metrics.crashCount)

        return details
    }

    // MARK: - Scorecard Generation

    /// Generate comprehensive resilience scorecard from results
    func generateScorecard(_ results: [ScenarioResult]) -> ResilienceScorecard {
        let passedCount = results.filter { $0.passed }.count
        let overallScore = calculateOverallScore(results)
        let categoryScores = calculateCategoryScores(results)
        let recommendations = generateRecommendations(results)

        let metadata = ResilienceScorecard.TestRunMetadata(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            durationSeconds: results.reduce(0) { $0 + $1.recoveryTimeMs } / 1000.0,
            scenariosExecuted: results.count,
            scenariosPassed: passedCount,
            overallResilienceScore: overallScore
        )

        return ResilienceScorecard(
            testRun: metadata,
            scenarios: results,
            categoryScores: categoryScores,
            recommendations: recommendations
        )
    }

    /// Calculate overall resilience score (weighted average of all scenarios)
    private func calculateOverallScore(_ results: [ScenarioResult]) -> Double {
        guard !results.isEmpty else { return 0.0 }

        let totalScore = results.reduce(0.0) { $0 + $1.resilienceScore }
        return totalScore / Double(results.count)
    }

    /// Calculate per-category resilience scores
    private func calculateCategoryScores(_ results: [ScenarioResult]) -> [String: Double] {
        var categoryScores: [String: Double] = [:]

        // Group results by category
        let groupedResults = Dictionary(grouping: results, by: { $0.category })

        for (category, categoryResults) in groupedResults {
            let categoryScore = categoryResults.reduce(0.0) { $0 + $1.resilienceScore } / Double(categoryResults.count)
            categoryScores[category] = categoryScore
        }

        return categoryScores
    }

    /// Generate actionable recommendations based on results
    private func generateRecommendations(_ results: [ScenarioResult]) -> [String] {
        var recommendations: [String] = []

        // Find scenarios with low scores (<50)
        let weakScenarios = results.filter { $0.resilienceScore < 50 }

        for scenario in weakScenarios {
            switch scenario.scenario {
            case "SaveFailure":
                recommendations.append("Implement retry logic for SwiftData save failures (currently no retries)")
            case "ModelDownloadFailure":
                recommendations.append("Add offline model bundling to eliminate download dependency")
            case "ConverterFailure":
                recommendations.append("Add fallback audio format conversion path")
            case "PermissionDenial":
                recommendations.append("Improve permission denial UX with Settings deep link")
            default:
                recommendations.append("Improve resilience for \(scenario.scenario) (score: \(String(format: "%.1f", scenario.resilienceScore)))")
            }
        }

        // Find scenarios with high recovery time (>5s)
        let slowRecoveries = results.filter { $0.recoveryTimeMs > 5000 }
        for scenario in slowRecoveries {
            recommendations.append("Optimize recovery time for \(scenario.scenario) (currently \(Int(scenario.recoveryTimeMs))ms)")
        }

        // Find "broken" user impact scenarios
        let brokenScenarios = results.filter { $0.userImpact == "broken" }
        if !brokenScenarios.isEmpty {
            recommendations.append("Critical: \(brokenScenarios.count) scenarios result in broken user experience")
        }

        // If no recommendations, provide positive feedback
        if recommendations.isEmpty {
            recommendations.append("Excellent resilience across all scenarios! No critical improvements needed.")
        }

        return recommendations
    }

    // MARK: - Persistence

    /// Save scorecard to JSON file
    func saveScorecard(_ scorecard: ResilienceScorecard, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(scorecard)
        let url = URL(fileURLWithPath: path)

        try data.write(to: url)

        print("[ChaosRunner] Scorecard saved to: \(path)")
    }

    /// Load scorecard from JSON file
    func loadScorecard(from path: String) throws -> ResilienceScorecard {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        return try decoder.decode(ResilienceScorecard.self, from: data)
    }

    // MARK: - Reporting

    /// Print scorecard summary to console
    func printSummary(_ scorecard: ResilienceScorecard) {
        print("""

        ╔═══════════════════════════════════════════════════════════════════╗
        ║           CHAOS ENGINEERING RESILIENCE SCORECARD                  ║
        ╚═══════════════════════════════════════════════════════════════════╝

        Test Run: \(scorecard.testRun.timestamp)
        Duration: \(String(format: "%.1f", scorecard.testRun.durationSeconds))s
        Scenarios: \(scorecard.testRun.scenariosExecuted) (\(scorecard.testRun.scenariosPassed) passed)

        OVERALL RESILIENCE SCORE: \(String(format: "%.1f", scorecard.testRun.overallResilienceScore))/100

        Category Scores:
        """)

        for (category, score) in scorecard.categoryScores.sorted(by: { $0.value > $1.value }) {
            let bar = String(repeating: "█", count: Int(score / 5))
            let emoji = score >= 80 ? "✅" : score >= 60 ? "⚠️" : "❌"
            print("  \(emoji) \(category.padding(toLength: 25, withPad: " ", startingAt: 0)): \(String(format: "%5.1f", score))/100 \(bar)")
        }

        print("\nTop 5 Scenarios (by score):")
        let topScenarios = scorecard.scenarios.sorted { $0.resilienceScore > $1.resilienceScore }.prefix(5)
        for (index, scenario) in topScenarios.enumerated() {
            let emoji = scenario.passed ? "✅" : "❌"
            print("  \(index + 1). \(emoji) \(scenario.scenario.padding(toLength: 30, withPad: " ", startingAt: 0)): \(String(format: "%.1f", scenario.resilienceScore))/100")
        }

        print("\nBottom 5 Scenarios (need improvement):")
        let bottomScenarios = scorecard.scenarios.sorted { $0.resilienceScore < $1.resilienceScore }.prefix(5)
        for (index, scenario) in bottomScenarios.enumerated() {
            let emoji = scenario.resilienceScore < 50 ? "🔴" : "🟡"
            print("  \(index + 1). \(emoji) \(scenario.scenario.padding(toLength: 30, withPad: " ", startingAt: 0)): \(String(format: "%.1f", scenario.resilienceScore))/100")
        }

        if !scorecard.recommendations.isEmpty {
            print("\nRecommendations:")
            for (index, recommendation) in scorecard.recommendations.enumerated() {
                print("  \(index + 1). \(recommendation)")
            }
        }

        print("""

        ═══════════════════════════════════════════════════════════════════

        """)
    }
}

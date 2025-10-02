#!/usr/bin/env swift
// Regression Detection System for Swift Scribe
// Detects performance regressions by comparing current test run against historical averages
// Exit code 1 if critical regressions detected (fails CI build)

import Foundation

// MARK: - Models

struct TestRun: Codable {
    let id: Int
    let timestamp: String
    let commitSha: String
    let branch: String
    let overallResilienceScore: Double
    let totalTests: Int
    let passedTests: Int
    let failedTests: Int

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case commitSha = "commit_sha"
        case branch
        case overallResilienceScore = "overall_resilience_score"
        case totalTests = "total_tests"
        case passedTests = "passed_tests"
        case failedTests = "failed_tests"
    }
}

struct CategoryScore: Codable {
    let runId: Int
    let category: String
    let score: Double
    let scenarioCount: Int
    let passedCount: Int

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case category
        case score
        case scenarioCount = "scenario_count"
        case passedCount = "passed_count"
    }
}

struct ScenarioResult: Codable {
    let runId: Int
    let scenario: String
    let category: String
    let passed: Bool
    let recoveryTimeMs: Double?
    let userImpact: String
    let resilienceScore: Double
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case scenario
        case category
        case passed
        case recoveryTimeMs = "recovery_time_ms"
        case userImpact = "user_impact"
        case resilienceScore = "resilience_score"
        case errorMessage = "error_message"
    }
}

struct RegressionAlert: Codable {
    let alertType: String
    let severity: String
    let description: String
    let currentValue: Double?
    let previousValue: Double?
    let changePercent: Double?
    let affectedEntity: String

    enum CodingKeys: String, CodingKey {
        case alertType = "alert_type"
        case severity
        case description
        case currentValue = "current_value"
        case previousValue = "previous_value"
        case changePercent = "change_percent"
        case affectedEntity = "affected_entity"
    }
}

// MARK: - SQLite Helper

class SQLiteHelper {
    let dbPath: String

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    func query(_ sql: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, sql]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error running sqlite3: \(error)")
            return nil
        }
    }

    func queryJSON(_ sql: String) -> Data? {
        guard let result = query(sql) else { return nil }
        return result.data(using: .utf8)
    }
}

// MARK: - Regression Detector

class RegressionDetector {
    let db: SQLiteHelper
    let regressionThreshold: Double = 0.10  // 10% drop is regression
    let criticalScoreThreshold: Double = 50.0
    var alerts: [RegressionAlert] = []

    init(dbPath: String) {
        self.db = SQLiteHelper(dbPath: dbPath)
    }

    func detectRegressions() -> Bool {
        print("🔍 Regression Detection Analysis")
        print("=" * 60)

        guard let latestRun = fetchLatestRun() else {
            print("❌ No test runs found in database")
            return false
        }

        print("Latest Run:")
        print("  Timestamp: \(latestRun.timestamp)")
        print("  Commit: \(latestRun.commitSha.prefix(7))")
        print("  Branch: \(latestRun.branch)")
        print("  Overall Score: \(String(format: "%.1f", latestRun.overallResilienceScore))")
        print("  Tests: \(latestRun.passedTests)/\(latestRun.totalTests) passed")
        print("")

        // Check overall score regression
        checkOverallScoreRegression(currentRun: latestRun)

        // Check category score regressions
        checkCategoryRegressions(currentRunId: latestRun.id)

        // Check for newly failing scenarios
        checkNewlyFailingScenarios(currentRunId: latestRun.id)

        // Check for critical scenario scores
        checkCriticalScenarios(currentRunId: latestRun.id)

        // Report findings
        reportFindings()

        // Record alerts to database
        recordAlerts(runId: latestRun.id)

        // Determine if build should fail
        let criticalAlertsCount = alerts.filter { $0.severity == "critical" }.count
        return criticalAlertsCount > 0
    }

    private func fetchLatestRun() -> TestRun? {
        let sql = """
        SELECT id, timestamp, commit_sha, branch, overall_resilience_score,
               total_tests, passed_tests, failed_tests
        FROM test_runs
        ORDER BY timestamp DESC
        LIMIT 1;
        """

        guard let output = db.query(sql), !output.isEmpty else { return nil }

        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        guard parts.count >= 8 else { return nil }

        return TestRun(
            id: Int(parts[0]) ?? 0,
            timestamp: String(parts[1]),
            commitSha: String(parts[2]),
            branch: String(parts[3]),
            overallResilienceScore: Double(parts[4]) ?? 0.0,
            totalTests: Int(parts[5]) ?? 0,
            passedTests: Int(parts[6]) ?? 0,
            failedTests: Int(parts[7]) ?? 0
        )
    }

    private func checkOverallScoreRegression(currentRun: TestRun) {
        // Get average of last 5 runs (excluding current)
        let sql = """
        SELECT AVG(overall_resilience_score) as avg_score
        FROM (
            SELECT overall_resilience_score
            FROM test_runs
            WHERE id != \(currentRun.id)
            ORDER BY timestamp DESC
            LIMIT 5
        );
        """

        guard let output = db.query(sql), !output.isEmpty else { return }
        let avgScore = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0

        if avgScore > 0 {
            let changePercent = ((currentRun.overallResilienceScore - avgScore) / avgScore) * 100

            if changePercent < -(regressionThreshold * 100) {
                // Score dropped more than threshold
                alerts.append(RegressionAlert(
                    alertType: "score_drop",
                    severity: "critical",
                    description: "Overall resilience score dropped by \(String(format: "%.1f", abs(changePercent)))%",
                    currentValue: currentRun.overallResilienceScore,
                    previousValue: avgScore,
                    changePercent: changePercent,
                    affectedEntity: "overall_score"
                ))
            } else if changePercent < 0 {
                // Score dropped but within threshold
                alerts.append(RegressionAlert(
                    alertType: "score_drop",
                    severity: "warning",
                    description: "Overall resilience score decreased by \(String(format: "%.1f", abs(changePercent)))%",
                    currentValue: currentRun.overallResilienceScore,
                    previousValue: avgScore,
                    changePercent: changePercent,
                    affectedEntity: "overall_score"
                ))
            } else if changePercent > 5 {
                // Score improved significantly
                alerts.append(RegressionAlert(
                    alertType: "score_drop",
                    severity: "info",
                    description: "Overall resilience score improved by \(String(format: "%.1f", changePercent))%",
                    currentValue: currentRun.overallResilienceScore,
                    previousValue: avgScore,
                    changePercent: changePercent,
                    affectedEntity: "overall_score"
                ))
            }
        }
    }

    private func checkCategoryRegressions(currentRunId: Int) {
        // Get current category scores
        let currentSQL = """
        SELECT category, score
        FROM category_scores
        WHERE run_id = \(currentRunId);
        """

        guard let currentOutput = db.query(currentSQL), !currentOutput.isEmpty else { return }

        let currentLines = currentOutput.split(separator: "\n")

        for line in currentLines {
            let parts = line.split(separator: "|")
            guard parts.count >= 2 else { continue }

            let category = String(parts[0])
            let currentScore = Double(parts[1]) ?? 0.0

            // Get average for this category from last 5 runs
            let avgSQL = """
            SELECT AVG(score) as avg_score
            FROM (
                SELECT cs.score
                FROM category_scores cs
                JOIN test_runs tr ON cs.run_id = tr.id
                WHERE cs.category = '\(category)'
                  AND tr.id != \(currentRunId)
                ORDER BY tr.timestamp DESC
                LIMIT 5
            );
            """

            guard let avgOutput = db.query(avgSQL), !avgOutput.isEmpty else { continue }
            let avgScore = Double(avgOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0

            if avgScore > 0 {
                let changePercent = ((currentScore - avgScore) / avgScore) * 100

                if changePercent < -(regressionThreshold * 100) {
                    alerts.append(RegressionAlert(
                        alertType: "metric_regression",
                        severity: "critical",
                        description: "\(category) score dropped by \(String(format: "%.1f", abs(changePercent)))%",
                        currentValue: currentScore,
                        previousValue: avgScore,
                        changePercent: changePercent,
                        affectedEntity: category
                    ))
                } else if changePercent < -5 {
                    alerts.append(RegressionAlert(
                        alertType: "metric_regression",
                        severity: "warning",
                        description: "\(category) score decreased by \(String(format: "%.1f", abs(changePercent)))%",
                        currentValue: currentScore,
                        previousValue: avgScore,
                        changePercent: changePercent,
                        affectedEntity: category
                    ))
                }
            }
        }
    }

    private func checkNewlyFailingScenarios(currentRunId: Int) {
        // Find scenarios that passed in previous runs but failed in current
        let sql = """
        SELECT
            current.scenario,
            current.category,
            current.resilience_score,
            current.error_message
        FROM scenario_results current
        WHERE current.run_id = \(currentRunId)
          AND current.passed = 0
          AND NOT EXISTS (
              SELECT 1
              FROM scenario_results prev
              JOIN test_runs tr ON prev.run_id = tr.id
              WHERE prev.scenario = current.scenario
                AND prev.run_id != \(currentRunId)
                AND prev.passed = 0
              ORDER BY tr.timestamp DESC
              LIMIT 1
          );
        """

        guard let output = db.query(sql), !output.isEmpty else { return }

        let lines = output.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: "|")
            guard parts.count >= 3 else { continue }

            let scenario = String(parts[0])
            let category = String(parts[1])
            let score = Double(parts[2]) ?? 0.0

            alerts.append(RegressionAlert(
                alertType: "new_failure",
                severity: "critical",
                description: "Scenario '\(scenario)' newly failing (previously passed)",
                currentValue: score,
                previousValue: nil,
                changePercent: nil,
                affectedEntity: scenario
            ))
        }
    }

    private func checkCriticalScenarios(currentRunId: Int) {
        // Find scenarios with critically low scores (<50)
        let sql = """
        SELECT scenario, category, resilience_score, user_impact
        FROM scenario_results
        WHERE run_id = \(currentRunId)
          AND resilience_score < \(criticalScoreThreshold)
          AND passed = 0;
        """

        guard let output = db.query(sql), !output.isEmpty else { return }

        let lines = output.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: "|")
            guard parts.count >= 4 else { continue }

            let scenario = String(parts[0])
            let score = Double(parts[2]) ?? 0.0
            let userImpact = String(parts[3])

            // Only alert if user impact is "broken"
            if userImpact == "broken" {
                alerts.append(RegressionAlert(
                    alertType: "scenario_fail",
                    severity: "critical",
                    description: "Critical failure: '\(scenario)' scored \(String(format: "%.1f", score)) with broken UX",
                    currentValue: score,
                    previousValue: nil,
                    changePercent: nil,
                    affectedEntity: scenario
                ))
            } else {
                alerts.append(RegressionAlert(
                    alertType: "scenario_fail",
                    severity: "warning",
                    description: "Low score: '\(scenario)' scored \(String(format: "%.1f", score))",
                    currentValue: score,
                    previousValue: nil,
                    changePercent: nil,
                    affectedEntity: scenario
                ))
            }
        }
    }

    private func reportFindings() {
        let criticalCount = alerts.filter { $0.severity == "critical" }.count
        let warningCount = alerts.filter { $0.severity == "warning" }.count
        let infoCount = alerts.filter { $0.severity == "info" }.count

        print("Findings:")
        print("  🔴 Critical: \(criticalCount)")
        print("  🟡 Warnings: \(warningCount)")
        print("  🔵 Info: \(infoCount)")
        print("")

        if alerts.isEmpty {
            print("✅ No regressions detected")
            return
        }

        // Print critical alerts
        let criticalAlerts = alerts.filter { $0.severity == "critical" }
        if !criticalAlerts.isEmpty {
            print("🔴 Critical Issues:")
            for alert in criticalAlerts {
                print("  - \(alert.description)")
                if let current = alert.currentValue, let previous = alert.previousValue {
                    print("    Current: \(String(format: "%.1f", current)), Previous: \(String(format: "%.1f", previous))")
                }
            }
            print("")
        }

        // Print warnings
        let warningAlerts = alerts.filter { $0.severity == "warning" }
        if !warningAlerts.isEmpty {
            print("🟡 Warnings:")
            for alert in warningAlerts {
                print("  - \(alert.description)")
            }
            print("")
        }

        // Print info
        let infoAlerts = alerts.filter { $0.severity == "info" }
        if !infoAlerts.isEmpty {
            print("🔵 Improvements:")
            for alert in infoAlerts {
                print("  - \(alert.description)")
            }
            print("")
        }
    }

    private func recordAlerts(runId: Int) {
        for alert in alerts {
            let currentValueSQL = alert.currentValue.map { String($0) } ?? "NULL"
            let previousValueSQL = alert.previousValue.map { String($0) } ?? "NULL"
            let changePercentSQL = alert.changePercent.map { String($0) } ?? "NULL"

            let escapedDescription = alert.description.replacingOccurrences(of: "'", with: "''")
            let escapedEntity = alert.affectedEntity.replacingOccurrences(of: "'", with: "''")

            let sql = """
            INSERT INTO regression_alerts (run_id, alert_type, severity, description, current_value, previous_value, change_percent, affected_entity)
            VALUES (\(runId), '\(alert.alertType)', '\(alert.severity)', '\(escapedDescription)', \(currentValueSQL), \(previousValueSQL), \(changePercentSQL), '\(escapedEntity)');
            """

            _ = db.query(sql)
        }
    }
}

// MARK: - Main

func main() {
    let args = CommandLine.arguments

    var dbPath = "test_artifacts/performance_trends.db"
    var command = "check"

    // Parse arguments
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--database":
            if i + 1 < args.count {
                dbPath = args[i + 1]
                i += 2
            } else {
                print("Error: --database requires a path argument")
                exit(1)
            }
        case "check", "report":
            command = args[i]
            i += 1
        default:
            print("Unknown argument: \(args[i])")
            print("Usage: detect_regressions.swift [check|report] [--database path]")
            exit(1)
        }
    }

    // Verify database exists
    guard FileManager.default.fileExists(atPath: dbPath) else {
        print("Error: Database not found at \(dbPath)")
        exit(1)
    }

    let detector = RegressionDetector(dbPath: dbPath)

    if command == "check" {
        let hasCriticalRegressions = detector.detectRegressions()

        if hasCriticalRegressions {
            print("")
            print("=" * 60)
            print("❌ BUILD FAILED: Critical regressions detected")
            print("=" * 60)
            exit(1)
        } else {
            print("")
            print("=" * 60)
            print("✅ BUILD PASSED: No critical regressions")
            print("=" * 60)
            exit(0)
        }
    } else if command == "report" {
        _ = detector.detectRegressions()
        exit(0)
    }
}

// String repetition helper
func * (left: String, right: Int) -> String {
    return String(repeating: left, count: right)
}

main()

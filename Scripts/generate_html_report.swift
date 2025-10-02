#!/usr/bin/env swift
// HTML Test Report Generator for Swift Scribe
// Generates interactive HTML dashboard with Chart.js visualizations
// Reads from SQLite database and ResilienceScorecard.json

import Foundation

// MARK: - Models

struct ReportData {
    let scoreTrend: [ScoreTrendPoint]
    let categoryTrends: [String: [CategoryTrendPoint]]
    let scenarioPassRates: [ScenarioPassRate]
    let recentAlerts: [RegressionAlert]
    let latestRun: TestRunSummary?
}

struct ScoreTrendPoint: Codable {
    let timestamp: String
    let score: Double
    let branch: String
}

struct CategoryTrendPoint: Codable {
    let timestamp: String
    let category: String
    let score: Double
}

struct ScenarioPassRate: Codable {
    let scenario: String
    let category: String
    let totalRuns: Int
    let passedRuns: Int
    let passRate: Double
    let avgScore: Double
}

struct RegressionAlert: Codable {
    let severity: String
    let description: String
    let timestamp: String
    let commitSha: String
}

struct TestRunSummary: Codable {
    let timestamp: String
    let commitSha: String
    let branch: String
    let overallScore: Double
    let totalTests: Int
    let passedTests: Int
    let failedTests: Int
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
}

// MARK: - Data Collector

class DataCollector {
    let db: SQLiteHelper

    init(dbPath: String) {
        self.db = SQLiteHelper(dbPath: dbPath)
    }

    func collectData() -> ReportData {
        let scoreTrend = fetchScoreTrend()
        let categoryTrends = fetchCategoryTrends()
        let scenarioPassRates = fetchScenarioPassRates()
        let recentAlerts = fetchRecentAlerts()
        let latestRun = fetchLatestRun()

        return ReportData(
            scoreTrend: scoreTrend,
            categoryTrends: categoryTrends,
            scenarioPassRates: scenarioPassRates,
            recentAlerts: recentAlerts,
            latestRun: latestRun
        )
    }

    private func fetchScoreTrend() -> [ScoreTrendPoint] {
        let sql = """
        SELECT timestamp, overall_resilience_score, branch
        FROM test_runs
        WHERE timestamp >= datetime('now', '-30 days')
        ORDER BY timestamp ASC
        LIMIT 50;
        """

        guard let output = db.query(sql), !output.isEmpty else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|")
            guard parts.count >= 3 else { return nil }
            return ScoreTrendPoint(
                timestamp: String(parts[0]),
                score: Double(parts[1]) ?? 0.0,
                branch: String(parts[2])
            )
        }
    }

    private func fetchCategoryTrends() -> [String: [CategoryTrendPoint]] {
        let sql = """
        SELECT tr.timestamp, cs.category, cs.score
        FROM category_scores cs
        JOIN test_runs tr ON cs.run_id = tr.id
        WHERE tr.timestamp >= datetime('now', '-30 days')
        ORDER BY tr.timestamp ASC, cs.category
        LIMIT 500;
        """

        guard let output = db.query(sql), !output.isEmpty else { return [:] }

        var trends: [String: [CategoryTrendPoint]] = [:]

        output.split(separator: "\n").forEach { line in
            let parts = line.split(separator: "|")
            guard parts.count >= 3 else { return }

            let timestamp = String(parts[0])
            let category = String(parts[1])
            let score = Double(parts[2]) ?? 0.0

            let point = CategoryTrendPoint(timestamp: timestamp, category: category, score: score)

            if trends[category] == nil {
                trends[category] = []
            }
            trends[category]?.append(point)
        }

        return trends
    }

    private func fetchScenarioPassRates() -> [ScenarioPassRate] {
        let sql = """
        SELECT
            scenario,
            category,
            COUNT(*) as total_runs,
            SUM(passed) as passed_runs,
            ROUND(100.0 * SUM(passed) / COUNT(*), 2) as pass_rate,
            AVG(resilience_score) as avg_score
        FROM scenario_results sr
        JOIN test_runs tr ON sr.run_id = tr.id
        WHERE tr.id IN (SELECT id FROM test_runs ORDER BY timestamp DESC LIMIT 30)
        GROUP BY scenario, category
        ORDER BY pass_rate ASC, avg_score ASC
        LIMIT 50;
        """

        guard let output = db.query(sql), !output.isEmpty else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|")
            guard parts.count >= 6 else { return nil }
            return ScenarioPassRate(
                scenario: String(parts[0]),
                category: String(parts[1]),
                totalRuns: Int(parts[2]) ?? 0,
                passedRuns: Int(parts[3]) ?? 0,
                passRate: Double(parts[4]) ?? 0.0,
                avgScore: Double(parts[5]) ?? 0.0
            )
        }
    }

    private func fetchRecentAlerts() -> [RegressionAlert] {
        let sql = """
        SELECT ra.severity, ra.description, tr.timestamp, tr.commit_sha
        FROM regression_alerts ra
        JOIN test_runs tr ON ra.run_id = tr.id
        WHERE tr.timestamp >= datetime('now', '-7 days')
        ORDER BY ra.severity DESC, tr.timestamp DESC
        LIMIT 50;
        """

        guard let output = db.query(sql), !output.isEmpty else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|")
            guard parts.count >= 4 else { return nil }
            return RegressionAlert(
                severity: String(parts[0]),
                description: String(parts[1]),
                timestamp: String(parts[2]),
                commitSha: String(parts[3])
            )
        }
    }

    private func fetchLatestRun() -> TestRunSummary? {
        let sql = """
        SELECT timestamp, commit_sha, branch, overall_resilience_score,
               total_tests, passed_tests, failed_tests
        FROM test_runs
        ORDER BY timestamp DESC
        LIMIT 1;
        """

        guard let output = db.query(sql), !output.isEmpty else { return nil }

        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        guard parts.count >= 7 else { return nil }

        return TestRunSummary(
            timestamp: String(parts[0]),
            commitSha: String(parts[1]),
            branch: String(parts[2]),
            overallScore: Double(parts[3]) ?? 0.0,
            totalTests: Int(parts[4]) ?? 0,
            passedTests: Int(parts[5]) ?? 0,
            failedTests: Int(parts[6]) ?? 0
        )
    }
}

// MARK: - HTML Generator

class HTMLGenerator {
    func generate(data: ReportData) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Swift Scribe Test Dashboard</title>
            <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
            <style>
                \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <h1>🎙️ Swift Scribe Test Dashboard</h1>
                <p class="subtitle">Resilience Engineering & Performance Tracking</p>
            </header>

            <div class="container">
                \(generateSummaryCards(data: data))
                \(generateCharts(data: data))
                \(generateScenarioTable(data: data))
                \(generateAlertsTable(data: data))
            </div>

            <footer>
                <p>Generated on \(formatDate(Date())) | <a href="https://github.com/yourusername/swift-scribe">Swift Scribe</a></p>
            </footer>

            <script>
                \(generateJavaScript(data: data))
            </script>
        </body>
        </html>
        """
    }

    private func generateCSS() -> String {
        return """
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            line-height: 1.6;
        }

        header {
            background: rgba(255, 255, 255, 0.95);
            padding: 2rem;
            text-align: center;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }

        header h1 {
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
            color: #667eea;
        }

        .subtitle {
            color: #666;
            font-size: 1.1rem;
        }

        .container {
            max-width: 1400px;
            margin: 2rem auto;
            padding: 0 1rem;
        }

        .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }

        .card {
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            transition: transform 0.2s;
        }

        .card:hover {
            transform: translateY(-5px);
        }

        .card h3 {
            font-size: 0.9rem;
            text-transform: uppercase;
            color: #999;
            margin-bottom: 0.5rem;
            letter-spacing: 0.5px;
        }

        .card .value {
            font-size: 2.5rem;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 0.5rem;
        }

        .card .label {
            font-size: 0.85rem;
            color: #666;
        }

        .card.success .value { color: #48bb78; }
        .card.warning .value { color: #ed8936; }
        .card.error .value { color: #f56565; }

        .chart-container {
            background: white;
            border-radius: 12px;
            padding: 2rem;
            margin-bottom: 2rem;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }

        .chart-container h2 {
            margin-bottom: 1.5rem;
            color: #667eea;
            font-size: 1.5rem;
        }

        canvas {
            max-height: 400px;
        }

        table {
            width: 100%;
            background: white;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            margin-bottom: 2rem;
        }

        table th {
            background: #667eea;
            color: white;
            padding: 1rem;
            text-align: left;
            font-weight: 600;
        }

        table td {
            padding: 1rem;
            border-bottom: 1px solid #eee;
        }

        table tr:last-child td {
            border-bottom: none;
        }

        table tr:hover {
            background: #f7fafc;
        }

        .badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 12px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
        }

        .badge.critical {
            background: #fed7d7;
            color: #c53030;
        }

        .badge.warning {
            background: #feebc8;
            color: #c05621;
        }

        .badge.info {
            background: #bee3f8;
            color: #2c5282;
        }

        .badge.success {
            background: #c6f6d5;
            color: #22543d;
        }

        footer {
            background: rgba(255, 255, 255, 0.95);
            padding: 1.5rem;
            text-align: center;
            margin-top: 2rem;
            color: #666;
        }

        footer a {
            color: #667eea;
            text-decoration: none;
        }

        footer a:hover {
            text-decoration: underline;
        }

        .progress-bar {
            background: #e2e8f0;
            border-radius: 8px;
            height: 8px;
            overflow: hidden;
            margin-top: 0.5rem;
        }

        .progress-bar-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea, #764ba2);
            transition: width 0.3s;
        }
        """
    }

    private func generateSummaryCards(data: ReportData) -> String {
        guard let latest = data.latestRun else {
            return "<div class='summary-cards'><p>No test data available</p></div>"
        }

        let passRate = latest.totalTests > 0 ? Double(latest.passedTests) / Double(latest.totalTests) * 100 : 0

        let scoreClass = latest.overallScore >= 80 ? "success" : (latest.overallScore >= 60 ? "warning" : "error")
        let passRateClass = passRate >= 90 ? "success" : (passRate >= 75 ? "warning" : "error")

        return """
        <div class="summary-cards">
            <div class="card \(scoreClass)">
                <h3>Resilience Score</h3>
                <div class="value">\(String(format: "%.1f", latest.overallScore))</div>
                <div class="label">Overall System Resilience</div>
                <div class="progress-bar">
                    <div class="progress-bar-fill" style="width: \(latest.overallScore)%"></div>
                </div>
            </div>

            <div class="card \(passRateClass)">
                <h3>Pass Rate</h3>
                <div class="value">\(String(format: "%.1f", passRate))%</div>
                <div class="label">\(latest.passedTests)/\(latest.totalTests) scenarios passed</div>
                <div class="progress-bar">
                    <div class="progress-bar-fill" style="width: \(passRate)%"></div>
                </div>
            </div>

            <div class="card">
                <h3>Latest Run</h3>
                <div class="value" style="font-size: 1.2rem;">\(latest.commitSha.prefix(7))</div>
                <div class="label">\(latest.branch) branch</div>
                <div class="label" style="margin-top: 0.5rem;">\(formatDate(parseISO8601(latest.timestamp)))</div>
            </div>

            <div class="card \(data.recentAlerts.filter { $0.severity == "critical" }.isEmpty ? "success" : "error")">
                <h3>Recent Alerts</h3>
                <div class="value">\(data.recentAlerts.filter { $0.severity == "critical" }.count)</div>
                <div class="label">Critical regressions (7 days)</div>
            </div>
        </div>
        """
    }

    private func generateCharts(data: ReportData) -> String {
        return """
        <div class="chart-container">
            <h2>📈 Resilience Score Trend (30 Days)</h2>
            <canvas id="scoreTrendChart"></canvas>
        </div>

        <div class="chart-container">
            <h2>📊 Category Scores Over Time</h2>
            <canvas id="categoryTrendChart"></canvas>
        </div>

        <div class="chart-container">
            <h2>🎯 Scenario Pass Rates (Last 30 Runs)</h2>
            <canvas id="scenarioPassRateChart"></canvas>
        </div>
        """
    }

    private func generateScenarioTable(data: ReportData) -> String {
        if data.scenarioPassRates.isEmpty {
            return ""
        }

        let rows = data.scenarioPassRates.prefix(20).map { scenario in
            let passRateClass = scenario.passRate >= 90 ? "success" : (scenario.passRate >= 75 ? "warning" : "critical")
            return """
            <tr>
                <td><strong>\(scenario.scenario)</strong></td>
                <td>\(scenario.category)</td>
                <td><span class="badge \(passRateClass)">\(String(format: "%.1f", scenario.passRate))%</span></td>
                <td>\(scenario.passedRuns)/\(scenario.totalRuns)</td>
                <td>\(String(format: "%.1f", scenario.avgScore))</td>
            </tr>
            """
        }.joined()

        return """
        <div class="chart-container" style="padding: 0;">
            <table>
                <thead>
                    <tr>
                        <th>Scenario</th>
                        <th>Category</th>
                        <th>Pass Rate</th>
                        <th>Runs</th>
                        <th>Avg Score</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>
        </div>
        """
    }

    private func generateAlertsTable(data: ReportData) -> String {
        if data.recentAlerts.isEmpty {
            return """
            <div class="chart-container">
                <h2>🎉 No Recent Alerts</h2>
                <p style="color: #48bb78; font-size: 1.2rem;">All systems resilient!</p>
            </div>
            """
        }

        let rows = data.recentAlerts.prefix(10).map { alert in
            return """
            <tr>
                <td><span class="badge \(alert.severity)">\(alert.severity.uppercased())</span></td>
                <td>\(alert.description)</td>
                <td>\(alert.commitSha.prefix(7))</td>
                <td>\(formatDate(parseISO8601(alert.timestamp)))</td>
            </tr>
            """
        }.joined()

        return """
        <div class="chart-container" style="padding: 0;">
            <table>
                <thead>
                    <tr>
                        <th>Severity</th>
                        <th>Description</th>
                        <th>Commit</th>
                        <th>Time</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>
        </div>
        """
    }

    private func generateJavaScript(data: ReportData) -> String {
        let scoreTrendLabels = data.scoreTrend.map { formatDate(parseISO8601($0.timestamp)) }
        let scoreTrendData = data.scoreTrend.map { $0.score }

        let categoryNames = Array(data.categoryTrends.keys).sorted()
        let categoryDatasets = categoryNames.enumerated().map { (index, category) -> String in
            let points = data.categoryTrends[category] ?? []
            let scores = points.map { $0.score }
            let color = categoryColor(index: index)
            return """
            {
                label: '\(category)',
                data: \(toJSON(scores)),
                borderColor: '\(color)',
                backgroundColor: '\(color)33',
                tension: 0.3
            }
            """
        }.joined(separator: ",\n")

        let scenarioLabels = data.scenarioPassRates.prefix(15).map { $0.scenario }
        let scenarioPassRates = data.scenarioPassRates.prefix(15).map { $0.passRate }

        return """
        // Score Trend Chart
        const scoreTrendCtx = document.getElementById('scoreTrendChart').getContext('2d');
        new Chart(scoreTrendCtx, {
            type: 'line',
            data: {
                labels: \(toJSON(scoreTrendLabels)),
                datasets: [{
                    label: 'Overall Resilience Score',
                    data: \(toJSON(scoreTrendData)),
                    borderColor: '#667eea',
                    backgroundColor: '#667eea33',
                    borderWidth: 3,
                    tension: 0.4,
                    fill: true
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    legend: { display: true },
                    tooltip: { mode: 'index', intersect: false }
                },
                scales: {
                    y: { beginAtZero: true, max: 100, title: { display: true, text: 'Score' } },
                    x: { title: { display: true, text: 'Date' } }
                }
            }
        });

        // Category Trend Chart
        const categoryTrendCtx = document.getElementById('categoryTrendChart').getContext('2d');
        new Chart(categoryTrendCtx, {
            type: 'line',
            data: {
                labels: \(toJSON(scoreTrendLabels)),
                datasets: [\(categoryDatasets)]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    legend: { display: true },
                    tooltip: { mode: 'index', intersect: false }
                },
                scales: {
                    y: { beginAtZero: true, max: 100, title: { display: true, text: 'Score' } },
                    x: { title: { display: true, text: 'Date' } }
                }
            }
        });

        // Scenario Pass Rate Chart
        const scenarioPassRateCtx = document.getElementById('scenarioPassRateChart').getContext('2d');
        new Chart(scenarioPassRateCtx, {
            type: 'bar',
            data: {
                labels: \(toJSON(scenarioLabels)),
                datasets: [{
                    label: 'Pass Rate (%)',
                    data: \(toJSON(scenarioPassRates)),
                    backgroundColor: \(toJSON(scenarioPassRates.map { passRate in
                        passRate >= 90 ? "#48bb78" : (passRate >= 75 ? "#ed8936" : "#f56565")
                    }))
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    y: { beginAtZero: true, max: 100, title: { display: true, text: 'Pass Rate (%)' } },
                    x: { title: { display: true, text: 'Scenario' } }
                }
            }
        });
        """
    }

    private func categoryColor(index: Int) -> String {
        let colors = ["#667eea", "#f56565", "#48bb78", "#ed8936", "#9f7aea", "#38b2ac"]
        return colors[index % colors.count]
    }

    private func toJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy HH:mm"
        return formatter.string(from: date)
    }

    private func parseISO8601(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}

// MARK: - Main

func main() {
    let args = CommandLine.arguments

    var dbPath = "test_artifacts/performance_trends.db"
    var outputPath = "test_artifacts/html_report"

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
        case "--output":
            if i + 1 < args.count {
                outputPath = args[i + 1]
                i += 2
            } else {
                print("Error: --output requires a path argument")
                exit(1)
            }
        default:
            print("Unknown argument: \(args[i])")
            print("Usage: generate_html_report.swift [--database path] [--output path]")
            exit(1)
        }
    }

    print("📊 Generating HTML Test Report")
    print("=" * 60)

    // Verify database exists
    guard FileManager.default.fileExists(atPath: dbPath) else {
        print("❌ Error: Database not found at \(dbPath)")
        exit(1)
    }

    // Collect data
    print("📥 Collecting data from database...")
    let collector = DataCollector(dbPath: dbPath)
    let data = collector.collectData()

    print("  - Score trend: \(data.scoreTrend.count) points")
    print("  - Category trends: \(data.categoryTrends.count) categories")
    print("  - Scenario pass rates: \(data.scenarioPassRates.count) scenarios")
    print("  - Recent alerts: \(data.recentAlerts.count) alerts")

    // Generate HTML
    print("🎨 Generating HTML...")
    let generator = HTMLGenerator()
    let html = generator.generate(data: data)

    // Create output directory
    let fileManager = FileManager.default
    try? fileManager.createDirectory(atPath: outputPath, withIntermediateDirectories: true)

    // Write HTML file
    let indexPath = "\(outputPath)/index.html"
    do {
        try html.write(toFile: indexPath, atomically: true, encoding: .utf8)
        print("✅ Report generated: \(indexPath)")
    } catch {
        print("❌ Error writing HTML: \(error)")
        exit(1)
    }

    print("=" * 60)
    print("🎉 HTML report generation complete!")
}

// String repetition helper
func * (left: String, right: Int) -> String {
    return String(repeating: left, count: right)
}

main()

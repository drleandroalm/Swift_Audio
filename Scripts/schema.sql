-- Swift Scribe Performance Tracking Database Schema
-- SQLite database for storing test results, performance metrics, and trends

-- Test Runs Table
-- Stores metadata for each CI test run
CREATE TABLE IF NOT EXISTS test_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    commit_sha TEXT NOT NULL,
    branch TEXT NOT NULL,
    overall_resilience_score REAL,
    total_tests INTEGER DEFAULT 0,
    passed_tests INTEGER DEFAULT 0,
    failed_tests INTEGER DEFAULT 0,
    duration_seconds REAL DEFAULT 0.0,
    ci_run_id TEXT,  -- GitHub Actions run ID
    pr_number INTEGER  -- PR number if applicable
);

CREATE INDEX IF NOT EXISTS idx_test_runs_timestamp ON test_runs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_test_runs_commit ON test_runs(commit_sha);
CREATE INDEX IF NOT EXISTS idx_test_runs_branch ON test_runs(branch);

-- Scenario Results Table
-- Stores individual chaos scenario results
CREATE TABLE IF NOT EXISTS scenario_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    scenario TEXT NOT NULL,
    category TEXT NOT NULL,
    passed INTEGER NOT NULL CHECK (passed IN (0, 1)),
    recovery_time_ms REAL,
    user_impact TEXT CHECK (user_impact IN ('transparent', 'degraded', 'broken', 'unknown')),
    resilience_score REAL,
    error_message TEXT,
    details_json TEXT,  -- JSON blob for scenario-specific details
    FOREIGN KEY (run_id) REFERENCES test_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_scenario_results_run ON scenario_results(run_id);
CREATE INDEX IF NOT EXISTS idx_scenario_results_scenario ON scenario_results(scenario);

-- Category Scores Table
-- Aggregated scores per category (Audio Pipeline, ML Model, etc.)
CREATE TABLE IF NOT EXISTS category_scores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    category TEXT NOT NULL,
    score REAL NOT NULL CHECK (score >= 0 AND score <= 100),
    scenario_count INTEGER DEFAULT 0,
    passed_count INTEGER DEFAULT 0,
    FOREIGN KEY (run_id) REFERENCES test_runs(id) ON DELETE CASCADE,
    UNIQUE(run_id, category)
);

CREATE INDEX IF NOT EXISTS idx_category_scores_run ON category_scores(run_id);
CREATE INDEX IF NOT EXISTS idx_category_scores_category ON category_scores(category);

-- Performance Metrics Table
-- Stores latency, memory, and throughput measurements
CREATE TABLE IF NOT EXISTS performance_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    metric_name TEXT NOT NULL,
    value REAL NOT NULL,
    unit TEXT NOT NULL,
    percentile TEXT CHECK (percentile IN ('p50', 'p95', 'p99', 'slo', 'avg')),
    category TEXT,  -- e.g., 'transcription', 'diarization', 'memory'
    FOREIGN KEY (run_id) REFERENCES test_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_performance_metrics_run ON performance_metrics(run_id);
CREATE INDEX IF NOT EXISTS idx_performance_metrics_name ON performance_metrics(metric_name);

-- Regression Alerts Table
-- Records detected regressions
CREATE TABLE IF NOT EXISTS regression_alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    alert_type TEXT NOT NULL CHECK (alert_type IN ('score_drop', 'scenario_fail', 'metric_regression', 'new_failure')),
    severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
    description TEXT NOT NULL,
    current_value REAL,
    previous_value REAL,
    change_percent REAL,
    affected_entity TEXT,  -- Scenario name, category, or metric name
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (run_id) REFERENCES test_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_regression_alerts_run ON regression_alerts(run_id);
CREATE INDEX IF NOT EXISTS idx_regression_alerts_severity ON regression_alerts(severity);

-- Views for common queries

-- Latest test run view
CREATE VIEW IF NOT EXISTS latest_test_run AS
SELECT * FROM test_runs
ORDER BY timestamp DESC
LIMIT 1;

-- Score trend view (last 30 days)
CREATE VIEW IF NOT EXISTS score_trend_30d AS
SELECT
    timestamp,
    DATE(timestamp) as date,
    overall_resilience_score as score,
    branch,
    commit_sha
FROM test_runs
WHERE timestamp >= datetime('now', '-30 days')
ORDER BY timestamp ASC;

-- Category score trends
CREATE VIEW IF NOT EXISTS category_trends_30d AS
SELECT
    tr.timestamp,
    DATE(tr.timestamp) as date,
    cs.category,
    cs.score,
    tr.branch
FROM category_scores cs
JOIN test_runs tr ON cs.run_id = tr.id
WHERE tr.timestamp >= datetime('now', '-30 days')
ORDER BY tr.timestamp ASC, cs.category;

-- Scenario pass rate (last 30 runs)
CREATE VIEW IF NOT EXISTS scenario_pass_rates AS
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
ORDER BY pass_rate ASC, avg_score ASC;

-- Recent regressions
CREATE VIEW IF NOT EXISTS recent_regressions AS
SELECT
    ra.*,
    tr.timestamp,
    tr.commit_sha,
    tr.branch
FROM regression_alerts ra
JOIN test_runs tr ON ra.run_id = tr.id
WHERE tr.timestamp >= datetime('now', '-7 days')
ORDER BY ra.severity DESC, tr.timestamp DESC;

-- Insert initial baseline data (optional)
-- This can be used to seed the database with expected baseline values
INSERT OR IGNORE INTO test_runs (id, timestamp, commit_sha, branch, overall_resilience_score, total_tests, passed_tests)
VALUES (0, datetime('now'), 'baseline', 'main', 0.0, 0, 0);

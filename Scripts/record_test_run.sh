#!/bin/bash
# Record test run results to SQLite database
# Usage: ./record_test_run.sh --scorecard path/to/scorecard.json --commit SHA --branch main

set -euo pipefail

# Default values
DB_PATH="test_artifacts/performance_trends.db"
SCORECARD_PATH=""
COMMIT_SHA="${GITHUB_SHA:-unknown}"
BRANCH="${GITHUB_REF_NAME:-unknown}"
CI_RUN_ID="${GITHUB_RUN_ID:-}"
PR_NUMBER="${GITHUB_EVENT_PULL_REQUEST_NUMBER:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --scorecard)
            SCORECARD_PATH="$2"
            shift 2
            ;;
        --commit)
            COMMIT_SHA="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --database)
            DB_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$SCORECARD_PATH" ] || [ ! -f "$SCORECARD_PATH" ]; then
    echo "Error: Scorecard file not found: $SCORECARD_PATH"
    exit 1
fi

# Initialize database if doesn't exist
if [ ! -f "$DB_PATH" ]; then
    echo "Initializing performance database..."
    sqlite3 "$DB_PATH" < "$(dirname "$0")/schema.sql"
fi

# Extract metrics from scorecard JSON
OVERALL_SCORE=$(jq -r '.test_run.overall_resilience_score // 0' "$SCORECARD_PATH")
TOTAL_TESTS=$(jq -r '.test_run.scenarios_executed // 0' "$SCORECARD_PATH")
PASSED_TESTS=$(jq -r '.test_run.scenarios_passed // 0' "$SCORECARD_PATH")
DURATION=$(jq -r '.test_run.duration_seconds // 0' "$SCORECARD_PATH")
TIMESTAMP=$(jq -r '.test_run.timestamp // ""' "$SCORECARD_PATH")

# Use current timestamp if not in scorecard
if [ -z "$TIMESTAMP" ]; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "Recording test run:"
echo "  Timestamp: $TIMESTAMP"
echo "  Commit: $COMMIT_SHA"
echo "  Branch: $BRANCH"
echo "  Score: $OVERALL_SCORE"
echo "  Tests: $PASSED_TESTS/$TOTAL_TESTS passed"

# Insert test run
RUN_ID=$(sqlite3 "$DB_PATH" <<EOF
INSERT INTO test_runs (timestamp, commit_sha, branch, overall_resilience_score, total_tests, passed_tests, failed_tests, duration_seconds, ci_run_id, pr_number)
VALUES (
    '$TIMESTAMP',
    '$COMMIT_SHA',
    '$BRANCH',
    $OVERALL_SCORE,
    $TOTAL_TESTS,
    $PASSED_TESTS,
    $(($TOTAL_TESTS - $PASSED_TESTS)),
    $DURATION,
    $([ -n "$CI_RUN_ID" ] && echo "'$CI_RUN_ID'" || echo "NULL"),
    $([ -n "$PR_NUMBER" ] && echo "$PR_NUMBER" || echo "NULL")
);
SELECT last_insert_rowid();
EOF
)

echo "Test run recorded with ID: $RUN_ID"

# Insert scenario results
echo "Recording scenario results..."
jq -c '.scenarios[]' "$SCORECARD_PATH" | while read -r scenario; do
    SCENARIO_NAME=$(echo "$scenario" | jq -r '.scenario')
    CATEGORY=$(echo "$scenario" | jq -r '.category')
    PASSED=$(echo "$scenario" | jq -r 'if .passed then 1 else 0 end')
    RECOVERY_TIME=$(echo "$scenario" | jq -r '.recovery_time_ms // "NULL"')
    USER_IMPACT=$(echo "$scenario" | jq -r '.user_impact // "unknown"')
    RESILIENCE_SCORE=$(echo "$scenario" | jq -r '.resilience_score // 0')
    ERROR_MSG=$(echo "$scenario" | jq -r '.error // ""')
    DETAILS=$(echo "$scenario" | jq -c '.details // {}')

    # Escape single quotes in strings for SQL
    ERROR_MSG_ESCAPED=$(echo "$ERROR_MSG" | sed "s/'/''/g")
    DETAILS_ESCAPED=$(echo "$DETAILS" | sed "s/'/''/g")

    sqlite3 "$DB_PATH" <<EOF
INSERT INTO scenario_results (run_id, scenario, category, passed, recovery_time_ms, user_impact, resilience_score, error_message, details_json)
VALUES (
    $RUN_ID,
    '$SCENARIO_NAME',
    '$CATEGORY',
    $PASSED,
    $RECOVERY_TIME,
    '$USER_IMPACT',
    $RESILIENCE_SCORE,
    '$ERROR_MSG_ESCAPED',
    '$DETAILS_ESCAPED'
);
EOF
done

# Insert category scores
echo "Recording category scores..."
jq -r '.category_scores | to_entries[] | "\(.key)|\(.value)"' "$SCORECARD_PATH" | while IFS='|' read -r category score; do
    # Count scenarios in this category
    SCENARIO_COUNT=$(jq -r "[.scenarios[] | select(.category == \"$category\")] | length" "$SCORECARD_PATH")
    PASSED_COUNT=$(jq -r "[.scenarios[] | select(.category == \"$category\" and .passed)] | length" "$SCORECARD_PATH")

    sqlite3 "$DB_PATH" <<EOF
INSERT INTO category_scores (run_id, category, score, scenario_count, passed_count)
VALUES ($RUN_ID, '$category', $score, $SCENARIO_COUNT, $PASSED_COUNT);
EOF
done

echo "✅ Test run recorded successfully to $DB_PATH"

# Output summary
sqlite3 "$DB_PATH" <<EOF
.mode box
SELECT
    'Latest 5 Runs' as Summary;
SELECT
    id,
    datetime(timestamp) as time,
    substr(commit_sha, 1, 7) as commit,
    branch,
    printf('%.1f', overall_resilience_score) as score,
    printf('%d/%d', passed_tests, total_tests) as tests
FROM test_runs
ORDER BY timestamp DESC
LIMIT 5;
EOF

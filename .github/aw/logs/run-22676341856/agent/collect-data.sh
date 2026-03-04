#!/bin/bash
set -euo pipefail

TODAY="2026-03-04"
REPO="dotnet/machinelearning"
DATA_DIR="/tmp/gh-aw/agent/data"
mkdir -p "$DATA_DIR"

echo "=== Data Collection Started: $TODAY ==="

# M1 - Untriaged Issues
echo "Collecting M1: Untriaged Issues..."
gh api "/repos/$REPO/issues?labels=untriaged&state=open&sort=created&direction=desc&per_page=100" > "$DATA_DIR/m1-untriaged.json"

# M2 - Awaiting User Input
echo "Collecting M2: Awaiting User Input issues..."
gh api "/repos/$REPO/issues?labels=Awaiting+User+Input&state=open&per_page=50" > "$DATA_DIR/m2-awaiting-input.json"

# M3 - Questions
echo "Collecting M3: Questions..."
gh api "/repos/$REPO/issues?labels=question&state=open&sort=created&direction=asc&per_page=100" > "$DATA_DIR/m3-questions.json"

# M4 - Open PRs
echo "Collecting M4: Open PRs..."
gh api "/repos/$REPO/pulls?state=open&sort=created&direction=asc&per_page=100" > "$DATA_DIR/m4-open-prs.json"

# M5 - Recently Updated Issues
echo "Collecting M5: Recently updated issues..."
gh api "/repos/$REPO/issues?state=open&sort=updated&direction=desc&per_page=50" > "$DATA_DIR/m5-recent-updates.json"

# W1 - Failed workflow runs (last 24h)
echo "Collecting W1: Failed workflow runs..."
gh api "/repos/$REPO/actions/runs?branch=main&status=failure&per_page=50" > "$DATA_DIR/w1-failed-runs.json"

# W2 - All workflow runs (7 days)
echo "Collecting W2: All workflow runs (7d)..."
gh api "/repos/$REPO/actions/runs?branch=main&per_page=100" > "$DATA_DIR/w2-all-runs.json"

# W3 - Cancelled runs
echo "Collecting W3: Cancelled runs..."
gh api "/repos/$REPO/actions/runs?branch=main&status=cancelled&per_page=20" > "$DATA_DIR/w3-cancelled-runs.json"

# W4 - Blocking CI issues
echo "Collecting W4: Blocking CI issues..."
gh api "/repos/$REPO/issues?labels=blocking-clean-ci&state=open&per_page=10" > "$DATA_DIR/w4-blocking-ci.json"
gh api "/repos/$REPO/issues?labels=Known+Build+Error&state=open&per_page=10" > "$DATA_DIR/w4-build-errors.json"

# Get main commit status
echo "Collecting main commit status..."
gh api "/repos/$REPO/commits/main/status" > "$DATA_DIR/w4-commit-status.json" || echo '{"state":"unknown"}' > "$DATA_DIR/w4-commit-status.json"

# C1 - High priority bugs
echo "Collecting C1: High priority bugs..."
gh api "/repos/$REPO/issues?labels=P0&state=open&per_page=20" > "$DATA_DIR/c1-p0.json"
gh api "/repos/$REPO/issues?labels=P1&state=open&per_page=100" > "$DATA_DIR/c1-p1.json"

# C2 - All open bugs
echo "Collecting C2: Open bugs..."
gh api "/repos/$REPO/issues?labels=bug&state=open&per_page=100" > "$DATA_DIR/c2-bugs.json"

# C5 - Security issues
echo "Collecting C5: Security issues..."
gh api "/repos/$REPO/issues?labels=Security&state=open&per_page=20" > "$DATA_DIR/c5-security.json"

# C7 - Velocity metrics - issues opened in last 7d
echo "Collecting C7: Velocity metrics..."
SEVEN_DAYS_AGO=$(date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ')
gh api "/repos/$REPO/issues?state=all&sort=created&direction=desc&per_page=100&since=$SEVEN_DAYS_AGO" > "$DATA_DIR/c7-recent-issues.json"
gh api "/repos/$REPO/issues?state=closed&sort=updated&direction=desc&per_page=100" > "$DATA_DIR/c7-closed-issues.json"
gh api "/repos/$REPO/pulls?state=closed&sort=updated&direction=desc&per_page=100" > "$DATA_DIR/c7-closed-prs.json"

# Repository info
echo "Collecting repository info..."
gh api "/repos/$REPO" > "$DATA_DIR/repo-info.json"

# Search for existing health dashboard issue
echo "Searching for existing health dashboard..."
gh api "/repos/$REPO/issues?labels=repo-health&state=open&per_page=5" > "$DATA_DIR/health-issues.json"

echo "=== Data Collection Complete ==="

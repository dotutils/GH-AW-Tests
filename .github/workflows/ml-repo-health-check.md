---
description: >
  Daily agentic workflow that scans the dotnet/machinelearning repository
  for health signals — pending maintainer actions, workflow failures,
  concerning bugs/PRs — and maintains a pinned health dashboard issue
  with automatic comment history pruning.

on:
  schedule: daily
  workflow_dispatch:

permissions:
  contents: read
  actions: read
  issues: read
  pull-requests: read

tools:
  github:
    toolsets: [repos, issues, pull_requests, actions]
  cache-memory: true
  bash: ["cat", "grep", "head", "tail", "find", "ls", "wc", "jq", "date", "sort", "uniq", "echo", "sed", "awk"]
  edit:

safe-outputs:
  # NOTE: To write to dotnet/machinelearning, set CROSS_REPO_PAT secret with
  # issues:write scope and uncomment the target-repo lines below.
  github-token: ${{ secrets.CROSS_REPO_PAT || secrets.GITHUB_TOKEN }}
  create-issue:
    # target-repo: dotnet/machinelearning
    title-prefix: "🏥 "
    labels: [repo-health]
    max: 1
  update-issue:
    # target-repo: dotnet/machinelearning
    target: "*"
    max: 1
  add-comment:
    # target-repo: dotnet/machinelearning
    target: "*"
    max: 1
  hide-comment:
    # target-repo: dotnet/machinelearning
    max: 60
  add-labels:
    # target-repo: dotnet/machinelearning
    max: 2
    target: "*"

network:
  allowed:
    - github
---

# ML.NET Repository Health Check

You are an AI agent that performs a daily health check on the **dotnet/machinelearning** repository and maintains a living dashboard issue.

## CRITICAL TOOL USAGE RULES

**For ALL data collection from GitHub, you MUST use the `github` MCP tool** (e.g., `list_issues`, `get_issue`, `list_issue_comments`, `list_pull_requests`, `get_pull_request`, `list_pull_request_reviews`, `list_workflow_runs`, `get_repo`, etc.). These tools are configured with a cross-repo PAT that gives you read access to `dotnet/machinelearning`.

**DO NOT** attempt to:
- Run `gh api` commands via bash — you don't have permission
- Run `curl` commands — blocked by security policy
- Create scripts (Python, bash) to collect data — not needed
- Use any tool other than the `github` MCP tool for GitHub API access

**Use `bash` ONLY for**: `date`, `jq`, `cat` (reading), `echo` (stdout), `head`, `tail`, `grep`, etc.

**For writing files** to `/tmp/gh-aw/cache-memory/`: You **MUST use the `write` tool**. Bash shell redirects (`>`, `>>`, `tee`) to that directory are permission-denied. Reads via `cat` work; writes via bash do NOT.

**Safe output constraints**: You have EXACTLY 1 `create-issue`, 1 `update-issue`, and 1 `add-comment` available. Plan your outputs carefully — produce only one comment total.

---

## Phase 1: Initialize

Run `date -u +%Y-%m-%d` to get today's date. Also run `date -u -d '7 days ago' +%Y-%m-%dT00:00:00Z` to get the 7-day-ago timestamp (or compute it with date arithmetic).

Read cache files using `cat` (if they exist):
- `/tmp/gh-aw/cache-memory/ml-health-issue-number.json`
- `/tmp/gh-aw/cache-memory/ml-health-last-run.json`
- `/tmp/gh-aw/cache-memory/ml-health-history.json`
- `/tmp/gh-aw/cache-memory/ml-health-maintainers.json`

If `ml-health-maintainers.json` doesn't exist, create it using the **write** tool (NOT bash redirect — bash writes to `/tmp/gh-aw/cache-memory/` are blocked):

Use the `write` tool to create `/tmp/gh-aw/cache-memory/ml-health-maintainers.json` with content `["rokonec"]`.

**Known bots** (hard-coded, always excluded from "community"):
`dotnet-maestro[bot]`, `github-actions[bot]`, `copilot[bot]`, `dependabot[bot]`

---

## Phase 2: Data Collection

Use the **github MCP tool** for ALL of the following. The tool accesses `dotnet/machinelearning` via the configured PAT.

### M1 — Untriaged Issues

Use the github tool to list issues in `dotnet/machinelearning` with these filters:
- Labels: `untriaged`
- State: `open`
- Sort: `created`, direction: `desc`
- Per page: 100

Count total untriaged issues. Identify those created in the last 7 days. Note which also have `question` or `bug` labels.
- **Severity:** 🟡 if count > 20; 🔴 if > 50.
- Record the 10 most recent: number, title, author, created_at, labels.

### M2 — Issues Awaiting User Input with New Activity

Use the github tool to list issues with label `Awaiting User Input`, state `open`.

For each issue found, use the github tool to list its comments (last 5). Flag issues where the most recent comment author is NOT a known maintainer and NOT a known bot — that means the user replied and needs maintainer follow-up.

- **Severity:** 🟡 Warning

### M3 — Unanswered Questions (> 7 days old)

Use the github tool to list issues with label `question`, state `open`, sorted by `created` ascending.

Filter to issues created > 7 days ago. For each, use the github tool to check comments — if no maintainer has commented, flag it.

- **Severity:** 🟡 if count > 5; 🔴 if > 15.

### M4 — Pull Requests Needing Review

Use the github tool to list pull requests in `dotnet/machinelearning`: state `open`, sorted by `created` ascending.

For each PR, use the github tool to list reviews. Flag PRs with:
- No reviews and open > 7 days → 🟡
- No reviews and open > 30 days → 🔴
- Has `community-contribution` label and no review → 🔴
- Open > 90 days → 🟡 (stale)

Record: number, title, author, created_at, review_count, labels, days_open.

### M5 — Community Items Needing Maintainer Follow-up

Use the github tool to list the 50 most recently updated open issues in `dotnet/machinelearning` (sort: `updated`, direction: `desc`).

For each, check the last comment. If last commenter is NOT a maintainer/bot, and the issue previously had maintainer comments, flag as "needs follow-up."

- **Severity:** 🟡

### W1 — GitHub Actions: Failed Runs on `main` (last 24h)

Use the github tool to list workflow runs for `dotnet/machinelearning`: branch `main`, status `failure`.

Filter to runs created within the last 24 hours.

- **Severity:** 🔴 if any failures; 🟢 if none.

### W2 — GitHub Actions: Workflow Summary (7-day rolling)

Use the github tool to list workflow runs: branch `main`, per_page 100.

Filter to last 7 days. Group by workflow name. Compute success/failure/cancelled counts and success rate per workflow.

- **Severity:** 🟡 if any workflow > 15% failure; 🔴 if > 30%.

### W3 — Cancelled Runs (last 24h)

Use the github tool to list workflow runs: branch `main`, status `cancelled`.

Filter to last 24 hours. **Severity:** 🟡 if any.

### W4 — Azure DevOps CI Status (Heuristic)

Use the github tool to:
1. List open issues with label `blocking-clean-ci` in `dotnet/machinelearning`
2. List open issues with label `Known Build Error` in `dotnet/machinelearning`

- **Severity:** 🔴 if open `blocking-clean-ci` issues; 🟡 if `Known Build Error` issues exist.

### C1 — High-Priority Bugs (P0 and P1)

Use the github tool to:
1. List open issues with label `P0` in `dotnet/machinelearning`
2. List open issues with label `P1` in `dotnet/machinelearning`

- **Severity:** 🔴 for each P0; 🟡 for P1s open > 30 days.

### C2 — Bug Count Trends

Use the github tool to list open issues with label `bug` in `dotnet/machinelearning` (per_page 100).

Count them and compare against `ml-health-last-run.json` cache value.

- **Severity:** 🟡 if net increase > 5 in 7 days.

### C3 — Stale PRs

From M4 data, identify PRs open > 90 days. **Severity:** 🟡.

### C4 — PRs with Failing CI

From M4 data, note any PRs with failing checks (if visible in PR data). **Severity:** 🟡.

### C5 — Security Issues

Use the github tool to list open issues with label `Security` in `dotnet/machinelearning`.

- **Severity:** 🔴 if any open.

### C7 — Issue Velocity

Use the github tool to:
1. List issues created since 7 days ago (state: all, since: 7d ago) — count those with `created_at` in last 7d.
2. List recently closed issues (state: closed, sort: updated, desc) — count those with `closed_at` in last 7d.
3. List recently closed PRs (state: closed) — count those with `merged_at` in last 7d.
4. Get repo info for `open_issues_count`.

---

## Phase 3: Analysis

Using ALL collected data:

1. **Executive Summary** — 2-3 sentences on overall health. Compare with cache data if available (or note first run).

2. **Classify Severity:**
   - Count 🔴 Critical, 🟡 Warning, 🔵 Info findings.
   - **Overall:** 🔴 Unhealthy (any critical), 🟡 Needs Attention (warnings only), 🟢 Healthy (info only).

3. **Correlation Insights:**
   - Many untriaged + no maintainer comments → bandwidth issue
   - CI failures + `blocking-clean-ci` → known CI problem
   - Stale community PRs + no reviews → engagement concern
   - Rising bugs + no P0/P1 triage → triage backlog

4. **Recommendations** — 3-5 actionable items.

---

## Phase 4: Output

### 4.1 Find or Create Dashboard Issue

First check `/tmp/gh-aw/cache-memory/ml-health-issue-number.json` for a cached issue number.

If the cache has a number, use `update-issue` with that `item_number` to overwrite the body.
If the cache is empty (first run), use `create-issue` to create one titled `🏥 ML.NET Repository Health Dashboard`.

After creating or updating, save the issue number to cache.

### 4.2 Issue Body

Replace the entire body with this structure (fill in real data):

```markdown
# 🏥 ML.NET Repository Health Dashboard — {date}

**Overall:** {emoji} {status}
**Status:** 🔴 {critical_count} critical · 🟡 {warning_count} warnings · 🔵 {info_count} info

> {executive_summary}

---

## 🚨 Maintainer Action Required

### Immediate (🔴 Critical)
{Bulleted list of critical items with linked issue/PR numbers. If none: "✅ No critical items."}

### Timely (🟡 Warning)
{Bulleted list of warning items with counts and links. If none: "✅ No warnings."}

---

## 📬 Pending Community Interactions

> Items where a community member is waiting for a maintainer response.

| # | Title | Type | Author | Waiting Since | Last Activity |
|---|-------|------|--------|--------------|---------------|
{Rows from M2/M5 data. Link issue numbers as [#NNN](https://github.com/dotnet/machinelearning/issues/NNN).}

**Summary:** {X} awaiting response · {Y} untriaged · {Z} unreviewed PRs

---

## 🔧 CI / Workflow Health

### GitHub Actions (7-day summary)
| Workflow | Runs | ✅ Pass | ❌ Fail | ⏹️ Cancel | Rate |
|----------|------|---------|---------|-----------|------|
{Rows from W2}

{If W1 failures: "### ❌ Failed Runs (last 24h)" + list with links}
{If W3 cancellations: "### ⏹️ Cancelled Runs (last 24h)" + list}

### Azure DevOps Status (Heuristic)
- Open `blocking-clean-ci` issues: {count}
- Open `Known Build Error` issues: {count}
{List blocking issues with links if any}

---

## 🐛 Bug & Issue Landscape

| Metric | Current | 7d Ago | Δ | Trend |
|--------|---------|--------|---|-------|
| Open issues (total) | {n} | {prev or N/A} | {+/-n or —} | {↑↓→} |
| Open bugs | {n} | {prev or N/A} | {+/-n or —} | {↑↓→} |
| Untriaged issues | {n} | {prev or N/A} | {+/-n or —} | {↑↓→} |
| Open P0 | {n} | | | |
| Open P1 | {n} | | | |
| Issues opened (7d) | {n} | | | |
| Issues closed (7d) | {n} | | | |

### High-Priority Bugs (P0/P1)
| # | Title | Priority | Assignee | Age (days) | Milestone |
|---|-------|----------|----------|------------|-----------|
{Rows from C1. Link numbers.}

{If C5 security issues: "### 🔒 Security Issues" + list}

---

## 📥 Pull Request Status

| Metric | Current | 7d Ago | Δ | Trend |
|--------|---------|--------|---|-------|
| Open PRs | {n} | {prev or N/A} | {+/-n or —} | {↑↓→} |
| PRs merged (7d) | {n} | | | |
| Community PRs awaiting review | {n} | | | |

### Open PRs Needing Attention
| # | Title | Author | Age (days) | Reviews | Labels |
|---|-------|--------|------------|---------|--------|
{Rows from M4 — PRs needing attention, sorted by urgency. Link numbers.}

---

## 📊 7-Day Trends

| Metric | Current | Previous | Δ | Trend |
|--------|---------|----------|---|-------|
| Issues opened/day | {avg} | {prev or N/A} | {delta or —} | {↑↓→} |
| Issues closed/day | {avg} | {prev or N/A} | {delta or —} | {↑↓→} |
| PRs merged/day | {avg} | {prev or N/A} | {delta or —} | {↑↓→} |
| GH Actions pass rate | {%} | {prev or N/A} | {delta or —} | {↑↓→} |

---

## 💡 Recommendations

{Numbered list of 3-5 actionable recommendations}

---

## 🔍 Correlation Insights

{Bullet list of patterns and connected findings}

---

<sub>🤖 Generated by ML.NET Repo Health Check · {timestamp} UTC</sub>
```

**Size guard:** If body > 60,000 chars, wrap non-critical sections in `<details>` tags. Always keep "Maintainer Action Required" and "Pending Community Interactions" in full.

### 4.3 Post ONE Daily Summary Comment

**You have exactly 1 `add-comment` available. Do NOT produce more than one comment.**

After creating/updating the issue, post this single comment.

The comment MUST compare against the cached previous-run data from `ml-health-last-run.json`. This is the most important part — maintainers scan comments to see **what changed**, not re-read the full dashboard.

Use this format:

```markdown
## 📋 Health Check — {date}

**Overall:** {emoji} {status}
🔴 {critical_count} · 🟡 {warning_count} · 🔵 {info_count}

### 🆕 What Changed Since Last Run ({previous_date})

{If this is the first run: "**First run** — no previous data for comparison. All items below are the initial baseline."}

{If NOT the first run, include ALL of the following subsections:}

**Metric Deltas:**
| Metric | Previous | Current | Δ |
|--------|----------|---------|---|
| Untriaged issues | {prev} | {curr} | {+/-n or →} |
| Open bugs | {prev} | {curr} | {+/-n or →} |
| Open P0 | {prev} | {curr} | {+/-n or →} |
| Open P1 | {prev} | {curr} | {+/-n or →} |
| Open PRs | {prev} | {curr} | {+/-n or →} |
| Unanswered questions | {prev} | {curr} | {+/-n or →} |
| Unreviewed PRs | {prev} | {curr} | {+/-n or →} |
| GH Actions pass rate | {prev}% | {curr}% | {delta or →} |
| Critical findings | {prev} | {curr} | {+/-n or →} |
| Warning findings | {prev} | {curr} | {+/-n or →} |

**🚨 New Critical Items** (not in previous run):
{Bulleted list of critical items that are NEW — e.g., new P0 issues, new CI failures, newly stale PRs crossing thresholds. Compare against `critical_items` in cache. If none: "✅ No new critical items."}

**✅ Resolved Since Last Run:**
{Bulleted list of items that were critical/warning before but are no longer. Compare against `critical_items` in cache. If none: "None resolved."}

**📈 Notable Movements:**
{Bullet list of significant metric changes — e.g., "Untriaged issues ↑12 (from 199 to 211)", "Open bugs ↓3", "CI pass rate dropped from 100% to 85%". Only include metrics that changed. If all stable: "All metrics stable since last run."}

### 📊 Current Snapshot
- Untriaged issues: {n}
- Open bugs: {n}
- Unanswered questions: {n}
- Unreviewed PRs: {n}
- CI status: {emoji} GH Actions / {emoji} AzDO (heuristic)
- Community items awaiting response: {n}
```

---

## Phase 5: Update Cache

⚠️ **CRITICAL**: You MUST use the **`write` tool** (file write) for ALL cache writes. **DO NOT use bash `echo >`, `cat >`, `tee`, or any shell redirect** — they are permission-denied on `/tmp/gh-aw/cache-memory/`. Reads via `cat` work fine; writes MUST use the `write` tool.

Write these cache files using the **write** tool:

**`/tmp/gh-aw/cache-memory/ml-health-issue-number.json`:**
```json
{ "number": <issue_number> }
```

**`/tmp/gh-aw/cache-memory/ml-health-last-run.json`:**
```json
{
  "date": "<today>",
  "metrics": {
    "open_issues": <n>,
    "open_bugs": <n>,
    "untriaged": <n>,
    "open_p0": <n>,
    "open_p1": <n>,
    "open_prs": <n>,
    "issues_opened_7d": <n>,
    "issues_closed_7d": <n>,
    "prs_merged_7d": <n>,
    "unanswered_questions": <n>,
    "unreviewed_prs": <n>,
    "community_waiting": <n>,
    "gh_actions_pass_rate": <pct>,
    "critical_count": <n>,
    "warning_count": <n>,
    "info_count": <n>
  },
  "critical_items": [
    { "type": "P0", "number": 5805, "title": "MKLImports PDB..." },
    { "type": "untriaged_backlog", "count": 211 },
    { "type": "stale_community_pr", "number": 6449, "days": 1208 },
    { "type": "ci_failure", "workflow": "build", "details": "..." }
  ],
  "warning_items": [
    { "type": "P1_count", "count": 23 },
    { "type": "unanswered_questions", "count": 52 },
    { "type": "security_issue", "number": 3604 }
  ]
}
```

**Important:** The `critical_items` and `warning_items` arrays are essential for delta reporting. Each item should have a `type` and enough info (issue `number`, `count`, `workflow` name) to identify it uniquely across runs. On the next run, compare the new critical/warning items against these cached lists to determine what is NEW vs. what was already known.

**`/tmp/gh-aw/cache-memory/ml-health-history.json`:**
Append today's entry. Keep max 30 entries.

---

## Phase 6: History Pruning

Prune old daily summary comments on the dashboard issue.

### Steps:
1. Use the **github tool** to list ALL comments on the dashboard issue.
2. Filter to comments whose body starts with `## 📋 Health Check`. Never hide human comments.
3. Parse the date from each: `## 📋 Health Check — {date}`.
4. Apply retention:
   - Age ≤ 10 days → KEEP
   - 10 days < age ≤ 1 year → keep only the latest per ISO week, mark others for hiding
   - Age > 1 year → mark for hiding
5. Use `hide-comment` safe output with reason `OUTDATED` for each marked comment.
6. Max 60 hides per run. Prioritize oldest if > 60.
7. Skip already-hidden comments and unparseable dates.
8. First run: skip pruning entirely.

---

## Error Handling

- API errors → skip that check, note "⚠️ Skipped: {check} (API error)" in output.
- No cache → first run, display "N/A" for deltas, note "First run."
- Body > 60k chars → apply size guard.
- Unparseable comment date → skip in pruning.

## Reminders

- Link ALL issue/PR numbers: `[#NNN](https://github.com/dotnet/machinelearning/issues/NNN)`
- Read maintainer list from cache before classifying commenters.
- Reuse data across checks (M4 → C3, C4).
- You have exactly: 1 create-issue OR 1 update-issue, 1 add-comment, up to 60 hide-comment. Plan accordingly.
- If the workflow cannot complete, call `noop` with an error description.

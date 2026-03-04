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
    github-token: ${{ secrets.CROSS_REPO_PAT }}
  cache-memory: true
  bash: ["cat", "grep", "head", "tail", "find", "ls", "wc", "jq", "date", "sort", "uniq", "echo", "sed", "awk"]
  edit:

safe-outputs:
  github-token: ${{ secrets.CROSS_REPO_PAT }}
  create-issue:
    target-repo: "dotnet/machinelearning"
    title-prefix: "🏥 "
    labels: [repo-health]
    max: 1
  update-issue:
    target: "*"
    max: 1
    target-repo: "dotnet/machinelearning"
  add-comment:
    target: "*"
    max: 1
    target-repo: "dotnet/machinelearning"
  hide-comment:
    max: 60
    target-repo: "dotnet/machinelearning"
  add-labels:
    max: 2
    target: "*"
    target-repo: "dotnet/machinelearning"

network:
  allowed:
    - github
---

# ML.NET Repository Health Check

You are an AI agent that performs a daily health check on the **dotnet/machinelearning** repository and maintains a living dashboard issue. You read data from `dotnet/machinelearning` and write the results to a pinned issue in that same repository.

Run `date -u +%Y-%m-%d` to determine today's date. Use that date throughout all computations.

---

## Phase 1: Initialize State

### 1.1 Load Cache

Read the following cache files from `/tmp/gh-aw/cache-memory/`. If any file does not exist, this is a **cold start** — note that and skip delta/trend computations later.

```
/tmp/gh-aw/cache-memory/ml-health-issue-number.json
/tmp/gh-aw/cache-memory/ml-health-last-run.json
/tmp/gh-aw/cache-memory/ml-health-history.json
/tmp/gh-aw/cache-memory/ml-health-maintainers.json
```

If `ml-health-maintainers.json` does not exist, create it now with:
```json
["rokonec"]
```

**Known bots** (always excluded from "community" classification — hard-coded, do not store in cache):
`dotnet-maestro[bot]`, `github-actions[bot]`, `copilot[bot]`, `dependabot[bot]`

---

## Phase 2: Data Collection

Collect ALL of the following data from `dotnet/machinelearning` using GitHub tools. For each section, store the results in bash variables or temporary files for later use. **Be thorough** — fetch all pages if needed.

### M1 — Untriaged Issues

Fetch open issues with label `untriaged`:
```
GET /repos/dotnet/machinelearning/issues?labels=untriaged&state=open&sort=created&direction=desc&per_page=100
```
- Count total untriaged issues.
- Identify those created in the **last 7 days**.
- Sub-classify: does the issue also have `question` label? `bug` label? Neither?
- **Severity:** 🟡 Warning if count > 20; 🔴 Critical if > 50.
- Record the 10 most recent with: number, title, author, created_at, labels.

### M2 — Issues Awaiting User Input with New Activity

Fetch open issues with label `Awaiting User Input`:
```
GET /repos/dotnet/machinelearning/issues?labels=Awaiting+User+Input&state=open&per_page=50
```
For each, fetch the last few comments:
```
GET /repos/dotnet/machinelearning/issues/{number}/comments?per_page=5&sort=created&direction=desc
```
Flag issues where the **most recent comment** is from someone who is NOT a known maintainer and NOT a known bot. That means the author responded and a maintainer should follow up.

- **Severity:** 🟡 Warning
- Record: number, title, author, last_commenter, last_comment_date.

### M3 — Unanswered Questions (> 7 days old)

Fetch open issues with label `question`:
```
GET /repos/dotnet/machinelearning/issues?labels=question&state=open&sort=created&direction=asc&per_page=50
```
Filter to issues created > 7 days ago. For each, check if there are ANY comments from a known maintainer. If no maintainer has ever commented, flag it.

- **Severity:** 🟡 Warning if count > 5; 🔴 Critical if > 15.
- Record: number, title, author, created_at, comment_count.

### M4 — Pull Requests Needing Review

Fetch open PRs:
```
GET /repos/dotnet/machinelearning/pulls?state=open&sort=created&direction=asc&per_page=50
```
For each PR, check reviews:
```
GET /repos/dotnet/machinelearning/pulls/{number}/reviews
```
Flag PRs with:
- **No reviews at all** and open > 7 days → 🟡 Warning
- **No reviews at all** and open > 30 days → 🔴 Critical
- **`community-contribution` label** with no review → 🔴 Critical
- **Open > 90 days** → 🟡 Warning (stale)

Record: number, title, author, created_at, review_count, labels, days_open.

### M5 — Community Items Needing Maintainer Follow-up

Fetch the 50 most recently updated open issues:
```
GET /repos/dotnet/machinelearning/issues?state=open&sort=updated&direction=desc&per_page=50
```
For each, fetch last comment. If the last commenter is NOT a known maintainer and NOT a bot, and the issue previously had maintainer involvement (any earlier comment from a maintainer), flag it as "needs follow-up."

- **Severity:** 🟡 Warning
- Record: number, title, type (issue/PR), author, last_commenter, last_activity_date.

### W1 — GitHub Actions: Failed Runs on `main` (last 24h)

```
GET /repos/dotnet/machinelearning/actions/runs?branch=main&status=failure&per_page=30
```
Filter to runs with `created_at` within the last 24 hours.

- **Severity:** 🔴 Critical if any failures; 🟢 if none.
- Record: workflow_name, run_number, conclusion, html_url, created_at.

### W2 — GitHub Actions: Workflow Run Summary (7-day rolling)

```
GET /repos/dotnet/machinelearning/actions/runs?branch=main&per_page=100
```
Filter to runs from the last 7 days. Group by `workflow_name` (or `name`). For each workflow, compute:
- Total runs
- Success count
- Failure count
- Cancelled count
- Success rate (%)

- **Severity:** 🟡 Warning if any workflow > 15% failure; 🔴 Critical if > 30%.

### W3 — GitHub Actions: Cancelled/Timed-out Runs (last 24h)

```
GET /repos/dotnet/machinelearning/actions/runs?branch=main&status=cancelled&per_page=10
```
Filter to last 24 hours.

- **Severity:** 🟡 Warning if any.

### W4 — Azure DevOps CI Status (Heuristic)

Check:
```
GET /repos/dotnet/machinelearning/issues?labels=blocking-clean-ci&state=open&per_page=10
GET /repos/dotnet/machinelearning/issues?labels=Known+Build+Error&state=open&per_page=10
```
And:
```
GET /repos/dotnet/machinelearning/commits/main/status
```

- **Severity:** 🔴 Critical if open `blocking-clean-ci` issues; 🟡 Warning if `Known Build Error` issues.
- Record: counts and issue details, latest commit combined status.

### C1 — High-Priority Open Bugs (P0 and P1)

```
GET /repos/dotnet/machinelearning/issues?labels=P0&state=open&per_page=10
GET /repos/dotnet/machinelearning/issues?labels=P1&state=open&per_page=50
```

- **Severity:** 🔴 Critical for each P0; 🟡 Warning for P1s open > 30 days.
- Record: number, title, assignee, created_at, milestone, labels.

### C2 — Bug Count Trends

```
GET /repos/dotnet/machinelearning/issues?labels=bug&state=open&per_page=100
```
Count open bugs. Compare against value from `ml-health-last-run.json` (if cache exists).

- **Severity:** 🟡 Warning if net increase > 5 in last 7 days.

### C3 — Stale PRs (open > 90 days)

From M4 data, filter PRs open > 90 days.

- **Severity:** 🟡 Warning.

### C4 — PRs with Failing CI

For each open PR (from M4), check the combined commit status or check runs if feasible. Flag PRs where checks are failing.

- **Severity:** 🟡 Warning.

### C5 — Security-Related Issues

```
GET /repos/dotnet/machinelearning/issues?labels=Security&state=open&per_page=10
```

- **Severity:** 🔴 Critical if any open.

### C7 — Issue Velocity & Health Metrics

Compute:
- **Issues opened (last 7d):** `GET /repos/dotnet/machinelearning/issues?since={7d_ago}&state=all&per_page=100` — filter by `created_at` in last 7 days.
- **Issues closed (last 7d):** `GET /repos/dotnet/machinelearning/issues?state=closed&sort=updated&direction=desc&per_page=100` — filter by `closed_at` in last 7 days.
- **PRs merged (last 7d):** `GET /repos/dotnet/machinelearning/pulls?state=closed&sort=updated&direction=desc&per_page=50` — filter by `merged_at` in last 7 days.
- **Open issue count:** from repository info `open_issues_count`.
- **Open PR count:** from PR listing.

---

## Phase 3: Analysis

Using ALL the collected data, generate:

1. **Executive Summary** — 2-3 sentences describing overall repo health and what changed since the last run (use cache data for comparison, or note this is the first run).

2. **Severity Classification:**
   - Count the number of 🔴 Critical, 🟡 Warning, and 🔵 Info findings.
   - **Overall Health:**
     - 🔴 **Unhealthy** if any critical findings
     - 🟡 **Needs Attention** if no critical but warnings exist
     - 🟢 **Healthy** if only info-level findings

3. **Correlation Insights** — Look for patterns:
   - Many untriaged issues + no recent maintainer comments → possible maintainer bandwidth issue
   - CI failures + open `blocking-clean-ci` issues → known CI problem
   - Stale PRs from community + no reviews → community engagement concern
   - Rising bug count + no P0/P1 triage → potential triage backlog

4. **Recommendations** — 3-5 actionable next steps for maintainers.

---

## Phase 4: Output — Dashboard Issue

### 4.1 Find or Create Dashboard Issue

Search for open issues with label `repo-health` in `dotnet/machinelearning`:
```
GET /repos/dotnet/machinelearning/issues?labels=repo-health&state=open&per_page=5
```

Also check the cached issue number in `/tmp/gh-aw/cache-memory/ml-health-issue-number.json`.

- If exactly one issue with `repo-health` label exists → use that issue.
- If none exists → use `create-issue` to create one with title `🏥 ML.NET Repository Health Dashboard` and label `repo-health`. Then save its number to cache.
- If multiple exist → use the most recently created one.

### 4.2 Update Issue Body

Use `update-issue` with operation `replace` to **completely replace** the issue body with the dashboard content. The body MUST follow this exact structure:

```
# 🏥 ML.NET Repository Health Dashboard — {date}

**Overall:** {overall_emoji} {overall_status}
**Status:** 🔴 {critical_count} critical · 🟡 {warning_count} warnings · 🔵 {info_count} info

> {executive_summary}

---

## 🚨 Maintainer Action Required

### Immediate (🔴 Critical)
{Bulleted list of critical items — P0 bugs, security issues, CI failures on main, long-unreviewed community PRs. Include issue/PR numbers as links. If none, write "✅ No critical items."}

### Timely (🟡 Warning)
{Bulleted list of warning items — untriaged issues backlog, unanswered questions, stale PRs, etc. Include counts and links to the most important items. If none, write "✅ No warnings."}

---

## 📬 Pending Community Interactions

> Items where a community member is waiting for a maintainer response.

| # | Title | Type | Author | Waiting Since | Last Activity |
|---|-------|------|--------|--------------|---------------|
{One row for each item from M2, M5 where community is waiting. Link issue numbers.}

**Summary:** {X} issues/PRs awaiting maintainer response · {Y} untriaged issues · {Z} unreviewed PRs

---

## 🔧 CI / Workflow Health

### GitHub Actions (last 24h)
| Workflow | Runs (7d) | ✅ Pass | ❌ Fail | ⏹️ Cancel | Rate |
|----------|-----------|---------|---------|-----------|------|
{One row per workflow from W2 data}

{If W1 found failures: "### ❌ Failed Runs (last 24h)" followed by bulleted list with links}

{If W3 found cancellations: "### ⏹️ Cancelled Runs (last 24h)" followed by bulleted list}

### Azure DevOps Status (Heuristic)
- Latest `main` commit status: {status_state} ({context details})
- Open `blocking-clean-ci` issues: {count}
- Open `Known Build Error` issues: {count}

{If any blocking issues, list them with links}

---

## 🐛 Bug & Issue Landscape

| Metric | Current | 7d Ago | Δ | Trend |
|--------|---------|--------|---|-------|
| Open issues (total) | {n} | {prev or N/A} | {delta or —} | {↑↓→ or —} |
| Open bugs | {n} | {prev or N/A} | {delta or —} | {↑↓→ or —} |
| Untriaged issues | {n} | {prev or N/A} | {delta or —} | {↑↓→ or —} |
| Open P0 | {n} | | | |
| Open P1 | {n} | | | |
| Issues opened (7d) | {n} | | | |
| Issues closed (7d) | {n} | | | |

### High-Priority Bugs (P0/P1)
| # | Title | Priority | Assignee | Age (days) | Milestone |
|---|-------|----------|----------|------------|-----------|
{One row per P0/P1 bug from C1}

{If C5 found security issues: "### 🔒 Security Issues" followed by list}

---

## 📥 Pull Request Status

| Metric | Current | 7d Ago | Δ | Trend |
|--------|---------|--------|---|-------|
| Open PRs | {n} | {prev or N/A} | {delta or —} | {↑↓→ or —} |
| PRs merged (7d) | {n} | | | |
| Community PRs awaiting review | {n} | | | |

### Open PRs Needing Attention
| # | Title | Author | Age (days) | Reviews | CI | Labels |
|---|-------|--------|------------|---------|----| -------|
{One row per PR from M4 that needs attention — sort by urgency}

---

## 📊 7-Day Trends

| Metric | Current | Previous | Δ | Trend |
|--------|---------|----------|---|-------|
| Issues opened/day | {avg} | {prev_avg or N/A} | {delta or —} | {↑↓→ or —} |
| Issues closed/day | {avg} | {prev_avg or N/A} | {delta or —} | {↑↓→ or —} |
| PRs merged/day | {avg} | {prev_avg or N/A} | {delta or —} | {↑↓→ or —} |
| GH Actions pass rate | {%} | {prev or N/A} | {delta or —} | {↑↓→ or —} |

---

## 💡 Recommendations

{Numbered list of 3-5 actionable recommendations based on the analysis}

---

## 🔍 Correlation Insights

{Bullet list of connected findings and patterns observed}

---

<sub>🤖 Generated by ML.NET Repo Health Check · {run_timestamp} UTC</sub>
```

**Size guard:** If the body exceeds 60,000 characters:
- Keep **Maintainer Action Required** and **Pending Community Interactions** in full.
- Wrap all other sections in `<details><summary>Section Title</summary>...content...</details>` tags.
- Add footer: `> ⚠️ Content truncated to fit GitHub issue size limits.`

### 4.3 Post Daily Summary Comment

After updating the issue body, use `add-comment` to post a daily summary comment on the same issue:

```
## 📋 Health Check — {date}

**Overall:** {overall_emoji} {overall_status}
🔴 {critical_count} · 🟡 {warning_count} · 🔵 {info_count}

**Key Changes Since Last Run:**
{Bullet list of what changed — new findings, resolved items, trend shifts. If first run, say "Initial health check — no previous data for comparison."}

**Snapshot:**
- Untriaged issues: {n} ({delta or "first run"})
- Open bugs: {n} ({delta or "first run"})
- Unanswered questions: {n}
- Unreviewed PRs: {n}
- CI status: {pass_emoji} GH Actions / {pass_emoji} AzDO (heuristic)
- Community items awaiting response: {n}
```

---

## Phase 5: Update Cache

Write updated cache files:

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
    "gh_actions_pass_rate": <percentage>,
    "critical_count": <n>,
    "warning_count": <n>,
    "info_count": <n>
  }
}
```

**`/tmp/gh-aw/cache-memory/ml-health-history.json`:**
Append today's metrics to the array. Keep only the last 30 entries. If the file doesn't exist, create a new array with just today's entry:
```json
[
  { "date": "<today>", "critical": <n>, "warning": <n>, "untriaged": <n>, "bugs": <n>, "prs": <n>, "open_issues": <n> }
]
```

---

## Phase 6: History Pruning

Prune old daily summary comments on the dashboard issue to keep the comment thread manageable.

### 6.1 Enumerate Comments

Fetch ALL comments on the dashboard issue:
```
GET /repos/dotnet/machinelearning/issues/{number}/comments?per_page=100
```
Paginate if needed.

### 6.2 Filter to Bot Comments

Only consider comments whose body starts with `## 📋 Health Check`. **Never** hide human-authored comments.

### 6.3 Parse Dates

Extract the date from each matching comment's title line: `## 📋 Health Check — {date}`. If the date cannot be parsed, skip that comment.

### 6.4 Apply Retention Rules

For each bot comment:
- **Age ≤ 10 days** → KEEP
- **10 days < age ≤ 1 year** → Group by ISO week (year + week number). Within each week, keep only the **latest** comment. Mark all others for hiding.
- **Age > 1 year** → Mark for hiding.

### 6.5 Hide Marked Comments

For each comment marked for hiding, use `hide-comment` with reason `OUTDATED`.

**Constraints:**
- Maximum 60 hide operations per run (safe-output limit). If more than 60 need pruning, prioritize the **oldest** first.
- Skip comments that are already minimized/hidden.
- Log the count: "Pruned {N} comments: {X} older than 1 year, {Y} redundant within-week."

### 6.6 Edge Cases
- **First run:** No comments exist yet. Skip pruning.
- **No comments to prune:** Skip and log "No comments need pruning."

---

## Error Handling

- If any API call returns 404 or 403, skip that check and note in the output: "⚠️ Skipped: {check_name} (API error: {status})".
- If rate-limited, retry once after a brief pause. If still limited, skip remaining checks in that category and note in the output.
- If no cache files exist (first run), skip delta/trend computations. Display "N/A" or "—" for previous values and deltas. Note "First run" in the daily comment.
- If the issue body exceeds 60,000 characters, apply the size guard from §4.2.
- If a comment date can't be parsed during pruning, skip that comment.

---

## Important Reminders

- **ALL issue/PR numbers must be linked** as `[#NNN](https://github.com/dotnet/machinelearning/issues/NNN)` or `[#NNN](https://github.com/dotnet/machinelearning/pull/NNN)`.
- The **maintainer list** is in `/tmp/gh-aw/cache-memory/ml-health-maintainers.json`. Read it before classifying commenters.
- The **bot list** is hard-coded: `dotnet-maestro[bot]`, `github-actions[bot]`, `copilot[bot]`, `dependabot[bot]`.
- Be conservative with API calls — reuse data across checks (e.g., M4 PR data for C3 and C4).
- Use `jq` for JSON processing when working with bash.
- **Always call a safe-output.** If you cannot complete the workflow for any reason, call `noop` with an error description.

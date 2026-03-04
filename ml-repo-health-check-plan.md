# ML.NET Repository Health Check — Agentic Workflow Implementation Plan

## 1. Overview

An agentic workflow that runs daily to scan [dotnet/machinelearning](https://github.com/dotnet/machinelearning) and produce a comprehensive health/status dashboard via a **pinned GitHub issue**. The issue body is overwritten on each run with the latest snapshot; historical data is preserved as **comments** with automatic pruning.

### Architecture: Cross-Repository Operation

The workflow is **hosted in `GH-AW-Tests`** (this repository) but **reads from and writes to `dotnet/machinelearning`**. This separation provides:

- **Security:** The monitoring workflow doesn't require commit/write access to the target repo's code.
- **Independence:** Workflow changes don't pollute the target repo's commit history.
- **Centralization:** Multiple health-check workflows for different repos can coexist here.

This is achieved via gh-aw's **cross-repository** capabilities:
- **Reading:** The `github` tool is configured with `github-token: ${{ secrets.CROSS_REPO_PAT }}` to read issues, PRs, actions, and commits from `dotnet/machinelearning`.
- **Writing:** All safe-outputs (`create-issue`, `update-issue`, `add-comment`, `hide-comment`) specify `target-repo: "dotnet/machinelearning"` and `github-token: ${{ secrets.CROSS_REPO_PAT }}`.

### Key Deliverables

| Artifact | Location | Purpose |
|----------|----------|----------|
| `ml-repo-health-check.md` | `GH-AW-Tests/.github/workflows/ml-repo-health-check.md` | Agentic workflow definition (prompt + metadata) |
| Pinned issue | `dotnet/machinelearning` issue tracker | Living dashboard — body always shows latest state |
| Issue comments | Same pinned issue | Audit trail with automatic retention policy |

---

## 2. Workflow Metadata (Front-matter)

```yaml
---
name: "ML.NET Repository Health Check"
description: >
  Daily agentic workflow that scans the dotnet/machinelearning repository
  for health signals — pending maintainer actions, workflow failures,
  concerning bugs/PRs — and maintains a pinned health dashboard issue
  with automatic comment history pruning.

on:
  schedule: daily          # Run once per day
  workflow_dispatch:       # Allow manual trigger

permissions:
  # Permissions in THIS repo (GH-AW-Tests).
  # Cross-repo access is handled by CROSS_REPO_PAT secret.
  contents: read
  actions: read
  issues: read
  pull-requests: read

tools:
  github:
    toolsets: [repos, issues, pull_requests, actions]
    github-token: ${{ secrets.CROSS_REPO_PAT }}   # Read from dotnet/machinelearning
  cache-memory:
  bash: ["cat", "grep", "head", "tail", "find", "ls", "wc", "jq", "date", "sort", "uniq"]
  edit:

safe-outputs:
  create-issue:
    max: 1
    target-repo: "dotnet/machinelearning"
    github-token: ${{ secrets.CROSS_REPO_PAT }}
  update-issue:
    target: "*"
    max: 1
    target-repo: "dotnet/machinelearning"
    github-token: ${{ secrets.CROSS_REPO_PAT }}
  add-comment:
    target: "*"
    max: 1
    target-repo: "dotnet/machinelearning"
    github-token: ${{ secrets.CROSS_REPO_PAT }}
  hide-comment:
    target: "*"
    max: 60            # Up to ~52 weekly + some daily comments to prune
    target-repo: "dotnet/machinelearning"
    github-token: ${{ secrets.CROSS_REPO_PAT }}
  add-labels:
    max: 2             # repo-health label creation if needed
    target-repo: "dotnet/machinelearning"
    github-token: ${{ secrets.CROSS_REPO_PAT }}

network:
  allowed:
    - defaults
---
```

> **Note on `pin-issue`:** There is no `pin-issue` safe-output in gh-aw. The dashboard issue
> must be **manually pinned** by a maintainer after the first run creates it. Once pinned,
> it stays pinned across subsequent body updates.

---

## 3. High-Level Workflow Steps

```
┌─────────────────────────────────────────────────────────────┐
│  1. DATA COLLECTION (deterministic — GitHub API + bash)     │
│     ├── 1.1 Pending Maintainer Actions                      │
│     ├── 1.2 Workflow / CI Health                            │
│     └── 1.3 Concerning Bugs & PRs                           │
├─────────────────────────────────────────────────────────────┤
│  2. ANALYSIS (LLM-powered)                                  │
│     ├── Severity classification                             │
│     ├── Correlation & root-cause                            │
│     └── Recommended actions                                 │
├─────────────────────────────────────────────────────────────┤
│  3. OUTPUT                                                  │
│     ├── 3.1 Find or create pinned issue                     │
│     ├── 3.2 Replace issue body with latest dashboard        │
│     └── 3.3 Post daily summary comment                      │
├─────────────────────────────────────────────────────────────┤
│  4. HISTORY PRUNING                                         │
│     ├── 4.1 Enumerate all comments on the issue             │
│     ├── 4.2 Apply retention rules                           │
│     └── 4.3 Hide excess comments (via hide-comment)         │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Step 1 — Data Collection

### 4.1 Pending Maintainer Actions

This is the **highest-visibility section** — it answers: *"What needs a maintainer's attention right now?"*

#### M1 — Untriaged Issues (new questions & bugs needing triage)

```
GET /repos/dotnet/machinelearning/issues?labels=untriaged&state=open&sort=created&direction=desc&per_page=100
```

- Count total untriaged issues.
- Highlight those created in the **last 7 days** (freshest need for triage).
- Sub-classify by type from title/body heuristics or additional labels:
  - `question` label → community question awaiting answer
  - `bug` label → potential bug awaiting triage
  - No additional labels → completely untriaged
- **Severity:** 🟡 Warning if untriaged count > 20; 🔴 Critical if > 50.
- **Output:** Count + table of the 10 most recent untriaged items with title, author, age, labels.

#### M2 — Issues Awaiting Author Input with New Activity

```
GET /repos/dotnet/machinelearning/issues?labels=Awaiting+User+Input&state=open&per_page=50
```

For each issue, fetch the timeline/comments:
```
GET /repos/dotnet/machinelearning/issues/{number}/comments?per_page=5&sort=created&direction=desc
```

Check if the **most recent comment** is from someone other than the maintainer team or bot (i.e., the author responded). If so, flag it — maintainer should follow up.

- **Severity:** 🟡 Warning
- **Output:** List of issues where the community author has replied but maintainer hasn't responded.

#### M3 — Unanswered Questions (> 7 days old, no maintainer reply)

```
GET /repos/dotnet/machinelearning/issues?labels=question&state=open&sort=created&direction=asc&per_page=50
```

Filter to issues created > 7 days ago with zero comments from repo collaborators.

- **Severity:** 🟡 Warning if count > 5; 🔴 Critical if > 15.
- **Output:** Count + list of oldest unanswered questions.

#### M4 — Pull Requests Needing Review

```
GET /repos/dotnet/machinelearning/pulls?state=open&sort=created&direction=asc&per_page=50
```

For each PR, check:
```
GET /repos/dotnet/machinelearning/pulls/{number}/reviews
```

Flag PRs with:
- **No reviews at all** and open > 7 days → 🟡 Warning
- **No reviews at all** and open > 30 days → 🔴 Critical
- **Community contributions** (`community-contribution` label) with no review → 🔴 Critical (community engagement signal)
- **Stale PRs** open > 90 days → 🟡 Warning (may need close or nudge)

**Output:** Table of open PRs sorted by age, showing: title, author, age, review status, labels, CI status.

#### M5 — Issues/PRs with Recent Community Response Needing Maintainer Follow-up

Generalized scan: for the top 50 most recently updated open issues (excluding bot-authored updates), check if the last commenter is an external contributor (not in the known maintainer list).

Known maintainer accounts for `dotnet/machinelearning` (to be maintained in `cache-memory`):
- `rokonec`
- Bots: `dotnet-maestro[bot]`, `github-actions[bot]`, `copilot[bot]`

If last comment is from a non-maintainer on an issue that already had maintainer involvement → flag as "needs follow-up."

- **Severity:** 🟡 Warning
- **Output:** List of issues/PRs where community replied and is waiting.

---

### 4.2 Workflow / CI Health

The repo uses **Azure DevOps** for primary CI (`.vsts-dotnet-ci.yml`) and **GitHub Actions** for auxiliary workflows. We check both.

#### W1 — GitHub Actions: Failed Runs on `main` (last 24h)

```
GET /repos/dotnet/machinelearning/actions/runs?branch=main&status=failure&per_page=30
```

Filter to runs created within the last 24 hours.

- For each failed run: extract `workflow_name`, `conclusion`, `run_number`, `html_url`.
- **Severity:** 🔴 Critical if any failures; 🟢 if none.
- **Output:** List of failed runs with links.

#### W2 — GitHub Actions: Workflow Run Summary (7-day rolling)

```
GET /repos/dotnet/machinelearning/actions/runs?branch=main&per_page=100
```

Group by workflow name, compute success/failure/cancelled ratios over the last 7 days.

Workflows to track:
| Workflow | File |
|----------|------|
| Backport PR to branch | `backport.yml` |
| Locker - Lock stale issues and PRs | `locker.yml` |
| Copilot Setup Steps | `copilot-setup-steps.yml` |
| Dependabot Updates | (dependabot) |

- **Severity:** 🟡 Warning if any workflow has > 15% failure rate; 🔴 Critical if > 30%.
- **Output:** Table of workflows with run counts, success rate, last run status.

#### W3 — GitHub Actions: Cancelled / Timed-out Runs (last 24h)

```
GET /repos/dotnet/machinelearning/actions/runs?branch=main&status=cancelled&per_page=10
```

- **Severity:** 🟡 Warning if any cancellations in last 24h.
- **Output:** List with links.

#### W4 — Azure DevOps CI Status (heuristic)

Since we cannot directly call Azure DevOps APIs from this workflow, use a heuristic approach:
- Check for recent issues with `blocking-clean-ci` or `Known Build Error` labels:
  ```
  GET /repos/dotnet/machinelearning/issues?labels=blocking-clean-ci&state=open&per_page=10
  GET /repos/dotnet/machinelearning/issues?labels=Known+Build+Error&state=open&per_page=10
  ```
- Check commit status on the latest main commit:
  ```
  GET /repos/dotnet/machinelearning/commits/main/status
  ```
- **Severity:** 🔴 Critical if there are open `blocking-clean-ci` issues; 🟡 Warning if `Known Build Error` issues exist.
- **Output:** Count + list of blocking CI issues, latest commit status summary.

---

### 4.3 Concerning Bugs & PRs

#### C1 — High-Priority Open Bugs (P0 and P1)

```
GET /repos/dotnet/machinelearning/issues?labels=P0&state=open&per_page=10
GET /repos/dotnet/machinelearning/issues?labels=P1&state=open&per_page=50
```

- **Severity:** 🔴 Critical for each P0; 🟡 Warning for P1s open > 30 days.
- **Output:** Table with title, assignee, age, milestone.

#### C2 — Bug Count Trends

```
GET /repos/dotnet/machinelearning/issues?labels=bug&state=open&per_page=100
```

Compare current open bug count against previous value from `cache-memory`.

- **Severity:** 🟡 Warning if net increase > 5 in last 7 days.
- **Output:** Current open bug count, 7-day delta, trend arrow.

#### C3 — Stale PRs (open > 90 days)

From M4 data, filter PRs open > 90 days.

- **Severity:** 🟡 Warning.
- **Output:** List with title, author, age, last activity date.

#### C4 — PRs with Failing CI

For each open PR, check status:
```
GET /repos/dotnet/machinelearning/pulls/{number}/checks
```
or from the combined status endpoint.

Flag PRs where **all checks are failing**.

- **Severity:** 🟡 Warning.
- **Output:** List with links.

#### C5 — Security-Related Issues

```
GET /repos/dotnet/machinelearning/issues?labels=Security&state=open&per_page=10
```

- **Severity:** 🔴 Critical if any open.
- **Output:** Count + list.

#### ~~C6 — Discussion Activity Pulse~~ — REMOVED

> **Decision:** GitHub Discussions are **not enabled** on `dotnet/machinelearning`
> (`has_discussions: false` confirmed via GitHub API). This check is removed entirely.
> If Discussions are enabled in the future, this section can be re-added.

#### C7 — Issue Velocity & Health Metrics

Compute from API data (use `cache-memory` for historical comparison):

| Metric | API Source |
|--------|-----------|
| Issues opened (last 7d) | `GET /repos/.../issues?since={7d_ago}&state=all&per_page=100` filtered by `created_at` |
| Issues closed (last 7d) | `GET /repos/.../issues?state=closed&sort=updated&direction=desc&per_page=100` filtered by `closed_at` |
| PRs merged (last 7d) | `GET /repos/.../pulls?state=closed&sort=updated&direction=desc&per_page=50` filter `merged_at` |
| Open issue count | From repo API `open_issues_count` |
| Open PR count | From pulls list |

- **Output:** Trends table with 7-day averages and deltas.

---

## 5. Step 2 — Analysis (LLM-Powered)

Using the collected data, the agent should generate:

1. **Executive Summary** — 2-3 sentences describing overall repo health and what changed since last run.

2. **Maintainer Action Required** — Prioritized list:
   - 🔴 Items requiring **immediate** attention (P0 bugs, security issues, CI failures on main)
   - 🟡 Items requiring **timely** attention (unanswered community questions, un-reviewed PRs, untriaged issues)
   - 🔵 Informational items (trends, metrics)

3. **Correlation Insights** — Connect related findings:
   - Many untriaged issues + no recent maintainer comments → possible maintainer bandwidth issue
   - CI failures + open `blocking-clean-ci` issues → known CI problem
   - Stale PRs from community + no reviews → community engagement concern
   - Rising bug count + no P0/P1 triage → potential triage backlog

4. **Recommendations** — Actionable next steps for maintainers.

---

## 6. Step 3 — Output

### 6.1 Find or Create Dashboard Issue (Cross-Repo)

1. Search for open issues with label `repo-health` in `dotnet/machinelearning`:
   ```
   GET /repos/dotnet/machinelearning/issues?labels=repo-health&state=open&per_page=5
   ```
   (Uses the `github` tool with `CROSS_REPO_PAT` for read access.)

2. If exactly one exists → use `update-issue` safe-output with `operation: replace` to overwrite its body.
3. If none exist:
   a. Use `create-issue` safe-output (with `target-repo: "dotnet/machinelearning"`) to create one
      with title `🏥 ML.NET Repository Health Dashboard` and label `repo-health`.
   b. If the `repo-health` label doesn't exist yet, use `add-labels` safe-output to create it.
   c. **Manual step required:** A maintainer must pin the issue after first creation (no `pin-issue` safe-output exists).
4. If multiple exist → update the most recently created one; use `close-issue` safe-output for the others.
5. Store the issue number in `cache-memory` file for quick lookup on subsequent runs.

### 6.2 Issue Body Format

The entire issue body is **replaced** on each run. Structure:

```markdown
# 🏥 ML.NET Repository Health Dashboard — {date}

**Overall:** {overall_emoji} {overall_status}
**Status:** 🔴 {critical_count} critical · 🟡 {warning_count} warnings · 🔵 {info_count} info

> {executive_summary}

---

## 🚨 Maintainer Action Required

### Immediate (🔴 Critical)
{List of critical items — P0 bugs, security issues, CI failures, long-unreviewed community PRs}

### Timely (🟡 Warning)
{List of warning items — untriaged issues, unanswered questions, stale PRs}

---

## 📬 Pending Community Interactions

> Items where a community member is waiting for a maintainer response.

| # | Title | Type | Author | Waiting Since | Last Activity |
|---|-------|------|--------|--------------|---------------|
{For each item needing maintainer follow-up}

**Summary:** {X} issues/PRs awaiting maintainer response · {Y} untriaged issues · {Z} unreviewed PRs

---

## 🔧 CI / Workflow Health

### GitHub Actions (last 24h)
| Workflow | Runs | ✅ Pass | ❌ Fail | ⏹️ Cancel | Rate |
|----------|------|---------|---------|-----------|------|
{For each workflow}

### Azure DevOps Status
- Latest `main` commit status: {status}
- Open `blocking-clean-ci` issues: {count}
- Open `Known Build Error` issues: {count}

{Details of any failures with links}

---

## 🐛 Bug & Issue Landscape

| Metric | Current | 7d Ago | Δ | Trend |
|--------|---------|--------|---|-------|
| Open issues (total) | {n} | {n} | {delta} | {arrow} |
| Open bugs | {n} | {n} | {delta} | {arrow} |
| Untriaged issues | {n} | {n} | {delta} | {arrow} |
| Open P0 | {n} | | | |
| Open P1 | {n} | | | |
| Issues opened (7d) | {n} | | | |
| Issues closed (7d) | {n} | | | |

### High-Priority Bugs (P0/P1)
{Table of P0/P1 issues with title, assignee, age, milestone}

---

## 📥 Pull Request Status

| Metric | Current | 7d Ago | Δ | Trend |
|--------|---------|--------|---|-------|
| Open PRs | {n} | {n} | {delta} | {arrow} |
| PRs merged (7d) | {n} | | | |
| Avg PR age (open) | {days} | | | |
| Community PRs awaiting review | {n} | | | |

### Open PRs
| # | Title | Author | Age | Reviews | CI | Labels |
|---|-------|--------|-----|---------|----| -------|
{For each open PR}

---

## 📊 7-Day Trends

| Metric | Today | 7d Avg | Δ | Trend |
|--------|-------|--------|---|-------|
| Issues opened/day | {n} | {avg} | {delta} | {arrow} |
| Issues closed/day | {n} | {avg} | {delta} | {arrow} |
| PRs merged/day | {n} | {avg} | {delta} | {arrow} |
| GH Actions pass rate | {%} | {avg} | {delta} | {arrow} |

---

## 💡 Recommendations

{Numbered list of actionable recommendations}

---

<sub>🤖 Generated by ML.NET Repo Health Check · [Run #{run_number}]({run_url}) · {timestamp} UTC</sub>
```

**Size guard:** If the issue body exceeds 60k characters:
- Always show **Maintainer Action Required** and **Pending Community Interactions** in full.
- Collapse other sections with `<details>` tags.
- Append footer: `> … Content truncated — see workflow run for full report.`

### 6.3 Daily Summary Comment

After updating the issue body, post a daily comment for the audit trail:

```markdown
## 📋 Health Check — {date}

**Overall:** {overall_emoji} {overall_status}
🔴 {critical_count} · 🟡 {warning_count} · 🔵 {info_count}

**Key Changes Since Yesterday:**
{bullet list of what changed — new findings, resolved items, trend shifts}

**Snapshot:**
- Untriaged issues: {n} ({delta})
- Open bugs: {n} ({delta})
- Unanswered questions: {n}
- Unreviewed PRs: {n}
- CI status: {pass_emoji} GH Actions / {pass_emoji} AzDO
- Community items awaiting response: {n}

[Full dashboard →]({issue_url})
```

---

## 7. Step 4 — History Pruning

### 7.1 Retention Policy

| Age of Comment | Retention |
|---------------|-----------|
| ≤ 10 days | Keep all daily comments |
| 11 days – 1 year | Keep **one comment per week** (the latest one from each ISO week) |
| > 1 year | **Hide** (minimize) |

### 7.2 Key Constraint: `hide-comment` vs. `delete-comment`

gh-aw provides **`hide-comment`** but does **not** provide a `delete-comment` safe-output.
`hide-comment` collapses a comment with a reason (e.g., `"OUTDATED"`), making it minimized
in the UI but **not permanently removed**.

**Implications:**
- Comments older than 1 year will be **hidden/minimized**, not deleted.
- Over very long periods (years), the issue may accumulate many hidden comments.
- This is acceptable because hidden comments don't clutter the visible timeline.
- If true deletion becomes necessary in the future, a separate GitHub Actions workflow
  (not agentic) could use `github-script` with the REST API to delete comments.

### 7.3 Pruning Algorithm

```
1. Fetch ALL comments on the health issue:
   GET /repos/dotnet/machinelearning/issues/{number}/comments?per_page=100
   (paginate if needed; use github tool with CROSS_REPO_PAT)

2. Filter to only comments authored by the workflow bot
   (match by author login or by comment body starting with "## 📋 Health Check")

3. For each comment, parse the date from the title "## 📋 Health Check — {date}"

4. Classify into buckets:
   a. age ≤ 10 days         → KEEP (daily)
   b. 10 days < age ≤ 1 year → GROUP by ISO week number + year
      - Within each week group, keep only the LATEST comment
      - Mark others for HIDING
   c. age > 1 year           → mark for HIDING

5. Hide all marked comments using hide-comment safe-output:
   Each call: hide-comment with target comment ID and reason "OUTDATED"
   (safe-output configured with max: 60 per run)

6. Log: "Pruned {N} comments: {X} older than 1 year, {Y} redundant within-week"
```

### 7.4 Edge Cases

- **First run:** No comments exist. Skip pruning entirely.
- **Manual comments:** Only prune comments matching the bot pattern. Never hide human-authored comments.
- **Rate limits:** Max 60 hide operations per run (enforced by safe-output `max: 60`). If more than 60 need pruning, prioritize oldest first and catch up on next run.
- **Missing dates:** If a comment's date cannot be parsed, skip it (don't hide).
- **Already hidden comments:** Skip comments that are already minimized.

---

## 8. Cache / State Management

### 8.1 What is `cache-memory`?

`cache-memory` is a gh-aw feature that provides **persistent file-based storage** across workflow runs.
It works by storing files at `/tmp/gh-aw/cache-memory/` during a run, then persisting them via
GitHub Actions’ cache mechanism between runs.

**Key characteristics:**
- **Storage:** Plain files on disk at `/tmp/gh-aw/cache-memory/` — typically JSON files.
- **Retention:** 7-day sliding window (GitHub Actions cache eviction). If the workflow runs
  daily, cache is always warm. If it stops running for > 7 days, state is lost.
- **Size:** Up to 10 GB per repository (shared with all Actions caches).
- **Progressive restore:** Uses key + restore-keys fallback pattern. If the exact key misses,
  the most recent matching prefix is restored.
- **Read/write:** The agent reads and writes these files using `bash` tools
  (`cat`, `jq`) and `edit` tool. There is no key-value API — it’s raw file I/O.

### 8.2 Cache Files Schema

| File Path | Format | Purpose |
|-----------|--------|----------|
| `/tmp/gh-aw/cache-memory/ml-health-issue-number.json` | `{ "number": 1234 }` | Quick lookup of the dashboard issue number |
| `/tmp/gh-aw/cache-memory/ml-health-last-run.json` | `{ "date": "...", "metrics": { ... } }` | Previous run snapshot for delta computation |
| `/tmp/gh-aw/cache-memory/ml-health-history.json` | `[{ "date": "...", "critical": N, "warning": N, "untriaged": N, "bugs": N, "prs": N }]` | Rolling 30-day metrics for trend table |
| `/tmp/gh-aw/cache-memory/ml-health-maintainers.json` | `["rokonec"]` | Known maintainer list (editable without code changes) |

### 8.3 Cache Lifecycle

1. **First run (cold start):** No cache files exist. The agent should:
   - Skip delta/trend computations (display “N/A” for deltas).
   - Seed `ml-health-maintainers.json` with the initial maintainer list from the prompt.
   - Create all other files with current-run data.

2. **Subsequent runs (warm cache):** Read previous state, compute deltas, then overwrite
   files with updated data.

3. **Cache miss after gap:** If the workflow hasn’t run for > 7 days, cache may be evicted.
   Treat the same as first run. The comment history on the issue still serves as a
   long-term audit trail independent of cache.

### 8.4 Updating Maintainer List

To update the maintainer list without modifying the workflow:
1. Trigger a `workflow_dispatch` run.
2. The agent reads `/tmp/gh-aw/cache-memory/ml-health-maintainers.json`.
3. A maintainer can manually edit this file in a fork/PR, or the agent can be instructed
   via a prompt override to add/remove names.

**Initial maintainer list:**
```json
["rokonec"]
```

**Known bots (always excluded from “community” classification):**
```json
["dotnet-maestro[bot]", "github-actions[bot]", "copilot[bot]", "dependabot[bot]"]
```

---

## 9. Data Collection — API Call Summary

All API calls target `dotnet/machinelearning` via the `github` tool configured with `CROSS_REPO_PAT`.

| Check | API Endpoint(s) | Per-page | Notes |
|-------|-----------------|----------|-------|
| M1 — Untriaged | `issues?labels=untriaged&state=open` | 100 | May need pagination (211 currently) |
| M2 — Awaiting User Input | `issues?labels=Awaiting+User+Input&state=open` | 50 | + comments per issue |
| M3 — Unanswered questions | `issues?labels=question&state=open` | 50 | + comments per issue (expensive) |
| M4 — PRs needing review | `pulls?state=open` | 50 | + reviews per PR |
| M5 — Community follow-up | `issues?state=open&sort=updated&direction=desc` | 50 | + comments per issue |
| W1 — Failed GH Actions | `actions/runs?branch=main&status=failure` | 30 | Filter last 24h |
| W2 — Workflow summary | `actions/runs?branch=main` | 100 | Group by workflow |
| W3 — Cancelled runs | `actions/runs?branch=main&status=cancelled` | 10 | Filter last 24h |
| W4 — AzDO heuristic | `issues?labels=blocking-clean-ci`, `commits/main/status` | 10 | Indirect |
| C1 — P0/P1 bugs | `issues?labels=P0`, `issues?labels=P1` | 10/50 | |
| C2 — Bug trends | `issues?labels=bug&state=open` | 100 | Compare with cache |
| C3 — Stale PRs | (from M4) | — | Filter >90 days |
| C4 — PRs failing CI | Per PR check runs | — | Expensive, limit to open PRs |
| C5 — Security issues | `issues?labels=Security&state=open` | 10 | |
| ~~C6 — Discussions~~ | — | — | **Removed** (discussions disabled on repo) |
| C7 — Velocity | `issues?since=...`, `pulls?state=closed` | 100 | Multiple endpoints |

**Estimated API calls per run:** ~30-80 (depending on open item count for per-item review/comment checks).

---

## 10. Severity Framework

| Level | Emoji | Meaning | Examples |
|-------|-------|---------|---------|
| Critical | 🔴 | Needs immediate maintainer attention | P0 bug, security issue, CI broken on main, community PR unreviewed >30 days |
| Warning | 🟡 | Needs timely attention | Untriaged backlog growing, unanswered questions >7d, stale PRs |
| Info | 🔵 | Metric / trend — no action needed | Issue velocity, PR merge rate, open counts |

**Overall Health Computation:**
- 🔴 **Unhealthy** — Any critical findings exist
- 🟡 **Needs Attention** — No critical, but warnings present
- 🟢 **Healthy** — Only info-level findings

---

## 11. Error Handling / Graceful Degradation

| Scenario | Behavior |
|----------|----------|
| API call returns 404 or 403 | Skip that check, note in output: "⚠️ Skipped: {check} (API error)" |
| Rate limit hit | Pause, retry once. If still limited, skip remaining checks in that category. |
| No `cache-memory` state | First run — skip delta/trend computations, seed files, note in output |
| Issue body > 60k chars | Truncate per size guard rules (§6.2) |
| Comment date unparseable | Skip that comment in pruning |
| Cross-repo PAT invalid | Fail with clear error — all operations depend on `CROSS_REPO_PAT` |

---

## 12. Implementation Checklist

### Phase 1: Core Workflow File
- [ ] Create `.github/workflows/ml-repo-health-check.md` with front-matter and full prompt
- [ ] Configure cross-repo tools (`github-token: ${{ secrets.CROSS_REPO_PAT }}`)
- [ ] Configure cross-repo safe-outputs (`target-repo`, `github-token`)
- [ ] Define the `repo-health` label specification
- [ ] Implement M1–M5 (Maintainer Actions) data collection instructions
- [ ] Implement W1–W4 (Workflow Health) data collection instructions
- [ ] Implement C1–C5, C7 (Concerning Items) data collection instructions (C6 removed)
- [ ] Write the Analysis step instructions (summary, correlation, recommendations)

### Phase 2: Output System
- [ ] Implement §6.1 — Cross-repo issue find/create logic with safe-outputs
- [ ] Implement §6.2 — Issue body template (`update-issue` with `operation: replace`)
- [ ] Implement §6.3 — Daily comment format (`add-comment` with `target-repo`)
- [ ] Implement size guard (60k char limit)
- [ ] Document manual pin step for first-time setup

### Phase 3: History Pruning
- [ ] Implement §7.3 — Comment enumeration and date parsing (cross-repo read)
- [ ] Implement retention bucketing (daily ≤10d, weekly ≤1yr, hide >1yr)
- [ ] Implement `hide-comment` safe-output calls with reason `"OUTDATED"`
- [ ] Handle edge cases (first run, manual comments, parse failures, already hidden)

### Phase 4: State Management
- [ ] Define `cache-memory` file schema (JSON files at `/tmp/gh-aw/cache-memory/`)
- [ ] Implement cold-start detection and seed files
- [ ] Implement delta computation (compare current vs previous metrics)
- [ ] Implement 7-day trend computation
- [ ] Seed and manage maintainer list file

### Phase 5: Secrets & Setup
- [ ] Create `CROSS_REPO_PAT` secret in `GH-AW-Tests` repo
- [ ] Verify PAT has required scopes (see §16)
- [ ] Manual first-run via `workflow_dispatch` to create the dashboard issue
- [ ] Manually pin the created issue in `dotnet/machinelearning`

### Phase 6: Testing & Tuning
- [ ] Manual `workflow_dispatch` trigger and verify output
- [ ] Verify comment pruning with `hide-comment`
- [ ] Tune severity thresholds based on actual repo state
- [ ] Verify the maintainer list is accurate and up to date
- [ ] Test first-run behavior (no cache, no existing issue)
- [ ] Test issue body size guard with large data sets
- [ ] Compile workflow: `gh aw compile` and verify `.lock.yml`

---

## 13. Key Differences from the DevOps Health Check Inspiration

| Aspect | DevOps Health Check (dotnet/skills) | ML.NET Repo Health Check |
|--------|-------------------------------------|--------------------------|
| **Primary focus** | Pipeline health, skill quality benchmarks | Maintainer responsiveness, community health, CI status |
| **CI system** | GitHub Actions only | Azure DevOps (primary) + GitHub Actions (auxiliary) |
| **Fingerprint & diff** | Full fingerprint-based diff system | Simpler delta approach — compare metrics snapshots |
| **Triage dispatch** | Dispatches investigation workers | No dispatch — just reports findings |
| **Comment history** | Single daily comment, no pruning | Pruned history: daily ≤10d, weekly ≤1yr, hide >1yr |
| **Hosting model** | Same repo as target | Cross-repo (GH-AW-Tests → dotnet/machinelearning) |
| **Skill/benchmark tracking** | Deep benchmark analysis (Q1-Q7) | Not applicable |
| **Community focus** | Low (internal project) | High — tracks unanswered questions, unreviewed PRs, response times |
| **Dashboard emphasis** | What's broken/regressed | What needs human attention + overall repo vitality |

---

## 14. Relevant Labels in dotnet/machinelearning

These existing labels will be used for data collection queries:

| Label | Open Issues | Use in Workflow |
|-------|-------------|-----------------|
| `untriaged` | 211 | M1 — Untriaged backlog |
| `bug` | 58 | C2 — Bug count trends |
| `question` | 52 | M3 — Unanswered questions |
| `enhancement` | 376 | C7 — Velocity context |
| `need info` | 20 | Context for triaged-but-incomplete |
| `needs-further-triage` | 39 | M1 — Extended triage backlog |
| `Awaiting User Input` | 4 | M2 — Waiting for author |
| `P0` | 1 | C1 — Critical bugs |
| `P1` | 23 | C1 — High-priority bugs |
| `P2` | 298 | Context metric |
| `P3` | 101 | Context metric |
| `blocking-clean-ci` | 16 | W4 — CI health heuristic |
| `Known Build Error` | 16 | W4 — CI health heuristic |
| `Security` | 1 | C5 — Security concerns |
| `community-contribution` | 5 PRs | M4 — Community PR review priority |

---

## 15. Resolved Decisions

All open questions from the initial design have been resolved:

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | **Which repo hosts the workflow?** | `GH-AW-Tests` (this repo), separate from target | Security: no code-write access needed to `dotnet/machinelearning`. Uses cross-repo safe-outputs with `target-repo` + `CROSS_REPO_PAT`. |
| 2 | **Maintainer list maintenance** | Stored in `cache-memory` file (`ml-health-maintainers.json`). No CODEOWNERS. Initial list: `rokonec`. | Editable without code changes. Seeded from prompt on first run. Can be updated by editing the cache file or updating the workflow prompt. |
| 3 | **Azure DevOps visibility** | Heuristic approach: `blocking-clean-ci` / `Known Build Error` labels + `commits/main/status` | Direct AzDO API access not available from gh-aw. Heuristic covers the most visible CI health signals. Can enhance later if insufficient. |
| 4 | **Discussions** | **Removed** (C6 eliminated) | `has_discussions: false` confirmed via GitHub API for `dotnet/machinelearning`. |
| 5 | **Comment management** | Use `hide-comment` safe-output (not delete) | gh-aw provides `hide-comment` but no `delete-comment`. Hidden comments are collapsed with reason `"OUTDATED"` — not permanently removed but invisible in normal browsing. Acceptable trade-off. |
| 6 | **Issue pinning** | Manual one-time step by maintainer | No `pin-issue` safe-output exists in gh-aw. After first-run creates the issue, a maintainer must pin it manually. |

---

## 16. Required Secrets & Permissions

### 16.1 `CROSS_REPO_PAT` Secret

A GitHub Personal Access Token (classic or fine-grained) must be stored as a repository
secret named `CROSS_REPO_PAT` in the `GH-AW-Tests` repository.

#### Option A: Fine-Grained PAT (Recommended)

| Setting | Value |
|---------|-------|
| **Resource owner** | `dotnet` (organization) |
| **Repository access** | `dotnet/machinelearning` only |
| **Permissions** | |
|   Issues | Read & Write (create issue, update body, add comment, hide comment, add labels) |
|   Pull requests | Read (list PRs, read reviews, read check runs) |
|   Actions | Read (list workflow runs, check statuses) |
|   Contents | Read (read commit status) |
|   Metadata | Read (always required) |

#### Option B: Classic PAT

| Scope | Purpose |
|-------|----------|
| `repo` | Full repository access (broader than needed, but simplest) |

> **Security note:** Fine-grained PAT is strongly preferred as it follows principle of
> least privilege. The classic PAT `repo` scope grants full access to all repos the user
> can access.

### 16.2 Workflow Permissions (in this repo)

The `permissions` block in the front-matter governs the `GITHUB_TOKEN` for the **hosting repo**
(`GH-AW-Tests`), not the target repo. Cross-repo access is entirely through `CROSS_REPO_PAT`.

```yaml
permissions:
  contents: read       # Read workflow files in this repo
  actions: read        # Read action run metadata in this repo
  issues: read         # Not strictly needed (we write to target repo)
  pull-requests: read  # Not strictly needed (we read from target repo)
```

### 16.3 Safe-Output Permissions Summary

| Safe-Output | Action on Target Repo | Required PAT Permission |
|-------------|----------------------|------------------------|
| `create-issue` | Create new issue in `dotnet/machinelearning` | Issues: Write |
| `update-issue` | Replace issue body | Issues: Write |
| `add-comment` | Post daily summary comment | Issues: Write |
| `hide-comment` | Collapse old comments | Issues: Write |
| `add-labels` | Create/apply `repo-health` label | Issues: Write |

### 16.4 First-Time Setup Checklist

1. Create a fine-grained PAT with permissions listed in §16.1.
2. Add it as secret `CROSS_REPO_PAT` in `GH-AW-Tests` → Settings → Secrets → Actions.
3. Compile the workflow: `gh aw compile`.
4. Push the `.md` and `.lock.yml` files.
5. Trigger a manual `workflow_dispatch` run.
6. After the issue is created in `dotnet/machinelearning`, **manually pin it**.
7. Verify the dashboard renders correctly and the daily comment appears.

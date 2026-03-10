# Research: GitHub Discussions Access via gh-aw GitHub MCP Tools

## Executive Summary

**Yes, a `discussions` toolset exists** in the GitHub MCP Server and can be used by gh-aw workflows. However, **none of the workflows in JanKrivanek/machinelearning currently use it**. Enabling it requires simply adding `discussions` to the `toolsets` array in the workflow's YAML frontmatter.

---

## 1. Complete List of Available GitHub MCP Server Toolsets

Source: [github/github-mcp-server README](https://github.com/github/github-mcp-server) (v0.31.0, the version used by gh-aw v0.53.6)

| Toolset | Description | In Default Set? |
|---------|-------------|-----------------|
| `context` | User/GitHub context info (strongly recommended) | ✅ Yes |
| `repos` | Repository-related tools (files, branches, commits, releases, search) | ✅ Yes |
| `issues` | Issues CRUD, search, sub-issues, labels | ✅ Yes |
| `pull_requests` | PR CRUD, reviews, diffs, merge | ✅ Yes |
| `users` | User search and profile | ✅ Yes |
| `actions` | GitHub Actions workflows, runs, jobs, artifacts, logs | ❌ No |
| `code_security` | Code scanning alerts | ❌ No |
| `copilot` | Copilot-related tools (assign to issue, request review) | ❌ No |
| `dependabot` | Dependabot alerts | ❌ No |
| **`discussions`** | **GitHub Discussions: read, list, comments, categories** | **❌ No** |
| `gists` | Gist CRUD | ❌ No |
| `git` | Low-level Git API (tree operations) | ❌ No |
| `labels` | Label CRUD | ❌ No |
| `notifications` | Notification management | ❌ No |
| `orgs` | Organization tools | ❌ No |
| `projects` | GitHub Projects (v2) management | ❌ No |
| `secret_protection` | Secret scanning alerts | ❌ No |
| `security_advisories` | Security advisories | ❌ No |
| `stargazers` | Star/unstar repositories | ❌ No |

**Special toolsets:**
- `all` — enables every toolset
- `default` — equivalent to `context, repos, issues, pull_requests, users`

**Remote-only additional toolsets:** `copilot`, `copilot_spaces`, `github_support_docs_search`

---

## 2. Discussions Toolset — Available Tools

When the `discussions` toolset is enabled, the following MCP tools become available:

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `get_discussion` | Get a single discussion | `owner`, `repo`, `discussionNumber` |
| `get_discussion_comments` | Get comments on a discussion | `owner`, `repo`, `discussionNumber`, pagination (`after`, `perPage`) |
| `list_discussion_categories` | List discussion categories for a repo/org | `owner`, `repo` (optional) |
| `list_discussions` | List discussions with filtering | `owner`, `repo` (optional), `category`, `orderBy`, `direction`, pagination |

**Required OAuth scope:** `repo`

**Note:** These are **read-only** tools. There is no `create_discussion` or `update_discussion` in the `discussions` toolset. However, `create_discussion` exists as a **safe-output** type at the gh-aw framework level (see Section 5).

---

## 3. JanKrivanek/machinelearning — Current Workflow Toolset Usage

None of the 7 gh-aw workflows in this repository use the `discussions` toolset:

| Workflow File | Name | Toolsets | Purpose |
|---------------|------|----------|---------|
| `triage-stats.md` | Triage Stats Dashboard | `[repos, issues]` | Aggregates triage issues → dashboard |
| `bulk-triage.md` | Bulk Triage | `[repos, issues, actions]` | Orchestrates batch upstream issue triage |
| `triage-single-issue.md` | Triage Single Issue | `[repos, issues, pull_requests]` | Triages one upstream issue |
| `repo-health-check.md` | Repo Health Check | `[repos, issues, pull_requests, actions]` | Daily health dashboard |
| `repo-health-investigate.md` | Repo Health Investigate | `[repos, issues, pull_requests, actions]` | Deep-dive on health findings |
| `repo-health-groom.md` | Repo Health Groom | `[repos, issues]` | Dashboard cleanup/grooming |
| `refresh-dashboard.md` | Refresh Triage Dashboard | `[repos, issues]` | Idempotent dashboard refresh |

### How triage-stats.md Gathers Data

The `triage-stats.md` workflow gathers data **exclusively via `gh issue list`**, not discussions:

```bash
gh issue list --repo "$GITHUB_REPOSITORY" --label "triage" --state all \
  --json number,title,body,labels,state,createdAt --limit 200
```

It uses only the `issues` toolset MCP tools for API access, and `bash` tools for CLI commands.

---

## 4. How to Enable Discussions Access in a gh-aw Workflow

### Step 1: Add the toolset to frontmatter

```yaml
---
name: "My Workflow"
description: "A workflow that reads discussions"

tools:
  github:
    toolsets: [repos, issues, discussions]  # <-- add 'discussions' here
  bash: ["gh", "jq", "echo"]

permissions:
  contents: read
  # Note: discussions don't have a separate GitHub Actions permission;
  # the MCP server uses the token's OAuth scopes (requires 'repo' scope)
---
```

### Step 2: Recompile the lock file

```bash
gh aw compile
```

This will regenerate the `.lock.yml` file, which will set:
```yaml
"GITHUB_TOOLSETS": "repos,issues,discussions"
```

### Step 3: Use discussions tools in the workflow body

The agent can then use MCP tools like:
- `list_discussions` to enumerate discussions
- `get_discussion` to read a specific discussion
- `get_discussion_comments` to get comments
- `list_discussion_categories` to discover categories

Or use `gh` CLI commands via bash tools:
```bash
# List discussions via GraphQL (gh CLI)
gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      discussions(first: 10, orderBy: {field: CREATED_AT, direction: DESC}) {
        nodes { number title bodyText category { name } }
      }
    }
  }
' -f owner="OWNER" -f repo="REPO"
```

---

## 5. Discussions in Safe-Outputs (Writing/Creating)

The `discussions` toolset only provides **read** capabilities via MCP tools. However, the gh-aw framework has a built-in `create_discussion` **safe-output** type.

Evidence from the lock.yml files — the `create_issue` tool description says:
> "For reports, announcements, or status updates that don't require task tracking, use **create_discussion** instead."

And the `safe_outputs` job exposes outputs for:
- `create_discussion_error_count`
- `create_discussion_errors`

This means **creating discussions** is done via gh-aw's safe-output mechanism, not directly through MCP tools. To use it, add to frontmatter:

```yaml
safe-outputs:
  create-discussion:
    category: "Announcements"  # Discussion category
    max: 1
```

---

## 6. Built-in Discussion Event Context

All gh-aw workflows (regardless of toolsets) have access to the discussion event number when triggered by a discussion event:

```yaml
GH_AW_GITHUB_EVENT_DISCUSSION_NUMBER: ${{ github.event.discussion.number }}
```

This is injected into the prompt as:
```
- **discussion-number**: #<NUMBER>
```

This means workflows triggered `on: discussion` events automatically receive the discussion context, even without the `discussions` toolset enabled.

---

## 7. Architecture Summary

```
┌─────────────────────────────────────────────────┐
│            gh-aw Workflow (.md file)             │
│                                                   │
│  tools:                                           │
│    github:                                        │
│      toolsets: [repos, issues, discussions]       │
│    bash: [...]                                    │
│                                                   │
│  safe-outputs:                                    │
│    create-discussion: { category: "...", max: 1 } │
└────────────────┬────────────────────────────────┘
                 │ gh aw compile
                 ▼
┌─────────────────────────────────────────────────┐
│           Compiled Lock File (.lock.yml)          │
│                                                   │
│  MCP Config:                                      │
│    github:                                        │
│      container: github-mcp-server:v0.31.0        │
│      env:                                         │
│        GITHUB_TOOLSETS: "repos,issues,discussions"│
│        GITHUB_READ_ONLY: "1"                      │
│    safeoutputs:                                   │
│      type: http (MCP server for safe outputs)    │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│          GitHub MCP Server (v0.31.0)              │
│                                                   │
│  Enabled tools (discussions toolset):             │
│    - get_discussion                               │
│    - get_discussion_comments                      │
│    - list_discussion_categories                   │
│    - list_discussions                              │
│                                                   │
│  + tools from other enabled toolsets              │
└─────────────────────────────────────────────────┘
```

---

## 8. Key Takeaways

1. **`discussions` is a fully supported toolset** in the GitHub MCP Server — it just needs to be explicitly enabled since it's not in the default set.

2. **No workflow in JanKrivanek/machinelearning currently reads discussions** — all data gathering is via issues and PRs.

3. **Enabling it is trivial** — add `discussions` to the `toolsets` array and recompile.

4. **Read vs Write split:**
   - **Reading** discussions → enable the `discussions` toolset (MCP tools)
   - **Creating** discussions → use `create-discussion` safe-output
   - **gh CLI/GraphQL** → available via `bash` tools if `gh` is in the allowed commands

5. **The MCP server runs in read-only mode** (`GITHUB_READ_ONLY: "1"`) in gh-aw workflows, so even with the `discussions` toolset enabled, only read operations are available through MCP. Write operations must go through safe-outputs.

6. **Token permissions**: The GitHub MCP server token needs `repo` scope for discussions access. The workflows already use `GITHUB_MCP_SERVER_TOKEN` which likely has this scope.

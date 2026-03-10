---
description: >
  Finalization workflow that runs after all MSBuild issue investigations
  are complete. Reads investigation comments from the discussion, extracts
  summaries, and updates the discussion body with consolidated results.

on:
  workflow_dispatch:
    inputs:
      discussion_id:
        description: "Discussion number containing investigation results"
        required: true
        type: string

permissions:
  contents: read
  issues: read
  discussions: read

tools:
  github:
    toolsets: [repos, issues, discussions]
  bash: ["cat", "grep", "head", "tail", "wc", "jq", "date", "sort", "uniq", "echo", "sed", "awk"]

safe-outputs:
  add-comment:
    target: "*"
    max: 1
  noop:

network:
  allowed:
    - github
---

# MSBuild Investigation Summary

You are an AI agent that consolidates investigation results from the MSBuild weekly report
discussion #__GH_AW_GITHUB_EVENT_INPUTS_DISCUSSION_ID__.

<!-- compiler-hint: ${{ github.event.inputs.discussion_id }} -->

Your job is to:
1. Read all comments on discussion #__GH_AW_GITHUB_EVENT_INPUTS_DISCUSSION_ID__
2. Extract investigation summaries from comments posted by the investigation workflows
3. Update the discussion body to include a consolidated summary with links to detailed comments

## CRITICAL TOOL USAGE RULES

**For ALL data collection from GitHub, you MUST use the `github` MCP tool.**

**DO NOT** attempt to:
- Run `gh api` commands via bash
- Run `curl` commands

---

## Step 1: Read the Discussion

Use github tools to:
1. Get discussion #__GH_AW_GITHUB_EVENT_INPUTS_DISCUSSION_ID__ — read the full body
2. List ALL comments on the discussion
3. Identify comments that contain investigation results (they will have the pattern `## 🔍 Investigation: Issue #`)

For each investigation comment, extract:
- **Issue number** and **title**
- **Classification** (Bug/Regression/Performance)
- **Reproduction status** (Reproduced / Not reproduced / Inconclusive)
- **Summary** (the 2-3 sentence summary)
- **Comment URL/ID** (for linking)

---

## Step 2: Build the Summary Table

Create a consolidated summary table:

```markdown
## 🧪 Investigation Results

| # | Title | Classification | Reproduced? | Summary | Details |
|---|-------|----------------|-------------|---------|---------|
| [#NNN](link) | <title> | Bug | ✅ Yes | <brief summary> | [View details](#comment-link) |
| ... | ... | ... | ... | ... | ... |
```

Include:
- **Stats line**: "Investigated X issue(s): Y reproduced, Z not reproduced, W inconclusive"
- The summary table
- If no investigation comments were found, note: "No investigation results found. Investigations may still be in progress."

---

## Step 3: Post Summary Comment

Use the `add-comment` safe output to post a summary comment on discussion #__GH_AW_GITHUB_EVENT_INPUTS_DISCUSSION_ID__.

The comment should contain:

```markdown
## 🧪 Investigation Results Summary

**Summary:** Investigated X issue(s) — Y reproduced, Z not reproduced, W inconclusive

| # | Title | Classification | Reproduced? | Summary | Details |
|---|-------|----------------|-------------|---------|---------|
| [#NNN](link) | <title> | Bug | ✅ Yes | <brief summary> | [View details](#comment-link) |
| ... | ... | ... | ... | ... | ... |

---
_Investigation summary generated automatically. See individual comments above for full details._
```

## If No Investigation Comments Found

If there are no investigation comments on the discussion, call `noop` with a descriptive message explaining why no summary can be generated.

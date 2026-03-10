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

tools:
  github:
    toolsets: [repos, issues]
  bash: ["cat", "grep", "head", "tail", "wc", "jq", "date", "sort", "uniq", "echo", "sed", "awk"]

safe-outputs:
  update-discussion:
    target: "*"
    max: 1
  noop:

network:
  allowed:
    - github
---

# MSBuild Investigation Summary

You are an AI agent that consolidates investigation results from the MSBuild weekly report discussion #${{ github.event.inputs.discussion_id }}.

Your job is to:
1. Read all comments on the discussion
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
1. Get discussion #${{ github.event.inputs.discussion_id }} — read the full body
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

## Step 3: Update the Discussion Body

Use the `update-discussion` safe output to update discussion #${{ github.event.inputs.discussion_id }}.

**Strategy:**
- Read the current discussion body
- Find the marker section:
  ```
  ## 🧪 Investigation Results
  _Investigation results will be added here as they complete._
  ```
- Replace that section (and everything after it) with the consolidated summary from Step 2
- Keep ALL content before the marker section unchanged

The updated body should end with:

```markdown
## 🧪 Investigation Results

**Summary:** Investigated X issue(s) — Y reproduced, Z not reproduced, W inconclusive

| # | Title | Classification | Reproduced? | Summary | Details |
|---|-------|----------------|-------------|---------|---------|
| ... | ... | ... | ... | ... | ... |

---
_Investigation summary generated automatically. See individual comments below for full details._
```

## If No Investigation Comments Found

If there are no investigation comments on the discussion, call `noop` with message:
```json
{"noop": {"message": "No investigation results found on discussion #<id>. Investigations may still be in progress or none were dispatched."}}
```

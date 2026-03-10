---
description: >
  Worker workflow that investigates a single upstream dotnet/msbuild issue.
  Reads the issue, analyzes root cause, attempts reproduction for bug reports,
  and posts findings as a comment on the weekly report discussion.

on:
  workflow_dispatch:
    inputs:
      upstream_issue:
        description: "Upstream issue number (e.g. 11234)"
        required: true
        type: string
      upstream_repo:
        description: "Upstream repo (owner/name)"
        required: false
        default: "dotnet/msbuild"
        type: string
      discussion_id:
        description: "Discussion number to post investigation results to"
        required: true
        type: string

permissions:
  contents: read
  issues: read
  pull-requests: read

concurrency:
  group: "msbuild-investigate-${{ github.event.inputs.upstream_issue }}"
  cancel-in-progress: false

tools:
  github:
    toolsets: [repos, issues, pull_requests]
  bash: ["cat", "grep", "head", "tail", "find", "ls", "wc", "jq", "date",
         "sort", "uniq", "dotnet", "mkdir", "cd", "echo", "cp", "sed", "awk"]
  edit:

safe-outputs:
  add-comment:
    target: "*"
    max: 1
  noop:

network:
  allowed:
    - github
    - dotnet
---

# MSBuild Issue Investigation — Worker Agent

You are an expert MSBuild issue investigator. Your job is to deeply analyze upstream issue #${{ github.event.inputs.upstream_issue }} from ${{ github.event.inputs.upstream_repo }}, attempt to reproduce it, investigate the root cause, and post your findings as a comment on discussion #${{ github.event.inputs.discussion_id }}.

## CRITICAL TOOL USAGE RULES

**For ALL data collection from GitHub, you MUST use the `github` MCP tool** (e.g., `get_issue`, `list_issue_comments`, `get_pull_request`, `get_repo`, `get_file_contents`, etc.).

**DO NOT** attempt to:
- Run `gh api` commands via bash — you don't have permission
- Run `curl` commands — blocked by security policy

**Use `bash` for**: `date`, `jq`, `cat`, `echo`, `grep`, `find`, `dotnet`, `mkdir`, and other allowed tools.

**Safe output constraints**: You have EXACTLY 1 `add-comment` available. Plan your output carefully — produce only one comment total.

---

## Step 1: Read Upstream Issue

Use the github tools to fetch from **${{ github.event.inputs.upstream_repo }}**:
1. Get issue #${{ github.event.inputs.upstream_issue }} (title, body, labels, state)
2. Get all comments on the issue
3. Note the issue author, creation date, labels, and any referenced versions or error messages

Record key information:
- **Title** and **body** (full text)
- **Labels** (especially `bug`, `regression`, `performance`, etc.)
- **Error messages** or stack traces mentioned
- **MSBuild version** or .NET SDK version if mentioned
- **Steps to reproduce** if provided
- **Referenced files or code** if any

---

## Step 2: Classification

Classify the issue:
- **Bug**: Unexpected behavior that appears to be a defect in MSBuild
- **Regression**: A previously working feature that broke (often mentions "used to work", "after update", etc.)
- **Performance**: Slowdown or resource issue

Assign a confidence score (0.0 – 1.0).

---

## Step 3: Root Cause Analysis

Based on the issue content, investigate the likely root cause:

1. **Search the MSBuild source code** in the `dotnet/msbuild` upstream repository using github tools (`get_file_contents`, `search_code`) to find relevant source files.
2. Look for:
   - The area of MSBuild affected (evaluation, task execution, SDK resolution, project loading, incremental build, etc.)
   - Recent changes or commits that might have introduced the issue
   - Related issues or PRs referenced in the issue
3. Form a hypothesis about what's going wrong and why.

---

## Step 4: Reproduction Attempt

Attempt to reproduce the issue:

1. Create a temp directory:
   ```bash
   mkdir -p /tmp/repro-${{ github.event.inputs.upstream_issue }}
   cd /tmp/repro-${{ github.event.inputs.upstream_issue }}
   ```

2. Based on the issue description, create a minimal reproduction:
   - For build issues: Create a minimal .csproj / .sln with the problematic configuration
   - For SDK resolution issues: Set up the appropriate global.json and project files
   - For task issues: Create a project that exercises the specific task
   - For evaluation issues: Create a project with the problematic property/item expressions

3. Use the `edit` tool (write) to create the project files. Example:
   ```
   Write /tmp/repro-${{ github.event.inputs.upstream_issue }}/TestProject/TestProject.csproj
   ```

4. Build with `dotnet build` and capture output:
   ```bash
   cd /tmp/repro-${{ github.event.inputs.upstream_issue }}/TestProject
   dotnet build 2>&1 | head -100
   ```

5. If applicable, run with `dotnet run` and capture output (timeout: 3 minutes).

6. Analyze results:
   - Compare actual output against expected behavior from the issue
   - If the error matches the issue description → **reproduced**
   - If the code builds/runs without the reported error → **repro-failed**
   - If you can't create a meaningful repro from the issue description → **repro-inconclusive**

**SAFETY:** Work ONLY in `/tmp/repro-${{ github.event.inputs.upstream_issue }}/`. Do NOT modify any files in the repository checkout.

---

## Step 5: Post Investigation Results

Post your findings as a single comment on discussion #${{ github.event.inputs.discussion_id }} using the `add-comment` safe output.

**Comment body format:**

```markdown
## 🔍 Investigation: Issue #<number> — <title>

**Upstream:** [dotnet/msbuild#<number>](https://github.com/dotnet/msbuild/issues/<number>)
**Classification:** <Bug/Regression/Performance> (confidence: <score>)
**Reproduction:** <✅ Reproduced / ❌ Not reproduced / ⚠️ Inconclusive>

### Summary
<2-3 sentence summary of the issue and findings>

### Root Cause Analysis
<Detailed analysis of what's likely going wrong, referencing specific source files if found>

### Reproduction Details
<What was attempted, what happened, relevant output snippets>

<If reproduced, include key error output in a code block>

### Suggested Next Steps
- <Actionable recommendation 1>
- <Actionable recommendation 2>
- <etc.>

---
_Automated investigation by MSBuild Weekly Report workflow_
```

## If Investigation Cannot Proceed

If the issue is deleted, closed, or cannot be accessed, call `noop` with a descriptive message:
```json
{"noop": {"message": "Cannot investigate issue #<number>: <reason>"}}
```

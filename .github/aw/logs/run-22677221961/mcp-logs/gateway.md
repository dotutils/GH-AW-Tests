<details>
<summary>MCP Gateway</summary>

- ✓ **startup** MCPG Gateway version: v0.1.4
- ✓ **startup** Starting MCPG with config: stdin, listen: 0.0.0.0:80, log-dir: /tmp/gh-aw/mcp-logs/
- ✓ **startup** Loaded 2 MCP server(s): [github safeoutputs]
- 🔍 rpc **safeoutputs**→`tools/list`
- 🔍 rpc **safeoutputs**←`resp` `{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"create_issue","description":"Create a new GitHub issue for tracking bugs, feature requests, or tasks. Use this for actionable work items that need assignment, labeling, and status tracking. For reports, announcements, or status updates that don't require task tracking, use create_discussion instead. CONSTRAINTS: Maximum 1 issue(s) can be created. Title will be prefixed with \"🏥 \". Labels [repo-health] will be automatically added. Issues will be created...`
- ✗ **backend**
  ```
  MCP backend connection failed, command=docker, args=[run --rm -i -e NO_COLOR=... -e TERM=... -e PYTHONUNBUFFERED=... -e GITHUB_TOOLSETS=repo... -e GITHUB_LOCKDOWN_MODE=... -e GITHUB_PERSONAL_ACCESS_TOKEN -e GITHUB_READ_ONLY=... ghcr.io/github/github-mcp-server:v0.30.3], error=calling "initialize": EOF
  ```
- ✗ **backend**
  ```
  MCP backend stderr output:
Error: GITHUB_PERSONAL_ACCESS_TOKEN not set
Usage:
  server stdio [flags]

Flags:
  -h, --help   help for stdio

Global Flags:
      --content-window-size int          Specify the content window size (default 5000)
      --dynamic-toolsets                 Enable dynamic toolsets
      --enable-command-logging           When enabled, the server will log all command requests and responses to the log file
      --export-translations              Save translations to a JSON file
      --features strings                 Comma-separated list of feature flags to enable
      --gh-host string                   Specify the GitHub hostname (for GitHub Enterprise etc.)
      --insiders                         Enable insiders features
      --lockdown-mode                    Enable lockdown mode
      --log-file string                  Path to log file
      --read-only                        Restrict the server to read-only operations
      --repo-access-cache-ttl duration   Override the repo access cache TTL (e.g. 1m, 0s to disable) (default 5m0s)
      --tools strings                    Comma-separated list of specific tools to enable
      --toolsets strings                 Comma-separated list of tool groups to enable (no spaces).
                                         Available: actions, code_security, dependabot, discussions, gists, git, issues,
                                         	     labels, notifications, orgs, projects, pull_requests, repos,
                                         	     secret_protection, security_advisories, stargazers, users
                                         Special toolset keywords:
                                           - all: Enables all available toolsets
                                           - default: Enables the default toolset configuration of:
                                         	     context, issues, pull_requests, repos, users
                                         Examples:
                                           - --toolsets=actions,gists,notifications
                                           - Default + additional: --toolsets=default,actions,gists
                                           - All tools: --toolsets=all

GITHUB_PERSONAL_ACCESS_TOKEN not set
  ```
- ✗ **backend**
  ```
  MCP backend connection/protocol error, command=docker
  ```
- ✓ **startup** Starting in ROUTED mode on 0.0.0.0:80
- ✓ **startup** Routes: /mcp/<server> for servers: [github safeoutputs]
- 🔍 rpc **safeoutputs**→`tools/call` `{"jsonrpc":"2.0","method":"tools/call","params":{"arguments":{"alternatives":"Manual data collection via GitHub API or web interface. User may need to run these queries in a different environment with proper GitHub MCP server access.","reason":"Cannot access GitHub MCP tool or gh CLI due to permission restrictions. All bash commands for gh CLI and file writes are blocked with \"Permission denied\". Need GitHub MCP server for querying repository data.","tool":"GitHub MCP server for data queries"},"name":"mis...`
- 🔍 rpc **safeoutputs**←`resp`
  
  ```json
  {"id":3,"result":{"content":[{"text":"{\"result\":\"success\"}","type":"text"}],"isError":false}}
  ```
- 🔍 rpc **safeoutputs**→`tools/call` `missing_tool`
  
  ```json
  {"params":{"arguments":{"alternatives":"Manual health check requires cross-repo PAT configured in github MCP server or gh CLI authentication with read:org, repo scopes for dotnet/machinelearning.","reason":"Cannot access GitHub API - no github MCP tool available and gh CLI not authenticated. Need read access to dotnet/machinelearning for health check metrics.","tool":"github MCP tool or authenticated gh CLI"},"name":"missing_tool"}}
  ```
- 🔍 rpc **safeoutputs**←`resp`
  
  ```json
  {"id":4,"result":{"content":[{"text":"{\"result\":\"success\"}","type":"text"}],"isError":false}}
  ```
- ✗ **auth** Authentication failed: invalid API key, remote=[::1]:47032, path=/close
- ✓ **shutdown** Shutting down gateway...

</details>

# Coucou MCP Architecture — Tools & Connectors for Chat

Coucou connects to Model Context Protocol (MCP) servers already configured on the user's machine, transforming the island chat into an assistant with actionable developer tools.

Following the philosophy of PR #400 (where local AI backends are automatically detected with zero credentials to paste), the MCP subsystem scans existing developer tool configurations passively without modifying files on disk or storing credentials in clear text.

---

## 1. Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                   Coucou Chat UI                       │
│      (Dynamic Island / Settings / ClaudeService)       │
└───────────────────────────┬────────────────────────────┘
                            │ OpenAI-compatible tool_calls
┌───────────────────────────▼────────────────────────────┐
│                  MCPChatCoordinator                   │
│   - Intercepts tool calls from LLM response            │
│   - Dispatches read-only vs mutating calls             │
└─────────────┬───────────────────────────┬──────────────┘
              │ Mutating (Approval)       │ Read-Only (Safe)
┌─────────────▼─────────────┐ ┌───────────▼──────────────┐
│    MCPApprovalManager     │ │     MCPToolRegistry      │
│  - Native Notch card      │ │  - Dispatches calls      │
│  - Sound & Allow/Deny     │ │  - Formats OpenAI schema │
└───────────────────────────┘ └───────────┬──────────────┘
                                          │
                      ┌───────────────────┴───────────────────┐
                      ▼                                       ▼
             MCPStdioClient                          MCPHTTPClient
         (Subprocesses over stdio)             (Remote streamable HTTP)
```

---

## 2. Zero-Config Discovery (`MCPScanner.swift`)

Coucou automatically reads existing configurations from standard developer tools on macOS and Linux:

| Tool | Monitored Locations | Configuration Key |
| :--- | :--- | :--- |
| **Claude Desktop** | `~/Library/Application Support/Claude/claude_desktop_config.json`<br>`~/.config/Claude/claude_desktop_config.json` | `mcpServers` |
| **Claude Code** | `~/.claude.json`<br>`<project>/.mcp.json` | `mcpServers`<br>`projects[*].mcpServers` |
| **Cursor** | `~/.cursor/mcp.json` | `mcpServers` |
| **VS Code** | `~/Library/Application Support/Code/User/mcp.json`<br>`~/.config/Code/User/mcp.json` | `servers`<br>`mcpServers` |
| **Windsurf** | `~/.codeium/windsurf/mcp_config.json` | `mcpServers` |
| **OpenCode** | `~/.config/opencode/opencode.json`<br>`~/.config/opencode/mcp.json` | `mcp`<br>`mcpServers` |

### Normalization Rules
1. **Variable expansion:** Normalizes syntax across formats:
   * `${VAR}` (Claude Code, shell)
   * `${env:VAR}` (VS Code, Cursor, Windsurf)
   * `{env:VAR}` (OpenCode)
   * `${userHome}` and `~/` expand to the actual user home directory.
2. **Secret Masking:** Keys and tokens (e.g. `sk-••••`, `ghp_••••`) and URL query parameters are masked when rendered in Settings.
3. **Deduplication:** Identical servers (e.g., PostgreSQL or GitHub configured in both Claude Desktop and Cursor) are merged into a single entry with composite source badges.

---

## 3. Communication Transports

### A. Subprocesses over Stdio (`MCPStdioClient.swift`)
* Launches servers as child processes (`Process`) with isolated standard pipes (`stdin`, `stdout`, `stderr`).
* Environment inherits user `PATH` entries including `/opt/homebrew/bin`, `/usr/local/bin`, `.nvm`, and `.local/bin`.
* Strict line-delimited JSON-RPC 2.0 framing.
* Watchdog timers ensure runaway processes are terminated on timeout (15s for handshake, 60s for tool calls).
* Child processes are cleanly terminated when the app exits or a server is disabled.

### B. Remote Streamable HTTP (`MCPHTTPClient.swift`)
* Communicates with remote servers via JSON-RPC 2.0 over HTTP POST (`application/json`).
* Injects headers (e.g. `Authorization: Bearer <token>`) configured by the user or imported from external configs.
* Fails closed with descriptive messages on HTTP 401, 403, 404, or 500 status codes.

---

## 4. Human-in-the-Loop Governance in the Notch

Coucou strictly regulates tool execution to prevent unintended side effects:

### Safety Classification
* **Read-Only / Safe Tools:**
  * Tools declaring `readOnlyHint: true`.
  * Tools starting with safe read prefixes (`get_`, `list_`, `read_`, `search_`, `fetch_`, `check_`, `describe_`, `view_`, `show_`, `find_`) that do not contain mutating keywords.
  * *Action:* Execute immediately and show an active working state.
* **Mutating / Side-Effect Tools:**
  * Any tool with keywords like `write`, `delete`, `send`, `post`, `update`, `create`, `execute`, `run`, `edit`.
  * *Action:* Triggers the native **Approval** card in the Notch.

### The Notch Approval Card
When a mutating tool is called:
1. `MCPApprovalManager` captures execution state using an async continuation.
2. The Notch displays:
   * Server name and tool (e.g. `PostgreSQL → execute_query(...)`).
   * Tool arguments summarized in a code block.
   * `Allow (Y)` / `Always` / `Deny (N)` action buttons.
3. If the user clicks **Allow**, execution continues and results are returned to the LLM.
4. If the user clicks **Deny** or closes the Notch, execution is rejected cleanly without side effects.

---

## 5. Chat Completion Integration

When any MCP server is enabled in **Settings → Chat → MCP Tools & Connectors**:
1. `MCPToolRegistry` formats all active tools as standard OpenAI function definitions (`mcp__<serverID>__<toolName>`).
2. Tools are injected into the `/chat/completions` payload in `ClaudeService.swift`.
3. When the LLM responds with `tool_calls`, `MCPChatCoordinator` executes the tools (with Notch approval if mutating) and appends `tool` messages to the conversation.
4. Coucou triggers a follow-up completion with the tool results so the LLM responds with a complete, contextual answer.

---

## 6. Testing

All MCP modules are validated using standalone Swift test harnesses:
* `scripts/test-mcp-scanner.sh`: Tests config parsing, normalization, secret masking, and deduplication.
* `scripts/test-mcp-client.sh`: Tests JSON-RPC 2.0 protocol encoding, response parsing, and AnyCodable serde.
* `scripts/test-mcp-coordinator.sh`: Tests safety classification, tool routing, and approval handling.
* `scripts/test-mcp-http.sh`: Tests remote HTTP client payload framing and response parsing.

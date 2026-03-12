# MCP Server Setup

## Configuration

Add `.mcp.json` to your project root:

```json
{
  "mcpServers": {
    "skltn": {
      "command": "skltn",
      "args": ["mcp"]
    }
  }
}
```

## Available tools

### get_skeleton

Get declaration skeleton of a project or specific file.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `project_root` | string | Yes | Absolute path to the project root directory |
| `path` | string | No | Relative file path to get skeleton for a specific file |
| `kinds` | string[] | No | Filter by declaration kind: class, struct, enum, protocol, actor, extension |

### query_symbols

Search for symbols (types, methods, properties) by name.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `project_root` | string | Yes | Absolute path to the project root directory |
| `query` | string | Yes | Search query string to match against symbol names |
| `limit` | integer | No | Maximum number of results (default: 20) |

Returns each hit on a new line: `header (file:startLine-endLine)`.
Returns "No results found for: ..." when nothing matches.

## When to use MCP vs CLI

- **MCP tools**: Preferred when the MCP server is already connected. No Bash call needed, results come directly.
- **CLI via Bash**: Use when MCP is not configured, or when you need to pipe output or combine with other shell commands.

## JSON-RPC Daemon (advanced)

For long-running sessions, use the daemon mode which maintains project indices in memory:

```bash
skltn daemon
```

Methods: `index.open`, `index.status`, `index.get_skeleton`, `index.update`, `index.query`, `index.diagnostics`

Protocol: JSON-RPC 2.0 over stdin/stdout.

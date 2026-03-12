import Foundation

extension SkeletonIndexCLIMain {
    static func installSkill() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let targets: [(name: String, dir: String, skillContent: String)] = [
            ("Claude Code", "\(home)/.claude/skills/skeleton", claudeCodeSkillContent),
            ("Codex", "\(home)/.codex/skills/skeleton", codexSkillContent),
        ]

        var installed: [String] = []

        for target in targets {
            let parentDir = (target.dir as NSString).deletingLastPathComponent
            let toolRoot = (parentDir as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: toolRoot) else { continue }

            let refsDir = "\(target.dir)/references"
            try fm.createDirectory(atPath: refsDir, withIntermediateDirectories: true)

            let skillPath = "\(target.dir)/SKILL.md"
            try target.skillContent.write(toFile: skillPath, atomically: true, encoding: .utf8)

            let outputFormatPath = "\(refsDir)/output-format.md"
            try outputFormatContent.write(toFile: outputFormatPath, atomically: true, encoding: .utf8)

            let mcpSetupPath = "\(refsDir)/mcp-setup.md"
            try mcpSetupContent.write(toFile: mcpSetupPath, atomically: true, encoding: .utf8)

            installed.append("\(target.name): \(target.dir)")
        }

        if installed.isEmpty {
            print("No supported tool found. Expected ~/.claude/ or ~/.codex/ to exist.")
        } else {
            for entry in installed {
                print("Installed: \(entry)")
            }
        }
    }
}

// MARK: - Shared SKILL.md body

private let sharedSkillBody = """

# Skeleton

Get a structural overview of any codebase — declarations without implementations.

## Instructions

### Step 1: Determine the project root

- If `$ARGUMENTS` contains a path, use it
- Otherwise use the current working directory

### Step 2: Run the skeleton extraction

```bash
skltn get_skeleton --project-root /absolute/path/to/project
```

To filter a single file:

```bash
skltn get_skeleton --project-root /absolute/path/to/project --path Sources/MyFile.swift
```

### Step 3: Present the output

- Show the skeleton as a structural overview
- If the output exceeds 2000 lines, summarize by showing only type headers (lines not starting with spaces) and note the full line count

### Step 4: Search symbols (optional)

```bash
skltn query --project-root /absolute/path/to/project --q "MyType" --limit 10
```

Returns matching declarations with file path and line numbers (default limit: 20).

## Reading the output

Top-level lines (no indent) are type declarations — use these for summaries. Indented lines show properties and methods with their signatures and line ranges.

For the full output format specification, consult `references/output-format.md`.

## Supported languages

Swift, Kotlin, TypeScript, Go, Zig, Rust, C++, Python, Java

## MCP integration

If the `skltn` MCP server is configured (via `.mcp.json`), you can also use `get_skeleton` and `query_symbols` tools directly without Bash. See `references/mcp-setup.md` for setup and tool parameters.

## Common issues

### skltn command not found

Install via Mint:

```bash
mint install 1amageek/swift-skeleton
```

Or build from source:

```bash
git clone https://github.com/1amageek/swift-skeleton.git
cd swift-skeleton && swift build -c release
```

### parse_error or (!) in output

These are expected for files with syntax errors. The skeleton continues processing — partial results are still usable. `# parse_error` means a file failed entirely. `(!)` means a block was partially parsed (e.g., missing closing brace).
"""

// MARK: - Claude Code

private let claudeCodeSkillContent = """
---
name: skeleton
description: Understand the overall structure and architecture of a codebase. Extracts all type declarations, method signatures, properties, and inheritance relationships into a compact skeleton. Use when user asks about project architecture, says "show me the structure", wants to explore an unfamiliar codebase, or is planning multi-module changes. Also use before launching an Explore agent to give it a structural map.
allowed-tools: Bash, Read, Task
license: MIT
compatibility: Requires skltn CLI installed via `mint install 1amageek/swift-skeleton` or built from source. macOS 13+, Swift 6.2+.
metadata:
  author: 1amageek
  mcp-server: skltn
---
\(sharedSkillBody)
"""

// MARK: - Codex

private let codexSkillContent = """
---
name: skeleton
description: Understand the overall structure and architecture of a codebase. Extracts all type declarations, method signatures, properties, and inheritance relationships into a compact skeleton. Use when user asks about project architecture, says "show me the structure", wants to explore an unfamiliar codebase, or is planning multi-module changes. Also use before spawning an explorer agent to give it a structural map.
license: MIT
compatibility: Requires skltn CLI installed via `mint install 1amageek/swift-skeleton` or built from source. macOS 13+, Swift 6.2+.
metadata:
  author: 1amageek
  mcp-server: skltn
---
\(sharedSkillBody)
"""

// MARK: - references/output-format.md

private let outputFormatContent = """
# Output Format Specification

## Structure

```
<kind> <Name>[: Conformances] [<file>:<start>-<end>]
  props: <name>:<Type>, ...
  methods:
    <name>(<ParamTypes>) [-> ReturnType] [<start>-<end>]
```

## Line types

### Type header (no indent)

```
struct SkeletonIndexCore: Sendable [Sources/SkeletonIndexCore/SkeletonIndexCore.swift:3-246]
```

- `<kind>`: class, struct, enum, protocol, actor, extension
- `<Name>`: Type name
- `: Conformances`: Inheritance and protocol conformance (omitted if none)
- `[file:start-end]`: Source file path and line range

### Properties

```
  props: parsers:[any SkeletonParser], formatter:SkeletonFormatter
```

- Comma-separated list of `name:Type` pairs
- Only properties with explicit type annotations are shown
- Omitted entirely if none

### Methods

```
  methods:
    init([any SkeletonParser], SkeletonFormatter) [7-10]
    build(String) -> ProjectIndex [16-45]
    query(ProjectIndex, String, Int) -> [QueryHit] [97-139]
```

- Parameter types only (no parameter names)
- Return type after `->` (omitted if Void or unknown)
- `[start-end]`: Line range within the file

## Special markers

| Marker | Meaning |
|--------|---------|
| `# parse_error <file>` | File failed to parse entirely |
| `(!)` after type header | Block partially parsed (e.g., missing closing brace) |
| `?` in line range | Line number unknown (e.g., `[?-?]`, `[3-?]`) |

## Ordering

- Files: sorted by path (ascending)
- Blocks within a file: source order (order of appearance)
- Properties and methods within a block: source order

## Filtering by kind

Use `--kinds` (MCP) or the `kinds` parameter to filter output to specific declaration types:

Accepted values: `class`, `struct`, `enum`, `protocol`, `actor`, `extension`

Omit to include all kinds.
"""

// MARK: - references/mcp-setup.md

private let mcpSetupContent = """
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
"""

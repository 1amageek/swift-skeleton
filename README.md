# swift-skeleton

Give LLMs the full picture of your codebase — without the full source.

## Why Skeleton?

An LLM coding agent explores a codebase the same way a developer joins a new project. It doesn't need to read every line — it needs to see the shape first: what types exist, what methods they expose, how they relate to each other, and where to find them.

That shape is the **skeleton** — declarations without implementations. Like looking at a building's blueprint instead of walking every room.

swift-skeleton extracts this skeleton automatically: type declarations, properties, method signatures, inheritance, file paths, and line numbers. The result fits in a context window where full source code never would. The LLM reads the skeleton, understands the architecture, and then dives into only the files it actually needs.

```
struct SkeletonIndexCore: Sendable [Sources/SkeletonIndexCore/SkeletonIndexCore.swift:3-246]
  props: parsers:[any SkeletonParser], formatter:SkeletonFormatter
  methods:
    init([any SkeletonParser], SkeletonFormatter) [7-10]
    build(String) -> ProjectIndex [16-45]
    getSkeleton(ProjectIndex, String?) -> SkeletonTextResult [57-62]
    query(ProjectIndex, String, Int) -> [QueryHit] [97-139]
```

From this alone, an LLM can instantly understand:

- `SkeletonIndexCore` is a `Sendable` struct
- It takes parsers via DI and builds an index with `build`
- Results are retrieved via `getSkeleton` and `query`
- The implementation lives in `SkeletonIndexCore.swift` lines 3–246

Built on [Tree-sitter](https://tree-sitter.github.io/tree-sitter/) for fast, accurate parsing.

## Supported Languages

Swift, Kotlin, TypeScript, Go, Zig, Rust, C++, Python, Java

Each language parser is selectable via [Package Traits (SE-0450)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md). Build with `--disable-default-traits` for Swift-only.

## Installation

### Mint (recommended)

```bash
mint install 1amageek/swift-skeleton
```

### Build from source

```bash
git clone https://github.com/1amageek/swift-skeleton.git
cd swift-skeleton
swift build -c release
```

## Agent Skill

swift-skeleton provides a **Skill** for LLM coding agents (Claude Code, Codex). The skill gives the agent a structural overview of any project before it starts exploring files. Each tool gets a tailored SKILL.md — Claude Code's version references Explore agents, Codex's version uses generic exploration terminology.

### Setup

```bash
mint install 1amageek/swift-skeleton
skltn install-skill
```

This installs the skill to `~/.claude/skills/skeleton/` and `~/.codex/skills/skeleton/` (whichever tools are present).

### Usage

```
# Explicit invocation
/skeleton /path/to/project

# The agent can also invoke it automatically before code exploration
```

## MCP Server

Runs as an [MCP](https://modelcontextprotocol.io) server so Claude Code can query codebase structure directly.

### Setup

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

### Tools

#### `get_skeleton`

Get declaration skeleton of a project or specific file.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `project_root` | `string` | Yes | Absolute path to the project root |
| `path` | `string` | No | Relative file path to filter by |
| `kinds` | `string[]` | No | Filter by declaration kind |

`kinds` accepts: `class`, `struct`, `enum`, `protocol`, `actor`, `extension`. Omit to include all.

#### `query_symbols`

Search symbols by name.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `project_root` | `string` | Yes | Absolute path to the project root |
| `query` | `string` | Yes | Search string |
| `limit` | `integer` | No | Max results (default: 20) |

## CLI

```bash
# Full project skeleton
skltn get_skeleton --project-root /path/to/project

# Single file skeleton
skltn get_skeleton --project-root /path/to/project --path Sources/MyFile.swift

# Symbol search
skltn query --project-root /path/to/project --q "MyClass" --limit 10

# Install agent skill (Claude Code / Codex)
skltn install-skill

# JSON-RPC daemon (stdin/stdout)
skltn daemon

# MCP server (stdin/stdout)
skltn mcp
```

## Architecture

```
SkeletonIndexCore          Language-agnostic core (protocols, models, formatter, index)
SkeletonSwiftParser        Swift parser (Tree-sitter)
SkeletonKotlinParser       Kotlin parser (Tree-sitter)
SkeletonTypeScriptParser   TypeScript parser (Tree-sitter)
SkeletonGoParser           Go parser (Tree-sitter)
SkeletonZigParser          Zig parser (Tree-sitter)
SkeletonRustParser         Rust parser (Tree-sitter)
SkeletonCppParser          C++ parser (Tree-sitter)
SkeletonPythonParser       Python parser (indent-based AST)
SkeletonJavaParser         Java parser (Tree-sitter)
SkeletonIndexClient        EmbeddedService / SidecarService
skltn                      CLI / Daemon / MCP server (unified executable)
```

The core has zero dependency on Tree-sitter. Parsers are injected via the `SkeletonParser` protocol.

### Adding a New Language

Implement `SkeletonParser` and inject it:

```swift
public protocol SkeletonParser: Sendable {
    var languageName: String { get }
    var supportedExtensions: Set<String> { get }
    func parse(path: String, source: String) -> ParsedFile
}

let core = SkeletonIndexCore(parsers: [
    SwiftSkeletonParser(),
    YourLanguageParser(),
])
```

## Library Usage

### Embedded (in-process)

```swift
import SkeletonIndexCore
import SkeletonSwiftParser

let core = SkeletonIndexCore(parsers: [SwiftSkeletonParser()])
let index = try core.build(projectRoot: "/path/to/project")
let skeleton = core.getSkeleton(index: index)
print(skeleton.text)

let hits = core.query(index: index, q: "MyType", limit: 10)
```

### Sidecar (out-of-process)

```swift
import SkeletonIndexClient

let service = SidecarService(executablePath: "skltn")
let result = try await service.open(projectRoot: "/path/to/project", languages: ["swift"])
let skeleton = try await service.getSkeleton(projectID: result.projectID)
```

### JSON-RPC Daemon

```bash
skltn daemon
```

Methods: `index.open`, `index.status`, `index.get_skeleton`, `index.update`, `index.query`, `index.diagnostics`

## Requirements

- Swift 6.2+
- macOS 13+

## License

MIT

# swift-skeleton

Swift source code structural indexer. Extracts type declarations, properties, method signatures, inheritance, and source locations from a codebase — without reading full source code.

Built on [Tree-sitter](https://tree-sitter.github.io/tree-sitter/) for fast, accurate parsing.

## Output Example

```
struct SkeletonIndexCore: Sendable [Sources/SkeletonIndexCore/SkeletonIndexCore.swift:3-246]
  props: parsers:[any SkeletonParser], formatter:SkeletonFormatter
  methods:
    init([any SkeletonParser], SkeletonFormatter) [7-10]
    build(String) -> ProjectIndex [16-45]
    getSkeleton(ProjectIndex, String?) -> SkeletonTextResult [57-62]
    query(ProjectIndex, String, Int) -> [QueryHit] [97-139]
```

## Architecture

```
SkeletonIndexCore          Language-agnostic core (protocols, models, formatter, index)
SkeletonSwiftParser        Swift parser (Tree-sitter dependency isolated here)
SkeletonIndexClient        EmbeddedService / SidecarService
skeletonindex              CLI
skeletonindexd             JSON-RPC daemon
skeletonindex-mcp          MCP server for Claude Code
```

The core has zero dependency on Tree-sitter. Parsers are injected via `SkeletonParser` protocol.

### Adding a New Language

Implement `SkeletonParser` and inject it:

```swift
public protocol SkeletonParser: Sendable {
    var languageName: String { get }
    var supportedExtensions: Set<String> { get }
    func parse(path: String, source: String) -> ParsedFile
}

// Usage
let core = SkeletonIndexCore(parsers: [
    SwiftSkeletonParser(),
    YourLanguageParser(),
])
```

## Installation

```bash
git clone https://github.com/1amageek/swift-skeleton.git
cd swift-skeleton
swift build -c release
```

Requires Swift 6.2+ and macOS 13+.

## CLI

```bash
# Get full project skeleton
skeletonindex get_skeleton --project-root /path/to/project

# Get skeleton for a specific file
skeletonindex get_skeleton --project-root /path/to/project --path Sources/MyFile.swift

# Search symbols
skeletonindex query --project-root /path/to/project --q "MyClass" --limit 10
```

## MCP Server (Claude Code)

`skeletonindex-mcp` exposes the indexer as an [MCP](https://modelcontextprotocol.io) server, allowing Claude Code to inspect codebase structure.

### Setup

Build the release binary and add `.mcp.json` to your project root:

```bash
swift build -c release
```

```json
{
  "mcpServers": {
    "skeletonindex": {
      "command": "/path/to/swift-skeleton/.build/release/skeletonindex-mcp",
      "args": []
    }
  }
}
```

### Tools

#### `get_skeleton`

Get declaration skeleton of a project or specific file.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `project_root` | `string` | Yes | Absolute path to project root |
| `path` | `string` | No | Relative file path to filter by |
| `kinds` | `string[]` | No | Filter by declaration kind |

`kinds` accepts: `class`, `struct`, `enum`, `protocol`, `actor`, `extension`. Omit to include all.

#### `query_symbols`

Search symbols by name.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `project_root` | `string` | Yes | Absolute path to project root |
| `query` | `string` | Yes | Search string |
| `limit` | `integer` | No | Max results (default: 20) |

## JSON-RPC Daemon

`skeletonindexd` provides a persistent daemon over stdin/stdout with JSON-RPC 2.0.

```bash
skeletonindexd
```

Methods: `index.open`, `index.status`, `index.get_skeleton`, `index.update`, `index.query`, `index.diagnostics`

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

let service = SidecarService(executablePath: "skeletonindexd")
let result = try await service.open(projectRoot: "/path/to/project", languages: ["swift"])
let skeleton = try await service.getSkeleton(projectID: result.projectID)
```

## License

MIT

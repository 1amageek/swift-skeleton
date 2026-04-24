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

swift-skeleton ships with an [Agent Skill](https://docs.anthropic.com/en/docs/claude-code/skills) in [`SKILLS/skeleton/`](SKILLS/skeleton/). The skill teaches LLM coding agents (Claude Code, Codex) how to use skeleton extraction — giving the agent a structural overview of any project before it starts exploring files.

```
SKILLS/skeleton/
├── SKILL.md                  # Core instructions
└── references/
    ├── cli.md                # CLI commands and filters
    └── output-format.md      # Output format specification
```

### Install via CLI

```bash
skltn install-skill
```

This copies the skill to `~/.claude/skills/skeleton/` and `~/.codex/skills/skeleton/` (whichever tools are present).

### Manual install

Copy the `SKILLS/skeleton/` folder to your tool's skills directory:

```bash
cp -r SKILLS/skeleton ~/.claude/skills/skeleton
```

### Usage

```
# Explicit invocation
/skeleton /path/to/project

# The agent can also invoke it automatically before code exploration
```

## CLI

```bash
# Full project skeleton
skltn skeleton /path/to/project

# Single file skeleton
skltn skeleton /path/to/project --path Sources/MyFile.swift

# Compact project map
skltn skeleton /path/to/project --headers-only

# Filter by language or declaration kind
skltn skeleton /path/to/project --language swift
skltn skeleton /path/to/project --kinds struct,actor

# Symbol search
skltn query /path/to/project --q "MyClass" --limit 10

# Project status and diagnostics
skltn status /path/to/project
skltn diagnostics /path/to/project
skltn files /path/to/project
skltn languages

# Install agent skill (Claude Code / Codex)
skltn install-skill

# JSON-RPC daemon (stdin/stdout)
skltn daemon
```

`get_skeleton` and `build` are aliases for `skeleton`. `search` is an alias for `query`, and `diag` is an alias for `diagnostics`.

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
skltn                      CLI / JSON-RPC daemon
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

let service = SidecarService()
let result = try await service.open(projectRoot: "/path/to/project", languages: ["swift"])
let skeleton = try await service.getSkeleton(projectID: result.projectID, path: nil)
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

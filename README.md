# swift-skeleton

Give LLMs the full picture of your codebase — without the full source.

## Why Skeleton?

An LLM coding agent explores a codebase the same way a developer joins a new project. It doesn't need to read every line — it needs to see the shape first: what types exist, what methods they expose, how they relate to each other, and where to find them.

That shape is the **skeleton** — declarations without implementations. Like looking at a building's blueprint instead of walking every room.

swift-skeleton extracts this skeleton automatically: type declarations, properties, method signatures, inheritance, file paths, and line numbers. The result fits in a context window where full source code never would. The LLM reads the skeleton, understands the architecture, and then dives into only the files it actually needs.

Parser-range-derived implementation fingerprints and project-context heuristics also add short review signals without retaining method bodies:

```
struct SkeletonIndexCore: Sendable [Sources/SkeletonIndexCore/SkeletonIndexCore.swift:3-246]
  props: parsers:[any SkeletonParser], formatter:SkeletonFormatter
  methods:
    init([any SkeletonParser], SkeletonFormatter) [7-10]
    build(String) -> ProjectIndex [16-45]
    getSkeleton(ProjectIndex, String?) -> SkeletonTextResult [57-62]
    query(ProjectIndex, String, Int) -> [QueryHit] [97-139]

struct PlaceholderStore: Store [Sources/PlaceholderStore.swift:1-12] [impl:body,wire]
  methods:
    load(String) -> Item [4-6] [impl!:trap]
    contains(String) -> Bool [8-10] [impl?:const]
```

From this alone, an LLM can instantly understand:

- `SkeletonIndexCore` is a `Sendable` struct
- It takes parsers via DI and builds an index with `build`
- Results are retrieved via `getSkeleton` and `query`
- The implementation lives in `SkeletonIndexCore.swift` lines 3–246
- `PlaceholderStore` has high-confidence and suspicious implementation patterns worth reopening

Built on [Tree-sitter](https://tree-sitter.github.io/tree-sitter/) for fast, accurate parsing.

### Implementation markers

| Marker | Meaning |
|---|---|
| `[impl:body,wire]` | Declaration-level summary, preserved by `--headers-only` |
| `[impl!:trap]` | Configured high-confidence pattern such as an explicit not-implemented terminal |
| `[impl?:const]` | AST-pattern or project-context heuristic requiring source review |

Reasons are `trap`, `empty`, `const`, `noop`, `flow`, `error`, `wire`, and `dead`. Protocol/interface requirements are not treated as empty implementations, and normal output suppresses findings classified as non-production.

### Trust boundary

Implementation markers prioritize source review; they are not semantic verification. Built-in parsers reduce the live AST to call, return, write, catch, branch, and trap evidence, then project-context heuristics add wiring and reachability signals. Method body text is not retained. Compatibility parsers that do not provide AST evidence use the range-based fallback analyzer. Neither path proves name resolution, types, semantic correctness, dependency wiring, or reachability.

- Open every marked method range and use the original source as the authority.
- Confirm invocation shape for `trap`, interpolation dependencies for `const`, handler scope for `error`, and construction or call paths for `wire` and `dead`.
- Treat intentional default implementations and domain-correct no-ops as valid after source review.
- Treat no marker as “no configured pattern matched,” not as proof that the implementation is complete.
- Check `diagnostics` before trusting coverage because partial results can accompany parser errors.

Project-context analysis inspects the indexed source set. For large monorepos, start from a package or module root and widen the scan only when cross-package context is required.

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
skltn get /path/to/project

# Single file skeleton
skltn get /path/to/project --path Sources/MyFile.swift

# Strict directory scope (only Sources/Feature)
skltn get /path/to/project/Sources/Feature

# Focus one SwiftPM target and include visible API from imported local dependencies
skltn get /path/to/project/Sources --target Feature

# Apply an effective-access filter to every rendered declaration
skltn get /path/to/project/Sources --target Feature --access public

# Compact project map
skltn get /path/to/project --headers-only

# Filter by language or declaration kind
skltn get /path/to/project --language swift
skltn get /path/to/project --kinds struct,actor

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

The command may be omitted (`skltn /path/to/project`). `skeleton`, `get_skeleton`, and `build` remain compatibility aliases for `get`. `search` is an alias for `query`, and `diag` is an alias for `diagnostics`.

`--target` is intentionally different from a path. A positional directory remains a strict scan of that directory. SwiftPM target mode resolves `Package.swift`, renders the focus target in full, and then renders only source-visible declarations from direct local dependencies that the target actually imports. It does not traverse external package sources or add dependency-role/access labels. `--access` accepts `public`, `package`, `internal`, `fileprivate`, `private`, or `all` and uses effective Swift access rather than modifier text.

Target output is compact and module-oriented:

```text
module Feature
  imports: FeatureTwo
struct FeatureAPI [Sources/Feature/FeatureAPI.swift:3-12]

module FeatureTwo
struct PublicDependency [Sources/FeatureTwo/PublicDependency.swift:1-8]
```

## Architecture

```
SkeletonIndexCore          Language-agnostic core (protocols, models, formatter, index)
SkeletonTreeSitterSupport  Shared AST implementation-evidence extraction
SkeletonSwiftParser        Swift parser (Tree-sitter)
SkeletonSwiftPMProjectSupport SwiftPM target graph adapter
SkeletonKotlinParser       Kotlin parser (Tree-sitter)
SkeletonTypeScriptParser   TypeScript parser (Tree-sitter)
SkeletonGoParser           Go parser (Tree-sitter)
SkeletonZigParser          Zig parser (Tree-sitter)
SkeletonRustParser         Rust parser (Tree-sitter)
SkeletonCppParser          C++ parser (Tree-sitter)
SkeletonPythonParser       Python parser (Tree-sitter)
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
import SkeletonSwiftPMProjectSupport
import SkeletonSwiftParser

let core = SkeletonIndexCore(
    parsers: [SwiftSkeletonParser()],
    projectStructureResolvers: [SwiftPMProjectStructureResolver()]
)
let index = try core.build(
    projectRoot: "/path/to/project/Sources",
    languages: ["swift"],
    targetName: "Feature"
)
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

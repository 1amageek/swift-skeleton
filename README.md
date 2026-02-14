# swift-skeleton

A Swift declaration indexer optimized for **fast codebase scouting**.

`swift-skeleton` builds a compact skeleton view of Swift source files, focusing on top-level declarations and source ranges so you can quickly locate relevant code and jump to original files.

## Features (v1)

- Parses Swift files using Tree-sitter Swift grammar.
- Extracts declaration skeletons for:
  - `class`
  - `struct`
  - `enum`
  - `protocol`
  - `extension`
- Includes source location metadata (`file:start-end`).
- Omits function bodies and keeps output compact.
- Continues on parse failures and reports partial output with diagnostics.
- Supports both:
  - Embedded usage (library API)
  - Sidecar usage (daemon + JSON-RPC 2.0)

## Package Layout

### Products

- `SkeletonIndexCore` (library)
- `SkeletonIndexClient` (library)
- `skeletonindexd` (executable)
- `skeletonindex` (executable)

### Targets

- `SkeletonIndexCore`
- `SkeletonIndexClient`
- `skeletonindexd`
- `skeletonindex`
- `SkeletonIndexCoreTests`

## Installation / Build

### Requirements

- Swift 6.2+

### Build

```bash
swift build
```

### Test

```bash
swift test --parallel
```

## CLI Usage

The CLI executable is `skeletonindex`.

```bash
skeletonindex build --project-root <path> [--path <file>]
skeletonindex get_skeleton --project-root <path> [--path <file>]
skeletonindex query --project-root <path> --q <string> [--limit <n>]
```

Examples:

```bash
# Build/get full skeleton from a project
skeletonindex get_skeleton --project-root ./MyProject

# Get skeleton only for one file
skeletonindex get_skeleton --project-root ./MyProject --path Sources/App/App.swift

# Query declarations
skeletonindex query --project-root ./MyProject --q UserService --limit 20
```

## Output Contract (v1)

### Ordering

- Files are sorted by path ascending.
- Blocks are output in source order.
- Properties and methods are output in source order.

### Headers

- Type declarations:
  - `<kw> <TypeName>: <Inheritance...> [<file>:<start>-<end>]`
- Extensions:
  - `extension <TypeName>: <Protocols...> [<file>:<start>-<end>]`
- If inheritance/conformance is empty, `: ...` is omitted.

### Properties

- Format:
  - `props: <name>:<TypeRef>, ...`
- Properties without explicit type annotations are omitted.

### Methods

- Function format:
  - `<name>(<ParamTypeRef...>) -> <ReturnTypeRef> [<start>-<end>]`
- Initializer format:
  - `init(<ParamTypeRef...>) [<start>-<end>]`
- Unknown parameter type is rendered as `?`.
- If return type is unknown/absent, `-> ...` is omitted.

### Error Markers

- File-level parse failure:
  - `# parse_error <filePath>`
- Block contains parse error node:
  - header suffix `(!)`
- Unknown ranges use `?` (e.g. `start-?`, `?-?`).

## Architecture

### Core

Pure indexing functionality:

- parse
- build
- update
- query
- skeleton text rendering
- diagnostics generation

### Client

Defines `SkeletonIndexService` and provides:

- `EmbeddedService`
- `SidecarService`

### Daemon

`skeletonindexd` provides a JSON-RPC 2.0 sidecar interface.

Supported methods (v1 minimum):

- `index.open`
- `index.status`
- `index.get_skeleton`
- `index.update`
- `index.query`
- `index.diagnostics`

## Current Scope / Non-Scope

### In Scope (v1)

- Swift declaration skeleton extraction
- Fast, partial output even when parse is imperfect
- Source ranges for jump-to-source workflows

### Not in Scope (v1)

- Name resolution
- Type inference
- Function body extraction
- Call graph extraction
- LSP integration
- Comment preservation / formatting

## CI

GitHub Actions runs test validation on push and pull requests.

Workflow file:

- `.github/workflows/ci.yml`

## License

Please add your preferred license file if this project will be distributed publicly.

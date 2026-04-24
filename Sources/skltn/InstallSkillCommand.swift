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

            let cliPath = "\(refsDir)/cli.md"
            try cliContent.write(toFile: cliPath, atomically: true, encoding: .utf8)

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
skltn skeleton /absolute/path/to/project
```

To filter a single file:

```bash
skltn skeleton /absolute/path/to/project --path Sources/MyFile.swift
```

To reduce large output before presenting it:

```bash
skltn skeleton /absolute/path/to/project --headers-only
```

### Step 3: Present the output

- Show the skeleton as a structural overview
- If the output exceeds 2000 lines, summarize by showing only type headers (lines not starting with spaces) and note the full line count

### Step 4: Search symbols (optional)

```bash
skltn query /absolute/path/to/project --q "MyType" --limit 10
```

Returns matching declarations with file path and line numbers (default limit: 20).

## Useful CLI commands

```bash
skltn status /absolute/path/to/project
skltn diagnostics /absolute/path/to/project
skltn files /absolute/path/to/project
skltn languages
```

Use `--language swift` to restrict scanning to a language. Use `--kind struct` or comma-separated `--kinds struct,actor` to filter declaration kinds.

## Reading the output

Top-level lines (no indent) are type declarations — use these for summaries. Indented lines show properties and methods with their signatures and line ranges.

For the full output format specification, consult `references/output-format.md`.

## Supported languages

Swift, Kotlin, TypeScript, Go, Zig, Rust, C++, Python, Java

## CLI reference

For command details and filters, consult `references/cli.md`.

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
  interface: cli
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
  interface: cli
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

Use `--kind` or `--kinds` to filter output to specific declaration types:

Accepted values: `class`, `struct`, `enum`, `protocol`, `actor`, `extension`

Omit to include all kinds.
"""

// MARK: - references/cli.md

private let cliContent = """
# CLI Reference

## Commands

```bash
skltn skeleton [project-root] [--path <file>] [--language <name>] [--kind <kind>] [--headers-only]
skltn query [project-root] --q <string> [--limit <n>] [--language <name>]
skltn status [project-root] [--language <name>]
skltn diagnostics [project-root] [--language <name>]
skltn files [project-root] [--language <name>]
skltn languages
```

If `project-root` is omitted, `skltn` uses the current working directory.

## Aliases

| Alias | Command |
|-------|---------|
| `get_skeleton` | `skeleton` |
| `build` | `skeleton` |
| `search` | `query` |
| `diag` | `diagnostics` |

## Filters

`--language` restricts scanning to one or more languages. Repeat it or pass comma-separated values:

```bash
skltn skeleton . --language swift
skltn skeleton . --languages swift,python
```

`--kind` and `--kinds` filter declarations after parsing:

```bash
skltn skeleton . --kind struct
skltn skeleton . --kinds struct,actor,extension
```

Accepted kinds: `class`, `struct`, `enum`, `protocol`, `actor`, `extension`.

## Output Size

Use `--headers-only` for a compact map when a repository is large. It keeps top-level declaration headers and parse markers, but omits properties and methods.
"""

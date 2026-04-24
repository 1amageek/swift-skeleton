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

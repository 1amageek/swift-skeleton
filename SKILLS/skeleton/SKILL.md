---
name: skeleton
description: Extract and navigate a compact structural map of a codebase with the skltn CLI, including declaration headers, typed properties, method signatures, inheritance, source paths, and line ranges. Use when exploring project architecture, locating symbols, reviewing an unfamiliar repository, or planning changes across files or modules.
---

# Skeleton

Use `skltn` to inspect declarations without loading implementation bodies.

## Workflow

### 1. Resolve the project root

Use the path supplied by the user. If no path is supplied, use the current working directory.

### 2. Build a structural map

```bash
skltn skeleton [project-root] [options]
```

For a large repository, start with `--headers-only`. Use `--path <relative-file>` for one indexed file, `--language <name>` to restrict parsers, and `--kind <kind>` to restrict supported declaration kinds.

The `skeleton` command may be omitted. `get_skeleton` and `build` are aliases.

### 3. Search indexed declarations

```bash
skltn query [project-root] --q <text> [--limit <count>] [--language <name>]
```

`search` is an alias. The default limit is 20. A match inside a property or method returns the enclosing declaration block header and that block's file range.

### 4. Present results

- Use unindented declaration headers as the structural overview.
- Treat unindented `# parse_error` lines as diagnostics, not declarations.
- Preserve file paths and ranges so the user can open the original source.
- If full output is too large, rerun with `--headers-only` and report that the compact view omits properties and methods.

## Inspection commands

```bash
skltn status [project-root] [--language <name>]
skltn diagnostics [project-root] [--language <name>]
skltn files [project-root] [--language <name>]
skltn languages
```

Use `status` for index counts, `diagnostics` for parse errors and incomplete blocks, `files` for sorted indexed paths, and `languages` for parsers included in the installed binary.

## Filters

Language filters accept repeated flags or comma-separated values. The default build supports `swift`, `kotlin`, `typescript`, `go`, `zig`, `rust`, `cpp`, `python`, and `java`; the actual installed set is authoritative from `skltn languages`.

Kind filters accept `class`, `struct`, `enum`, `protocol`, `actor`, and `extension`. Parsers can emit additional language-specific header kinds, but the CLI does not accept those additional kinds as filter values.

## Output and diagnostics

Indented lines contain typed properties and method signatures. Return types are printed whenever the parser extracts one, including `Void` or `void`.

`# parse_error <file>` means the file contains a parse error or could not be parsed normally. Partial declaration blocks may still follow. `(!)` marks a declaration block containing an error node. Unknown line positions use `?`.

Read `references/output-format.md` for the output contract and `references/cli.md` for the complete command and option reference.

## CLI availability

If `skltn` is unavailable, install it with Mint:

```bash
mint install 1amageek/swift-skeleton
```

To build from source:

```bash
git clone https://github.com/1amageek/swift-skeleton.git
cd swift-skeleton
swift build -c release
```

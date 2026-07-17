import Foundation

extension SkeletonIndexCLIMain {
    static func installSkill() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let targets: [(name: String, dir: String)] = [
            ("Claude Code", "\(home)/.claude/skills/skeleton"),
            ("Codex", "\(home)/.codex/skills/skeleton"),
        ]

        var installed: [String] = []

        for target in targets {
            let parentDir = (target.dir as NSString).deletingLastPathComponent
            let toolRoot = (parentDir as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: toolRoot) else { continue }

            let refsDir = "\(target.dir)/references"
            try fm.createDirectory(atPath: refsDir, withIntermediateDirectories: true)

            let skillPath = "\(target.dir)/SKILL.md"
            try skillContent.write(toFile: skillPath, atomically: true, encoding: .utf8)

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

// MARK: - SKILL.md

private let skillContent = """
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
"""

// MARK: - references/output-format.md

private let outputFormatContent = """
# Output Format Specification

## Structure

```text
<kind> <Name>[: Inheritance] [<file>:<start>-<end>] [(!)]
  props: <name>:<Type>, ...
  methods:
    <name>(<ParamTypes>) [-> <ReturnType>] [<start>-<end>]
```

## Declaration headers

Headers are unindented and contain the parser-provided declaration keyword, name, optional inheritance or conformance list, project-relative file path, and line range.

The current parsers can emit these header kinds:

| Languages | Kinds |
|---|---|
| Swift | `class`, `struct`, `enum`, `protocol`, `actor`, `extension` |
| Kotlin | `class`, `interface`, `object`, `enum` |
| TypeScript | `class`, `interface`, `enum`, `type` |
| Go | `struct`, `interface`, `type` |
| Zig | `struct`, `enum`, `union` |
| Rust | `struct`, `enum`, `trait`, `union`, `extension` |
| C++ | `class`, `struct`, `union` |
| Python | `class` |
| Java | `class`, `interface`, `enum`, `record`, `annotation` |

Inheritance and conformance text is omitted when empty.

## Properties

Properties are emitted as a comma-separated `name:type` line. Only properties for which a parser extracts an explicit type are included. The entire line is omitted when the declaration has no extracted properties.

## Methods

Methods include parameter types without parameter names. Unknown parameter types use `?`. Initializers use `init` and omit a return type.

A parsed return type is emitted after `->`, including `Void` and `void`. The return segment is omitted when the parser does not extract a return type.

Method ranges are relative to the containing file.

## Special markers

| Marker | Meaning |
|---|---|
| `# parse_error <file>` | The file contains a parse error or could not be parsed normally; partial declarations may still be present. |
| `(!)` | The declaration block contains a parser error node and may be incomplete. |
| `?` | A parameter type or line position is unknown. |

## Ordering

- Files are sorted by path in ascending order.
- Blocks within a file remain in source order.
- Properties and methods within a block remain in source order.

## Kind filtering

The CLI accepts only `class`, `struct`, `enum`, `protocol`, `actor`, and `extension` as `--kind` or `--kinds` values. Omit kind filtering to retain language-specific kinds outside this set.
"""

// MARK: - references/cli.md

private let cliContent = """
# CLI Reference

## Commands

```text
skltn [skeleton] [project-root] [skeleton-options]
skltn query [project-root] --q <text> [query-options]
skltn query [project-root] <text> [query-options]
skltn status [project-root] [language-options]
skltn diagnostics [project-root] [language-options]
skltn files [project-root] [language-options]
skltn languages
skltn daemon
skltn install-skill
skltn help
skltn --help
skltn -h
```

If `project-root` is omitted, commands use the current working directory. The project root may also be passed with `--project-root` or `--root`.

An unrecognized first positional token is treated as the project root for the default `skeleton` command.

## Command aliases

| Alias | Command |
|---|---|
| `get_skeleton` | `skeleton` |
| `build` | `skeleton` |
| `search` | `query` |
| `diag` | `diagnostics` |

## Skeleton options

| Option | Aliases | Behavior |
|---|---|---|
| `--project-root <path>` | `--root` | Select the project directory instead of using a positional path. |
| `--path <path>` | `--file` | Return one indexed file using its project-relative or absolute path. |
| `--language <name>` | `--lang`, `--languages` | Restrict scanning to selected languages. |
| `--kind <kind>` | `--kinds` | Keep selected declaration kinds after parsing. |
| `--headers-only` | — | Keep declaration headers and parse markers; omit properties and methods. |

Language and kind options may be repeated or supplied as comma-separated values. Value options also accept the `--option=value` form.

Accepted kind filter values are `class`, `struct`, `enum`, `protocol`, `actor`, and `extension`. This list is narrower than the language-specific keywords that parsers can emit in headers.

## Query options and forms

| Option | Alias | Behavior |
|---|---|---|
| `--q <text>` | `--query` | Set the case-insensitive search text. |
| `--limit <count>` | — | Limit returned declaration blocks; defaults to 20. |
| `--language <name>` | `--lang`, `--languages` | Restrict scanning to selected languages. |

With `--q`, the first remaining positional value is the project root. Without `--q`, two positional values mean project root followed by search text; one positional value means search text in the current working directory.

Query searches declaration headers, inheritance, typed properties, method names, parameter types, and return types. Each result is the enclosing declaration block header with the block's file and range.

## Inspection commands

- `status` prints `files_indexed`, `parse_error_files`, `last_update_ts`, and `is_watching`.
- `diagnostics` prints `No diagnostics.` or `parse_error:` and `incomplete:` entries.
- `files` prints indexed project-relative paths in ascending order.
- `languages` prints parser names compiled into the executable in ascending order.

`status`, `diagnostics`, and `files` accept the project-root and language options described above.

## Process commands

- `daemon` starts the JSON-RPC 2.0 loop on standard input and standard output.
- `install-skill` installs this skill for detected Claude Code and Codex directories.

## Output size

Use `--headers-only` for a compact map. It preserves every line that does not begin with two spaces, including `# parse_error` markers.
"""

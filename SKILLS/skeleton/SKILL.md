---
name: skeleton
description: Extract and navigate a compact structural map and implementation-risk signals for a codebase with the skltn CLI, including declarations, signatures, inheritance, source ranges, parser-range-derived implementation fingerprints, and project-context heuristics. Use when exploring architecture, locating symbols, reviewing an unfamiliar repository, triaging likely stubs or fake wiring, or planning changes across files or modules.
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
- Prioritize declarations with `[impl:<domains>]`, then open the marked method ranges in the original source.
- Treat `[impl!:<reason>]` as a configured high-confidence pattern match and `[impl?:<reason>]` as a heuristic review signal.
- Use the original source as the authority before concluding that an implementation is fake, incomplete, wired incorrectly, or unreachable.
- When correctness is the goal, inspect critical unmarked paths too; no marker means only that the configured patterns found no signal.
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

Implementation markers are short signals derived from parser-provided method ranges, lexical body evidence, and project-context heuristics. Reasons are `trap`, `empty`, `const`, `noop`, `flow`, `error`, `wire`, and `dead`. Requirement-only declarations are not treated as empty implementations. `--headers-only` keeps declaration-level `[impl:<domains>]` summaries.

## Reliability boundary

- Markers prioritize source review; they do not perform name resolution, type inference, control-flow proof, data-flow proof, or semantic reachability analysis.
- Confirm that a reported trap is an invocation, that literal-looking returns do not depend on interpolation, and that error handling is evaluated in the relevant scope.
- Treat `wire` and `dead` as identifier-reference heuristics. Confirm dependency construction and call paths in the source before reporting them as defects.
- Findings classified as non-production remain internal and are not rendered. When path classification could affect an audit, inspect the indexed file list and relevant source directly.
- If a marker conflicts with the source, report the source conclusion and identify the marker as a false positive or false negative.

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

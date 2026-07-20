---
name: skeleton
description: Extract and navigate a compact structural map and implementation-risk signals for a codebase with the skltn CLI, including declarations, signatures, inheritance, source ranges, parser-range-derived implementation fingerprints, and project-context heuristics. Use when exploring architecture, locating symbols, reviewing an unfamiliar repository, working within a known SwiftPM target, triaging likely stubs or fake wiring, or planning changes across files or modules.
---

# Skeleton

Use `skltn` to inspect declarations without loading implementation bodies.

## Workflow

### 1. Resolve the project root

Use the path supplied by the user. If no path is supplied, use the current working directory.

### 2. Build a structural map

```bash
skltn get [project-root] [options]
```

Choose the narrowest view that preserves the context required by the task:

- When a SwiftPM target or module is known, use `--target` by default. This keeps the focus target complete and adds only the source-visible surface of direct imported local dependencies.
- For a large target, begin with `--headers-only`, then rerun without it only when member signatures are required.
- When the user requests an exact file or directory boundary, use that path without target expansion.
- When no target is known, begin with a repository-wide `--headers-only` map, identify the relevant target, then switch to target mode.

```bash
skltn get <package-root> --target <target-name> --headers-only
skltn get <package-root> --target <target-name>
```

Use `--path <relative-file>` for one indexed file, `--language <name>` to restrict parsers, and `--kind <kind>` to restrict supported declaration kinds.

Keep path and target intent distinct:

```bash
skltn get Sources/Feature
skltn get Sources --target Feature
```

The first command strictly scans `Sources/Feature`. The second resolves the SwiftPM target, renders it in full, and adds only source-visible declarations from direct local dependencies that the target imports. Use `--access public` only when the task needs the externally consumable API surface rather than the target's full implementation-facing structure.

The `get` command may be omitted. `skeleton`, `get_skeleton`, and `build` are compatibility aliases.

### 3. Search indexed declarations

```bash
skltn query [project-root] --q <text> [--limit <count>] [--language <name>]
```

`search` is an alias. The default limit is 20. A match inside a property or method returns the enclosing declaration block header; a standalone declaration returns its own signature and range.

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

`--access` accepts `public`, `package`, `internal`, `fileprivate`, `private`, or `all`. It filters effective access, including containing-declaration caps. In target mode the focus module is unfiltered by default; imported local dependencies default to the visibility available from the focus target. Explicit `--access` applies to every module. A parser without access metadata produces an explicit unsupported-filter error.

## Output and diagnostics

Indented lines contain typed properties and method signatures. Return types are printed whenever the parser extracts one, including `Void` or `void`.

Target mode begins sections with `module <name>` and may add one compact `imports:` line. Dependency sections carry no role or visibility labels. Swift source-declared type aliases, associated types, enum cases, subscripts, top-level functions, and typed variables are retained as declaration signatures without implementation bodies.

`# parse_error <file>` means the file contains a parse error or could not be parsed normally. Partial declaration blocks may still follow. `(!)` marks a declaration block containing an error node. Unknown line positions use `?`.

Implementation markers are short signals derived from parser-provided AST evidence and project-context heuristics. Built-in parsers summarize calls, returns, writes, branches, catches, and traps while the syntax tree is alive; function body text is not retained. Compatibility parsers that omit AST evidence use range-based fallback analysis. Reasons are `trap`, `empty`, `const`, `noop`, `flow`, `error`, `wire`, and `dead`. Requirement-only declarations are not treated as empty implementations. `--headers-only` keeps declaration-level `[impl:<domains>]` summaries.

## Reliability boundary

- Markers prioritize source review; they do not perform name resolution, type inference, control-flow proof, data-flow proof, or semantic reachability analysis.
- AST markers are intentionally narrow. They detect configured syntax patterns, not whether a plausible algorithm is semantically correct or intentionally deceptive.
- Treat `wire` and `dead` as project-context heuristics. Confirm dependency construction and call paths in the source before reporting them as defects.
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

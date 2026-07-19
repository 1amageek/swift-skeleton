# Output Format Specification

## Structure

```text
<kind> <Name>[: Inheritance] [<file>:<start>-<end>] [(!)] [impl:<domains>]
  props: <name>:<Type>, ...
  methods:
    <name>(<ParamTypes>) [-> <ReturnType>] [<start>-<end>] [impl!|?:<reason>]
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
| `[impl:<domains>]` | The declaration contains one or more implementation findings in `body`, `flow`, `error`, `wire`, or `dead`. |
| `[impl!:<reason>]` | A configured high-confidence implementation pattern matched at this method range. |
| `[impl?:<reason>]` | An AST-pattern or project-context heuristic should be reviewed at this method range. |

Only the highest-priority reason is printed per method. The internal fingerprint retains body state, parameter reads, return origins, state reads and writes, calls, control-flow paths, terminal behavior, caught errors, async operations, effects, production reachability, and implementation binding without retaining method body text.

| Reason | Signal |
|---|---|
| `trap` | Explicit trap or not-implemented terminal. |
| `empty` | Concrete non-initializer body has no executable content. |
| `const` | Inputs are ignored and only a literal result is returned. |
| `noop` | Executable syntax produces no result or observable work. |
| `flow` | Multiple branches collapse to the same literal result. |
| `error` | A caught error has no detected propagation, result, or observable handling. |
| `wire` | A fake-like implementation type is used as a production call or construction target. |
| `dead` | An explicitly private method has no production reference. |

These markers are review signals, not semantic verification. No marker means no configured pattern was detected. Requirement-only declarations remain body-absent and unflagged. Findings classified as non-production remain internal and are not rendered.

## Detection boundary

Built-in parsers use parser-provided AST evidence and a project-wide identifier/call index. Compatibility parsers that omit AST evidence use range-based fallback analysis. Neither path retains method body text or proves name resolution, types, semantic correctness, dependency wiring, or reachability.

Use the original source as the authority. Confirm invocation shape for trap findings, dependencies inside interpolated or quoted expressions for constant findings, the relevant handler scope for error findings, and construction or call paths for wire and dead findings. Path-based non-production classification can suppress rendered findings, so inspect indexed paths directly when classification affects the audit.

## Ordering

- Files are sorted by path in ascending order.
- Blocks within a file remain in source order.
- Properties and methods within a block remain in source order.

## Kind filtering

The CLI accepts only `class`, `struct`, `enum`, `protocol`, `actor`, and `extension` as `--kind` or `--kinds` values. Omit kind filtering to retain language-specific kinds outside this set.

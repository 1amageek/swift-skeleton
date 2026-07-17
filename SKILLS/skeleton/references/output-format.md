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

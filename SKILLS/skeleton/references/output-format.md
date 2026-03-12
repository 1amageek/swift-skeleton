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

Use `--kinds` (MCP) or the `kinds` parameter to filter output to specific declaration types:

Accepted values: `class`, `struct`, `enum`, `protocol`, `actor`, `extension`

Omit to include all kinds.

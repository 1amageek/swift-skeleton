# Target-Aware Skeleton Design

Status: Implemented

## Objective

Add a target-aware view without changing the strict filesystem semantics of the existing path view.

The primary value is focus. The existing project-wide view gives an agent broad coverage but spends output on unrelated modules. Target mode makes one module the detailed subject while reducing every directly relevant dependency to the interface that the subject can actually use. This should reduce output volume without removing the architectural context required to understand or review the focus module.

```text
project-wide view
  every module at similar detail
  -> broad context, large output

target view
  focus module at full detail
  + dependency modules at visible-interface detail
  -> smaller output, higher relevant-information density
```

Target mode therefore optimizes relevant-information density rather than merely truncating output. A reduction is valid only when the focus module, its imports, the contracts it can call, and visible implementation-risk signals remain available.

The two modes have different contracts:

```text
path mode
  requested path -> files below that path only

target mode
  requested scope + target name
    -> focus target implementation
    -> directly imported local target interfaces
```

Target mode is a contextual projection. It does not make an unrestricted recursive scan of external dependencies.

## CLI Contract

### Path mode

```bash
skltn get Sources/Feature
```

This command indexes and renders only files below `Sources/Feature`. It does not search for a manifest, resolve a target graph, or include sibling directories.

The existing path-mode output remains compatible.

### Target mode

```bash
skltn get Sources --target Feature
```

This command:

1. Finds the project manifest associated with the requested scope.
2. Resolves `Feature` as a project target.
3. Parses every source file owned by `Feature`.
4. Collects imports from those files.
5. Matches imported module names to direct local target dependencies.
6. Parses the matched dependency targets.
7. Renders `Feature` without access filtering.
8. Renders each dependency through the access context visible from `Feature`.

The initial implementation supports SwiftPM targets. A project resolver must explicitly claim the project before `--target` can be used. Unsupported project structures fail instead of falling back to guessed directory semantics.

### Access filter

```bash
skltn get Sources/Feature --access public
skltn get Sources --target Feature --access public
```

An explicit access filter applies to every rendered declaration. Without an explicit filter:

- path mode renders all declarations supported by the parser;
- target mode renders all focus-target declarations and only context-visible dependency declarations.

Swift access boundaries are hierarchical for this filter:

| Filter | Included effective access |
|---|---|
| `public` | `public`, `open` |
| `package` | `package`, `public`, `open` |
| `internal` | `internal`, `package`, `public`, `open` |
| `fileprivate` | `fileprivate` and broader |
| `private` or `all` | all parsed declarations |

The filter uses effective access, not a textual modifier match.

## Output Contract

Target mode groups output by module. It does not print dependency roles or visibility labels.

```text
module Feature
  imports: Feature2
struct BBB [Sources/Feature/BBB.swift:1-8]
  methods:
    load() -> AAAA [3-7]

module Feature2
struct AAAA [Sources/Feature2/AAAA.swift:1-12]
  methods:
    init() [2-4]
```

Rules:

- The focus module is first.
- Direct local dependencies follow in target-name order.
- Files remain path-sorted inside a module.
- Blocks and members remain in source order.
- The output does not contain `[dependency:*]`, `[public]`, or similar explanatory labels.
- `imports:` is the deduplicated, sorted set of source imports for the focus module.
- External modules may appear in `imports:` but their source declarations are not loaded.
- Existing parse and implementation markers retain their current spelling.
- A dependency implementation marker is rendered only when its declaration survives visibility filtering.
- `--headers-only` retains module headers, imports, declaration headers, parse markers, and declaration-level implementation markers.

## Source Boundary

The positional path has different behavior in each mode:

| Mode | Filesystem behavior |
|---|---|
| Path | The requested path is a strict recursive boundary. |
| Target | The requested path identifies project context; local target paths come from the resolved project graph. |

Target mode may include a local dependency target with a custom path outside `Sources`. It never enters external package checkouts by default.

Target-mode file paths are rendered relative to the resolved package root so paths from multiple target roots remain unambiguous.

## Architecture

```text
CLI GetRequest
  |
  +-- target absent ------------------------------+
  |                                               |
  |   SkeletonIndexCore.build(path)               |
  |     -> strict file discovery                  |
  |     -> parse                                  |
  |     -> existing flat projection               |
  |                                               |
  +-- target present -----------------------------+
      ProjectStructureResolver
        -> project graph
        -> focus target source roots
      Focus parse
        -> imports
      TargetProjectionBuilder
        -> imported direct local dependencies
        -> visibility contexts
      Dependency parse
      ModuleSkeletonFormatter
        -> focus module
        -> visible dependency surfaces
```

### Core responsibilities

`SkeletonIndexCore` owns:

- source indexing and parsing;
- implementation analysis;
- target projection orchestration;
- access-filter application;
- deterministic rendering input.

Core does not know that SwiftPM commonly uses `Sources/<Target>`.

### Project support responsibilities

A project-support module owns:

- manifest discovery;
- project-unit names and source roots;
- direct dependency edges;
- package identity;
- mapping imported module names to local project units.

SwiftPM support belongs in a new `SkeletonSwiftPMProjectSupport` target rather than `SkeletonIndexCore` or `SkeletonSwiftParser`.

### Language parser responsibilities

A language parser owns:

- imports;
- declared and effective access metadata;
- declaration signatures and ranges;
- implementation evidence.

Language-specific visibility rules are provided through a language semantics protocol. Core does not compare Swift modifier strings.

## Change Map

| Area | Planned responsibility |
|---|---|
| `Package.swift` | Add the SwiftPM project-support library and its focused test target. |
| `SkeletonIndexCore` | Add typed get requests, project-unit graph types, access metadata, target projection, and render sections. |
| `ParsedFile` | Retain imports and declaration access metadata without retaining implementation bodies. |
| `SkeletonBlock`, `PropertySignature`, `MethodSignature` | Carry declared and effective access required by projection. |
| `SkeletonIndexCore.swift` | Keep path build unchanged; orchestrate resolver, focus parse, import matching, and dependency parse for target mode. |
| `SkeletonFormatter` | Render module sections directly and apply headers-only structurally instead of filtering completed text lines. |
| `SkeletonSwiftParser` | Extract imports and access facts from Tree-sitter nodes while the tree is alive. |
| `SkeletonSwiftPMProjectSupport` | Discover `Package.swift`, run and decode `dump-package`, normalize target module names, and resolve local source roots. |
| `skltn` | Parse `--target` and `--access` into `SkeletonGetRequest`; inject project resolvers and language semantics. |
| `SkeletonIndexClient` and daemon | Carry the same optional target and access request fields over Embedded and JSON-RPC paths. |
| Tests | Verify strict path isolation, graph resolution, visibility projection, output compactness, and Sidecar parity. |

## Core Model

### Get request

```swift
public struct SkeletonGetRequest: Sendable {
    public let rootPath: String
    public let languages: [String]
    public let targetName: String?
    public let accessBoundary: AccessBoundary?
    public let kinds: Set<String>
    public let headersOnly: Bool
}
```

The CLI parses arguments once and passes a typed request. Option parsing and index mutation must not remain distributed across CLI helper methods.

### Project structure

```swift
public struct ProjectStructure: Sendable {
    public let projectRoot: String
    public let packageIdentity: String
    public let units: [ProjectUnit]
}

public struct ProjectUnit: Sendable {
    public let id: String
    public let name: String
    public let displayKind: String
    public let sourceRoots: [String]
    public let dependencies: [ProjectUnitDependency]
}
```

`displayKind` is supplied by the project adapter. SwiftPM uses `module`. Future adapters may use `crate`, `package`, or another native unit name.

### Imports

```swift
public struct SourceImport: Sendable, Equatable {
    public let moduleName: String
    public let attributes: ImportAttributes
    public let range: SourceRange
}
```

Swift import extraction must support normal, scoped, access-qualified, `@testable`, SPI, and re-exported imports. The default text output renders only module names. The additional metadata is retained for visibility decisions.

### Access metadata

Core stores normalized access scopes rather than source-language keywords:

```swift
public enum AccessScope: Sendable, Equatable {
    case exported
    case package
    case module
    case file
    case lexical
    case subclass
    case unknown
}
```

`open` and `public` both map to `exported` for visibility filtering. Overriding and subclassing capability remains separate metadata when needed.

Every block, property, method, initializer, and standalone declaration carries effective access. A nested declaration is never more visible than its containing declaration.

`unknown` is not considered visible through an explicit access filter. If an active parser cannot provide access metadata, the CLI returns an unsupported-filter error instead of silently omitting or exposing declarations.

### Index metadata

`ProjectIndex` gains:

- parsed imports per file;
- project structure when target mode is active;
- file-to-unit ownership;
- focus unit ID;
- dependency visibility contexts;
- the output base path.

The raw index retains declarations before rendering filters are applied. This prevents `--access`, `--kind`, and `--headers-only` from corrupting implementation analysis or later queries.

## SwiftPM Resolution

Target mode uses:

```bash
swift package dump-package --package-path <project-root>
```

Rationale:

- `Package.swift` is executable Swift and cannot be resolved correctly by directory convention alone.
- `dump-package` evaluates computed manifests without resolving or fetching package dependencies.
- Target mode is explicitly project-aware, so this cost does not affect strict path mode.

Safety and performance requirements:

- Never pass `--disable-sandbox`.
- Do not resolve or fetch external dependencies.
- Capture process failures as typed errors.
- Cache the decoded graph only inside the running daemon or embedded service, keyed by the standardized manifest path, manifest content digest, Swift toolchain identity, process environment identity, and resolver schema version.
- Do not persist evaluated manifest output across processes in the first release because a computed manifest can depend on process environment.
- Invalidate the in-memory cache when any key changes.
- Do not treat a cached graph as a successful resolution after a required manifest reevaluation fails.

Target path resolution:

- explicit manifest `path` wins;
- regular and executable targets default to `Sources/<Target>`;
- test targets default to `Tests/<Target>`;
- binary, plugin, and system targets without parsable local source are retained in the graph but are not rendered as source modules;
- `byName` dependencies are local only when their name matches a manifest target;
- `target` dependencies are local;
- `product` dependencies are external and are not traversed.

The focus target must exist. Unknown or ambiguous names produce a typed error with the available local target names.

## Swift Visibility Policy

Dependency projection is evaluated from the focus target's context.

| Relationship | Visible dependency declarations |
|---|---|
| Same Swift package | exported and package |
| External package | exported |
| `@testable import` with test target | exported, package, and module |
| Matching SPI import | exported plus matching SPI declarations |

The implementation must compute defaults and containment correctly:

- an unmodified declaration defaults to internal;
- members of a public concrete type default to internal;
- public protocol requirements inherit protocol visibility;
- enum cases inherit enum visibility;
- extension member defaults follow Swift extension access rules;
- a nested declaration is capped by its containing declaration;
- `@usableFromInline` does not make a declaration source-visible to another module;
- getter and setter visibility are retained separately when they differ.

These rules are extracted from Tree-sitter nodes while the syntax tree is alive. The implementation must not recover access control from full declaration strings or regular expressions.

## Dependency Selection

Target mode includes a local dependency module only when both are true:

1. the manifest declares a direct dependency edge from the focus target;
2. the focus target source imports the dependency module.

This intersection avoids rendering declared but unused libraries. Import matching uses the adapter's module-name normalization rules.

Only direct imported local dependencies are included in the first release. A dependency's own internal dependencies are not expanded. If a public signature mentions an unavailable module, its type reference and the focus import list still direct the agent to the next query.

This design does not add a dependency-depth option until a concrete need is demonstrated.

## Declared Surface Boundary

The target projection is a source-declared skeleton, not a compiler-generated module interface. It must not claim to include synthesized declarations or inferred types.

For the Swift dependency surface to be useful, the parser must cover source-declared declarations that can cross a module boundary:

- nominal and nested types;
- extensions and conformances;
- initializers, methods, properties, and subscripts;
- protocols, requirements, and associated types;
- enum cases;
- top-level functions, variables, type aliases, operators, and macros.

Until these declarations are represented, the feature is incomplete and must not be documented as a complete public interface view.

## Implementation Fingerprints

Implementation analysis runs before access projection.

- Focus-target findings use the complete focus target source set.
- Dependency findings use the complete local dependency target source set.
- Rendering removes findings attached to declarations removed by access filtering.
- A visible dependency API retains its short implementation marker.
- Findings from hidden dependency declarations do not contribute module-level markers.

Private-method `dead` analysis remains valid because all files in the owning target are indexed. Target mode must not analyze only individual files inside a target.

## Zero-Copy Boundary

The new feature must not deepen the existing source-copy path.

- A source owner is created once per file.
- Parsers receive the owner and byte ranges.
- Imports, access metadata, names, type references, and short evidence are materialized only as output metadata.
- Full declaration or method body strings are not retained.
- Target projection stores file and declaration IDs, not copied source or rendered fragments.
- Manifest JSON decoding is an external process boundary and may own its decoded buffer independently.

The existing `String` and `Array(source)` paths require a separate migration, but new target-mode types must be compatible with the source-owner design.

## Error Contract

Target mode fails explicitly for:

- no project resolver matching the requested scope;
- manifest evaluation failure;
- target not found;
- duplicate or ambiguous target identity;
- target with no local source root;
- an explicit access filter used with a parser that cannot supply access metadata.

Parser errors in individual source files keep the existing partial-output behavior. A project-graph failure does not fall back to directory-name guessing.

## API and Sidecar Changes

The Embedded and Sidecar APIs receive the same typed selection contract.

`index.open` adds optional fields:

```json
{
  "project_root": "Sources",
  "languages": ["swift"],
  "target": "Feature"
}
```

`index.get_skeleton` adds optional access and headers-only projection fields. Existing requests without these fields preserve current behavior.

Client source compatibility is preserved with overloads that create requests using `target: nil` and `accessBoundary: nil`.

## Test Strategy

### Core unit tests

- strict path mode never includes sibling paths;
- target projection orders focus before dependencies;
- dependency selection is the intersection of graph edges and imports;
- external product dependencies are not traversed;
- access projection filters blocks and members without mutating the index;
- implementation findings follow their visible declarations;
- unknown access metadata produces an error for explicit filtering.

### Swift parser tests

- import forms and module-name extraction;
- declared and effective access for types and nested types;
- concrete-type member defaults;
- protocol requirement defaults;
- extension defaults and conformances;
- package, open, public, internal, fileprivate, and private declarations;
- testable and SPI import metadata;
- getter and setter access;
- top-level and nested source-declared API coverage.

### SwiftPM resolver tests

- default and custom target paths;
- local `target` and `byName` dependencies;
- external product exclusion;
- test, executable, macro, plugin, system, and binary target classification;
- conditional dependency decoding;
- manifest failure and cache invalidation;
- no network dependency resolution.

### CLI E2E tests

Given sibling `Feature` and `Feature2` targets:

- `skltn get Sources/Feature` contains only Feature paths;
- `skltn get Sources --target Feature` contains Feature and the visible Feature2 surface;
- Feature2 internal and private declarations are absent;
- same-package package declarations are present;
- visible Feature2 implementation warnings remain present;
- dependency labels are absent;
- `--access public` narrows both focus and dependency output;
- headers-only retains module and import context;
- unknown targets return a nonzero exit code and a concise error.

Tests use focused `xcodebuild test` invocations with explicit timeouts.

## Delivery Order

1. Update and pin the Swift grammar so current Swift syntax parses reliably.
2. Add Core request, project-graph, import, and access metadata types.
3. Add AST-native Swift import and effective-access extraction.
4. Add the SwiftPM project resolver and manifest cache.
5. Add target projection and module-aware formatting.
6. Add Embedded and Sidecar request support.
7. Add focused unit and CLI E2E coverage.
8. Update README, embedded SKILL, installed SKILL, and CLI help after the executable contract is verified.

## Acceptance Criteria

- Path mode remains strict and output-compatible.
- Target mode resolves a SwiftPM target without directory-name guessing.
- The focus target is rendered in full.
- Direct imported local dependency targets are rendered only through the visibility available to the focus target.
- No dependency-role or visibility labels are added to text output.
- Explicit access filtering uses effective access.
- External package source is not traversed.
- Project-graph failures are explicit.
- Implementation markers remain attached to visible APIs.
- Embedded and Sidecar behavior matches the CLI.
- The declared Swift module surface coverage is complete enough to satisfy the listed source-declaration boundary.

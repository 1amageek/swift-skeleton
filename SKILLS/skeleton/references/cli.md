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

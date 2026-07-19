# CLI Reference

## Commands

```text
skltn get [project-root] [get-options]
skltn [project-root] [get-options]
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

An unrecognized first positional token is treated as the project root for the default `get` command.

## Command aliases

| Alias | Command |
|---|---|
| `skeleton` | `get` |
| `get_skeleton` | `get` |
| `build` | `get` |
| `search` | `query` |
| `diag` | `diagnostics` |

## Get options

| Option | Aliases | Behavior |
|---|---|---|
| `--project-root <path>` | `--root` | Select the project directory instead of using a positional path. |
| `--path <path>` | `--file` | Return one indexed file using its project-relative or absolute path. |
| `--language <name>` | `--lang`, `--languages` | Restrict scanning to selected languages. |
| `--kind <kind>` | `--kinds` | Keep selected declaration kinds after parsing. |
| `--headers-only` | — | Keep declaration headers, parse markers, and `[impl:<domains>]` summaries; omit properties and methods. |

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

Use `--headers-only` for a compact map. It preserves every line that does not begin with two spaces, including `# parse_error` and declaration-level implementation markers.

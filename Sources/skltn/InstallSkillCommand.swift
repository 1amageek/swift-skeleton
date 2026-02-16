import Foundation

extension SkeletonIndexCLIMain {
    static func installSkill() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let targets: [(name: String, dir: String, content: String)] = [
            ("Claude Code", "\(home)/.claude/skills/skeleton", claudeCodeSkillContent),
            ("Codex", "\(home)/.codex/skills/skeleton", codexSkillContent),
        ]

        var installed: [String] = []

        for target in targets {
            let parentDir = (target.dir as NSString).deletingLastPathComponent
            let toolRoot = (parentDir as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: toolRoot) else { continue }

            try fm.createDirectory(atPath: target.dir, withIntermediateDirectories: true)
            let path = "\(target.dir)/SKILL.md"
            try target.content.write(toFile: path, atomically: true, encoding: .utf8)
            installed.append("\(target.name): \(path)")
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

// MARK: - Shared sections

private let sharedBody = """
Run `skltn get_skeleton --project-root <path>` to get the structural overview of a project.

**Target**: $ARGUMENTS (if empty, use the current working directory)

## What this provides

A complete structural map of a project: every type declaration, method signature, property, and inheritance relationship — extracted instantly without reading individual files. This is the fastest way to understand what a codebase contains and how it is organized.

## Instructions

1. Determine the project root:
   - If `$ARGUMENTS` contains a path, use it
   - Otherwise use the current working directory
2. Run `skltn get_skeleton --project-root <project-root>` via Bash
3. Present the skeleton output to the user as a structural overview
4. If the output exceeds 2000 lines, summarize by showing only type headers (lines not starting with spaces) and note the full line count

## Output format

```
<kind> <Name>[: Conformances] [<file>:<start>-<end>]
  props: <name>:<Type>, ...
  methods:
    <name>(<ParamTypes>) [-> ReturnType] [<start>-<end>]
```

- Top-level lines (no indent) = type declarations. Use these for summaries
- `props:` = stored properties with types
- `methods:` = method signatures with parameter types, return type, and line range
- `[start-end]` = source file line range. Use to navigate directly to the implementation
- `# parse_error <file>` = file-level parse failure
- `(!)` suffix on a type header = partial parse (e.g., missing closing brace)
- `?` in line range = line number unknown

## Supported languages

Swift, Kotlin, TypeScript, Go, Zig, Rust, C++, Python, Java
"""

// MARK: - Claude Code

private let claudeCodeSkillContent = """
---
name: skeleton
description: Get codebase skeleton (type declarations, methods, properties) to understand project architecture. Supports Swift, Kotlin, TypeScript, Go, Zig, Rust, C++, Python, Java. Use this to grasp the full picture of a project — all types, methods, and properties at a glance. Also run before launching an Explore agent to give it structural context.
allowed-tools: Bash, Read, Task
---

\(sharedBody)

## Before Explore agents

When launching an Explore agent on a project, run `skltn get_skeleton` on that project root FIRST. Pass the skeleton result into the Explore agent's prompt so it has a structural map before exploring.

## When to use

- To grasp the full architecture of a project at a glance
- Before launching an Explore agent on a project
- When planning changes that span multiple modules
- To understand module boundaries and public API surface
- To quickly answer "what types/methods exist in this project?"
"""

// MARK: - Codex

private let codexSkillContent = """
---
name: skeleton
description: Get codebase skeleton (type declarations, methods, properties) to understand project architecture. Supports Swift, Kotlin, TypeScript, Go, Zig, Rust, C++, Python, Java. Use this to grasp the full picture of a project — all types, methods, and properties at a glance. Run before code exploration to give structural context.
---

\(sharedBody)

## Before code exploration

When exploring an unfamiliar codebase, run `skltn get_skeleton` on the project root FIRST. Use the skeleton result as a structural map before diving into individual files.

## When to use

- To grasp the full architecture of a project at a glance
- Before exploring an unfamiliar codebase
- When planning changes that span multiple modules
- To understand module boundaries and public API surface
- To quickly answer "what types/methods exist in this project?"
"""

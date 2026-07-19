import Foundation
import SkeletonIndexCore

@main
enum SkeletonIndexCLIMain {
    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            try runSkeleton(arguments: [])
            return
        }
        arguments.removeFirst()

        switch command {
        case "get", "skeleton", "get_skeleton", "build":
            try runSkeleton(arguments: arguments)
        case "query", "search":
            try runQuery(arguments: arguments)
        case "status":
            try runStatus(arguments: arguments)
        case "diagnostics", "diag":
            try runDiagnostics(arguments: arguments)
        case "files":
            try runFiles(arguments: arguments)
        case "languages":
            runLanguages()
        case "daemon":
            await runDaemon()
        case "install-skill":
            try installSkill()
        case "help", "--help", "-h":
            printUsage()
        default:
            arguments.insert(command, at: 0)
            try runSkeleton(arguments: arguments)
        }
    }

    private static func runSkeleton(arguments: [String]) throws {
        let core = SkeletonIndexCore(parsers: allParsers())
        let projectRoot = resolvedProjectRoot(from: arguments)
        let languages = values(for: ["--language", "--lang", "--languages"], in: arguments)
        let path = optionalValue(for: ["--path", "--file"], in: arguments)
        let kinds = Set(values(for: ["--kind", "--kinds"], in: arguments).map { $0.lowercased() })

        var index = try core.build(projectRoot: projectRoot, languages: languages)
        if !kinds.isEmpty {
            index = try filtered(index: index, kinds: kinds)
        }

        let result = core.getSkeleton(index: index, path: path)
        if hasFlag("--headers-only", in: arguments) {
            printHeadersOnly(result.text)
        } else {
            print(result.text)
        }
    }

    private static func runQuery(arguments: [String]) throws {
        let core = SkeletonIndexCore(parsers: allParsers())
        let languages = values(for: ["--language", "--lang", "--languages"], in: arguments)
        let projectRoot: String
        let query: String

        if let explicitQuery = optionalValue(for: ["--q", "--query"], in: arguments) {
            projectRoot = resolvedProjectRoot(from: arguments)
            query = explicitQuery
        } else {
            let positional = positionals(in: arguments)
            if positional.count >= 2 {
                projectRoot = positional[0]
                query = positional[1]
            } else if let first = positional.first {
                projectRoot = FileManager.default.currentDirectoryPath
                query = first
            } else {
                throw SkeletonCLIError.invalidArguments("missing --q")
            }
        }

        let limit = optionalValue(for: "--limit", in: arguments).flatMap(Int.init) ?? 20
        let index = try core.build(projectRoot: projectRoot, languages: languages)
        let hits = core.query(index: index, q: query, limit: limit)

        for hit in hits {
            print(hit.header)
        }
    }

    private static func runStatus(arguments: [String]) throws {
        let core = SkeletonIndexCore(parsers: allParsers())
        let index = try core.build(
            projectRoot: resolvedProjectRoot(from: arguments),
            languages: values(for: ["--language", "--lang", "--languages"], in: arguments)
        )
        let status = core.status(index: index)
        print("files_indexed: \(status.filesIndexed)")
        print("parse_error_files: \(status.parseErrorFiles)")
        print("last_update_ts: \(status.lastUpdateTS)")
        print("is_watching: \(status.isWatching)")
    }

    private static func runDiagnostics(arguments: [String]) throws {
        let core = SkeletonIndexCore(parsers: allParsers())
        let index = try core.build(
            projectRoot: resolvedProjectRoot(from: arguments),
            languages: values(for: ["--language", "--lang", "--languages"], in: arguments)
        )
        let diagnostics = core.diagnostics(index: index)
        if diagnostics.parseErrorFiles.isEmpty && diagnostics.incompleteBlocks.isEmpty {
            print("No diagnostics.")
            return
        }
        for file in diagnostics.parseErrorFiles {
            print("parse_error: \(file)")
        }
        for block in diagnostics.incompleteBlocks {
            let start = block.startLine.map(String.init) ?? "?"
            let end = block.endLine.map(String.init) ?? "?"
            print("incomplete: \(block.file):\(start)-\(end)")
        }
    }

    private static func runFiles(arguments: [String]) throws {
        let core = SkeletonIndexCore(parsers: allParsers())
        let index = try core.build(
            projectRoot: resolvedProjectRoot(from: arguments),
            languages: values(for: ["--language", "--lang", "--languages"], in: arguments)
        )
        for file in index.files.keys.sorted() {
            print(file)
        }
    }

    private static func runLanguages() {
        for language in allParsers().map(\.languageName).sorted() {
            print(language)
        }
    }

    private static func filtered(index: ProjectIndex, kinds: Set<String>) throws -> ProjectIndex {
        let validKinds: Set<String> = ["class", "struct", "enum", "protocol", "actor", "extension"]
        let invalidKinds = kinds.subtracting(validKinds)
        if !invalidKinds.isEmpty {
            throw SkeletonCLIError.invalidArguments("unsupported kind: \(invalidKinds.sorted().joined(separator: ","))")
        }

        let files = index.files.mapValues { parsedFile in
            let blocks = parsedFile.blocks.filter { block in
                switch block.kind {
                case .type(let keyword):
                    return kinds.contains(keyword)
                case .extension:
                    return kinds.contains("extension")
                }
            }
            return ParsedFile(
                path: parsedFile.path,
                blocks: blocks,
                hasParseError: parsedFile.hasParseError,
                methodSyntaxEvidence: parsedFile.methodSyntaxEvidence,
                implementationAnalysis: parsedFile.implementationAnalysis
            )
        }.filter { $0.value.hasParseError || !$0.value.blocks.isEmpty }

        return ProjectIndex(
            projectRoot: index.projectRoot,
            files: files,
            lastUpdateTS: index.lastUpdateTS,
            isWatching: index.isWatching
        )
    }

    private static func resolvedProjectRoot(from arguments: [String]) -> String {
        optionalValue(for: ["--project-root", "--root"], in: arguments)
            ?? positionals(in: arguments).first
            ?? FileManager.default.currentDirectoryPath
    }

    private static func printHeadersOnly(_ text: String) {
        let lines = text.split(separator: "\n").map(String.init)
        let headers = lines.filter { !$0.hasPrefix("  ") }
        print(headers.joined(separator: "\n"))
    }

    private static func value(for flag: String, in args: [String]) throws -> String {
        guard let value = optionalValue(for: flag, in: args) else {
            throw SkeletonCLIError.invalidArguments("missing \(flag)")
        }
        return value
    }

    private static func optionalValue(for flag: String, in args: [String]) -> String? {
        optionalValue(for: [flag], in: args)
    }

    private static func optionalValue(for flags: [String], in args: [String]) -> String? {
        for (idx, arg) in args.enumerated() {
            for flag in flags {
                if arg == flag, idx + 1 < args.count {
                    return args[idx + 1]
                }
                if arg.hasPrefix("\(flag)=") {
                    return String(arg.dropFirst(flag.count + 1))
                }
            }
        }
        return nil
    }

    private static func values(for flags: [String], in args: [String]) -> [String] {
        var results: [String] = []
        for (idx, arg) in args.enumerated() {
            for flag in flags {
                if arg == flag, idx + 1 < args.count {
                    results.append(contentsOf: splitValues(args[idx + 1]))
                } else if arg.hasPrefix("\(flag)=") {
                    results.append(contentsOf: splitValues(String(arg.dropFirst(flag.count + 1))))
                }
            }
        }
        return results
    }

    private static func splitValues(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func hasFlag(_ flag: String, in args: [String]) -> Bool {
        args.contains(flag)
    }

    private static func positionals(in args: [String]) -> [String] {
        let valueFlags: Set<String> = [
            "--project-root", "--root", "--path", "--file",
            "--q", "--query", "--limit",
            "--language", "--lang", "--languages",
            "--kind", "--kinds",
        ]

        var results: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if valueFlags.contains(arg) {
                skipNext = true
                continue
            }
            if arg.hasPrefix("-") {
                continue
            }
            results.append(arg)
        }
        return results
    }

    private static func printUsage() {
        print(
            """
            usage:
              skltn get [project-root] [--path <file>] [--language <name>] [--kind <kind>] [--headers-only]
              skltn [project-root] [--path <file>] [--language <name>] [--kind <kind>] [--headers-only]
              skltn query [project-root] --q <string> [--limit <n>] [--language <name>]
              skltn status [project-root] [--language <name>]
              skltn diagnostics [project-root] [--language <name>]
              skltn files [project-root] [--language <name>]
              skltn languages
              skltn daemon
              skltn install-skill

            aliases:
              skeleton, get_skeleton, build -> get
              search -> query
              diag -> diagnostics
            """
        )
    }
}

enum SkeletonCLIError: Error {
    case invalidArguments(String)
}

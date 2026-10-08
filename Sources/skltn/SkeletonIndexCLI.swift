import Foundation
import SkeletonIndexCore

@main
enum SkeletonIndexCLIMain {
  static func main() async {
    do {
      try await run(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch let error as SkeletonCLIError {
      writeError("\(error)\nrun 'skltn help' for usage")
      exit(2)
    } catch {
      writeError("\(error)")
      exit(1)
    }
  }

  private static func run(arguments commandLine: [String]) async throws {
    var arguments = commandLine
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
      try validateOptions(arguments, valueFlags: [], booleanFlags: [], maximumPositionals: 0)
      runLanguages()
    case "daemon":
      try validateOptions(arguments, valueFlags: [], booleanFlags: [], maximumPositionals: 0)
      await runDaemon()
    case "install-skill":
      try validateOptions(arguments, valueFlags: [], booleanFlags: [], maximumPositionals: 0)
      try installSkill()
    case "help", "--help", "-h":
      printUsage()
    default:
      arguments.insert(command, at: 0)
      try runSkeleton(arguments: arguments)
    }
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data("skltn: error: \(message)\n".utf8))
  }

  private static let rootFlags: Set<String> = ["--project-root", "--root"]
  private static let languageFlags: Set<String> = ["--language", "--lang", "--languages"]
  private static let getValueFlags: Set<String> = rootFlags.union(languageFlags).union([
    "--path", "--file", "--target", "--access", "--kind", "--kinds",
  ])
  private static let queryValueFlags: Set<String> = rootFlags.union(languageFlags).union([
    "--q", "--query", "--limit",
  ])
  private static let inspectionValueFlags: Set<String> = rootFlags.union(languageFlags)

  private static func runSkeleton(arguments: [String]) throws {
    try validateOptions(
      arguments, valueFlags: getValueFlags, booleanFlags: ["--headers-only"], maximumPositionals: 1)
    let core = makeCore()
    let projectRoot = resolvedProjectRoot(from: arguments)
    let languages = values(for: ["--language", "--lang", "--languages"], in: arguments)
    let path = optionalValue(for: ["--path", "--file"], in: arguments)
    let target = optionalValue(for: "--target", in: arguments)
    let kinds = try RequestValidation.kinds(values(for: ["--kind", "--kinds"], in: arguments))
    let access = try RequestValidation.accessBoundary(optionalValue(for: "--access", in: arguments))

    let index = try core.build(projectRoot: projectRoot, languages: languages, targetName: target)
    try core.validateRender(index: index, accessBoundary: access)

    let result = core.getSkeleton(
      index: index,
      path: path,
      options: SkeletonRenderOptions(
        accessBoundary: access,
        kinds: kinds,
        headersOnly: hasFlag("--headers-only", in: arguments)
      )
    )
    print(result.text)
  }

  private static func runQuery(arguments: [String]) throws {
    let hasExplicitQuery = optionalValue(for: ["--q", "--query"], in: arguments) != nil
    try validateOptions(
      arguments, valueFlags: queryValueFlags, booleanFlags: [],
      maximumPositionals: hasExplicitQuery ? 1 : 2)
    let core = makeCore()
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

    let limit = try RequestValidation.limit(optionalValue(for: "--limit", in: arguments))
    let index = try core.build(projectRoot: projectRoot, languages: languages)
    let hits = core.query(index: index, q: query, limit: limit)

    for hit in hits {
      print(hit.header)
    }
  }

  private static func runStatus(arguments: [String]) throws {
    try validateOptions(
      arguments, valueFlags: inspectionValueFlags, booleanFlags: [], maximumPositionals: 1)
    let core = makeCore()
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
    try validateOptions(
      arguments, valueFlags: inspectionValueFlags, booleanFlags: [], maximumPositionals: 1)
    let core = makeCore()
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
    try validateOptions(
      arguments, valueFlags: inspectionValueFlags, booleanFlags: [], maximumPositionals: 1)
    let core = makeCore()
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

  private static func makeCore() -> SkeletonIndexCore {
    SkeletonIndexCore(
      parsers: allParsers(),
      projectStructureResolvers: allProjectStructureResolvers()
    )
  }

  /// Rejects unknown options, value options without a value, and extra positionals
  /// instead of silently ignoring them.
  private static func validateOptions(
    _ arguments: [String],
    valueFlags: Set<String>,
    booleanFlags: Set<String>,
    maximumPositionals: Int
  ) throws {
    var index = 0
    var positionalCount = 0
    while index < arguments.count {
      let argument = arguments[index]
      index += 1
      guard argument.hasPrefix("-") else {
        positionalCount += 1
        continue
      }
      if let separator = argument.firstIndex(of: "=") {
        let flag = String(argument[..<separator])
        guard valueFlags.contains(flag) else {
          throw SkeletonCLIError.invalidArguments("unknown option: \(flag)")
        }
        continue
      }
      if booleanFlags.contains(argument) {
        continue
      }
      guard valueFlags.contains(argument) else {
        throw SkeletonCLIError.invalidArguments("unknown option: \(argument)")
      }
      guard index < arguments.count else {
        throw SkeletonCLIError.invalidArguments("missing value for \(argument)")
      }
      index += 1
    }
    if positionalCount > maximumPositionals {
      throw SkeletonCLIError.invalidArguments("unexpected arguments: expected at most \(maximumPositionals) positional value(s)")
    }
  }

  private static func resolvedProjectRoot(from arguments: [String]) -> String {
    optionalValue(for: ["--project-root", "--root"], in: arguments)
      ?? positionals(in: arguments).first
      ?? FileManager.default.currentDirectoryPath
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
      "--target", "--access",
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
        skltn get [project-root] [--target <name>] [--access <level>] [--path <file>] [--language <name>] [--kind <kind>] [--headers-only]
        skltn [project-root] [--target <name>] [--access <level>] [--path <file>] [--language <name>] [--kind <kind>] [--headers-only]
        skltn query [project-root] --q <text> [--limit <n>] [--language <name>]
        skltn query [project-root] <text> [--limit <n>] [--language <name>]
        skltn status [project-root] [--language <name>]
        skltn diagnostics [project-root] [--language <name>]
        skltn files [project-root] [--language <name>]
        skltn languages
        skltn daemon
        skltn install-skill
        skltn help

      aliases:
        skeleton, get_skeleton, build -> get
        search -> query
        diag -> diagnostics
        --help, -h -> help

      option aliases:
        --project-root, --root
        --path, --file
        --language, --lang, --languages
        --kind, --kinds
        --q, --query

      value options also accept --option=value; language and kind values may be comma-separated.
      exit status: 0 success, 1 indexing failure, 2 invalid arguments.
      """
    )
  }
}

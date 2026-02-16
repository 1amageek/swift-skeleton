import Foundation
import SkeletonIndexCore

@main
enum SkeletonIndexCLIMain {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "daemon":
            await runDaemon()
        case "mcp":
            try await runMCP()
        case "build", "get_skeleton":
            try runGetSkeleton(arguments: arguments)
        case "query":
            try runQuery(arguments: arguments)
        default:
            printUsage()
        }
    }

    private static func runGetSkeleton(arguments: [String]) throws {
        let projectRoot = try value(for: "--project-root", in: arguments)
        let path = optionalValue(for: "--path", in: arguments)
        let core = SkeletonIndexCore(parsers: allParsers())
        let index = try core.build(projectRoot: projectRoot)
        let result = core.getSkeleton(index: index, path: path)
        print(result.text)
    }

    private static func runQuery(arguments: [String]) throws {
        let projectRoot = try value(for: "--project-root", in: arguments)
        let query = try value(for: "--q", in: arguments)
        let limit = optionalValue(for: "--limit", in: arguments).flatMap(Int.init) ?? 20
        let core = SkeletonIndexCore(parsers: allParsers())
        let index = try core.build(projectRoot: projectRoot)
        let hits = core.query(index: index, q: query, limit: limit)
        for hit in hits {
            let start = hit.startLine.map(String.init) ?? "?"
            let end = hit.endLine.map(String.init) ?? "?"
            print("\(hit.header) [\(hit.file):\(start)-\(end)]")
        }
    }

    private static func value(for flag: String, in args: [String]) throws -> String {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else {
            throw SkeletonCLIError.invalidArguments("missing \(flag)")
        }
        return args[idx + 1]
    }

    private static func optionalValue(for flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else {
            return nil
        }
        return args[idx + 1]
    }

    private static func printUsage() {
        print(
            """
            usage:
              skltn get_skeleton --project-root <path> [--path <file>]
              skltn query --project-root <path> --q <string> [--limit <n>]
              skltn daemon
              skltn mcp
            """
        )
    }
}

enum SkeletonCLIError: Error {
    case invalidArguments(String)
}

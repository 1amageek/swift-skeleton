import Foundation
import SkeletonIndexClient
import SkeletonSwiftParser

@main
enum SkeletonIndexCLIMain {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }

        do {
            switch command {
            case "build", "get_skeleton":
                let projectRoot = try value(for: "--project-root", in: arguments)
                let path = optionalValue(for: "--path", in: arguments)
                let service = EmbeddedService(parsers: [SwiftSkeletonParser()])
                let opened = try await service.open(projectRoot: projectRoot, languages: ["swift"])
                let result = try await service.getSkeleton(projectID: opened.projectID, path: path)
                print(result.text)
            case "query":
                let projectRoot = try value(for: "--project-root", in: arguments)
                let query = try value(for: "--q", in: arguments)
                let limit = optionalValue(for: "--limit", in: arguments).flatMap(Int.init) ?? 20
                let service = EmbeddedService(parsers: [SwiftSkeletonParser()])
                let opened = try await service.open(projectRoot: projectRoot, languages: ["swift"])
                let hits = try await service.query(projectID: opened.projectID, q: query, limit: limit)
                for hit in hits {
                    let start = hit.startLine.map(String.init) ?? "?"
                    let end = hit.endLine.map(String.init) ?? "?"
                    print("\(hit.header) [\(hit.file):\(start)-\(end)]")
                }
            default:
                printUsage()
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
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
              skeletonindex build --project-root <path> [--path <file>]
              skeletonindex get_skeleton --project-root <path> [--path <file>]
              skeletonindex query --project-root <path> --q <string> [--limit <n>]
            """
        )
    }
}

enum SkeletonCLIError: Error {
    case invalidArguments(String)
}

import Foundation
import MCP
import SkeletonIndexCore
import SkeletonSwiftParser

func runMCP() async throws {
    let core = SkeletonIndexCore(parsers: [SwiftSkeletonParser()])
    let cache = IndexCache(core: core)

    let server = Server(
        name: "skeletonindex",
        version: "1.0.0",
        capabilities: .init(
            tools: .init()
        )
    )

    let transport = StdioTransport()
    try await server.start(transport: transport)

    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: [
            Tool(
                name: "get_skeleton",
                description: "Get declaration skeleton of a project or specific file. Returns type/extension declarations, properties, method signatures, inheritance, and source locations.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_root": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to the project root directory"),
                        ]),
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Optional relative file path to get skeleton for a specific file"),
                        ]),
                        "kinds": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Filter by declaration kind: class, struct, enum, protocol, actor, extension. Omit to include all."),
                        ]),
                    ]),
                    "required": .array([.string("project_root")]),
                ])
            ),
            Tool(
                name: "query_symbols",
                description: "Search for symbols (types, methods, properties) by name. Returns matching declarations with file path and line numbers.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_root": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to the project root directory"),
                        ]),
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query string to match against symbol names"),
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of results to return (default: 20)"),
                        ]),
                    ]),
                    "required": .array([.string("project_root"), .string("query")]),
                ])
            ),
        ])
    }

    await server.withMethodHandler(CallTool.self) { request in
        switch request.name {
        case "get_skeleton":
            return await handleGetSkeleton(request: request, cache: cache)
        case "query_symbols":
            return await handleQuerySymbols(request: request, cache: cache)
        default:
            return CallTool.Result(
                content: [.text("Unknown tool: \(request.name)")],
                isError: true
            )
        }
    }

    await server.waitUntilCompleted()
}

private func handleGetSkeleton(
    request: CallTool.Parameters,
    cache: IndexCache
) async -> CallTool.Result {
    guard let projectRoot = request.arguments?["project_root"]?.stringValue else {
        return CallTool.Result(
            content: [.text("Missing required parameter: project_root")],
            isError: true
        )
    }

    let path = request.arguments?["path"]?.stringValue
    let kinds: Set<String>? = request.arguments?["kinds"]?.arrayValue.map { array in
        Set(array.compactMap(\.stringValue))
    }

    do {
        let result = try await cache.getSkeleton(projectRoot: projectRoot, path: path, kinds: kinds)
        return CallTool.Result(content: [.text(result.text)])
    } catch {
        return CallTool.Result(
            content: [.text("Error: \(error)")],
            isError: true
        )
    }
}

private func handleQuerySymbols(
    request: CallTool.Parameters,
    cache: IndexCache
) async -> CallTool.Result {
    guard let projectRoot = request.arguments?["project_root"]?.stringValue else {
        return CallTool.Result(
            content: [.text("Missing required parameter: project_root")],
            isError: true
        )
    }

    guard let query = request.arguments?["query"]?.stringValue else {
        return CallTool.Result(
            content: [.text("Missing required parameter: query")],
            isError: true
        )
    }

    let limit = request.arguments?["limit"]?.intValue ?? 20

    do {
        let hits = try await cache.query(projectRoot: projectRoot, q: query, limit: limit)
        if hits.isEmpty {
            return CallTool.Result(content: [.text("No results found for: \(query)")])
        }
        let lines = hits.map { hit in
            var line = hit.header
            if let startLine = hit.startLine {
                line += " (\(hit.file):\(startLine))"
            } else {
                line += " (\(hit.file))"
            }
            return line
        }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    } catch {
        return CallTool.Result(
            content: [.text("Error: \(error)")],
            isError: true
        )
    }
}

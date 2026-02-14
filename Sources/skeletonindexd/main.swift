import Foundation
import SkeletonIndexCore

@main
enum SkeletonIndexDaemonMain {
    static func main() async {
        let registry = SkeletonProjectRegistry()
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput

        while let line = readLine() {
            let response = await handle(line: line, registry: registry)
            do {
                let data = try JSONSerialization.data(withJSONObject: response, options: [])
                stdout.write(data)
                stdout.write(Data([0x0A]))
            } catch {
                let fallback: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": NSNull(),
                    "error": [
                        "code": -32603,
                        "message": "failed to serialize response",
                    ],
                ]
                do {
                    let data = try JSONSerialization.data(withJSONObject: fallback, options: [])
                    stdout.write(data)
                    stdout.write(Data([0x0A]))
                } catch {
                    // Ignore serialization failure for fallback response.
                }
            }
            if stdin.availableData.isEmpty {
                break
            }
        }
    }

    private static func handle(line: String, registry: SkeletonProjectRegistry) async -> [String: Any] {
        guard let data = line.data(using: .utf8) else {
            return errorResponse(id: NSNull(), code: -32700, message: "invalid utf8")
        }

        let payload: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return errorResponse(id: NSNull(), code: -32700, message: "invalid json object")
            }
            payload = object
        } catch {
            return errorResponse(id: NSNull(), code: -32700, message: "invalid json")
        }

        guard
            let jsonrpc = payload["jsonrpc"] as? String,
            jsonrpc == "2.0",
            let method = payload["method"] as? String
        else {
            return errorResponse(id: payload["id"] ?? NSNull(), code: -32600, message: "invalid request")
        }
        let id = payload["id"] ?? NSNull()
        let params = payload["params"] as? [String: Any] ?? [:]

        do {
            let result: Any
            switch method {
            case "index.open":
                let projectRoot = try requireString(params, key: "project_root")
                let languages = params["languages"] as? [String] ?? ["swift"]
                let openResult = try await registry.open(projectRoot: projectRoot, languages: languages)
                result = [
                    "project_id": openResult.projectID,
                    "status": encodeStatus(openResult.status),
                ]
            case "index.status":
                let projectID = try requireString(params, key: "project_id")
                let status = try await registry.status(projectID: projectID)
                result = encodeStatus(status)
            case "index.get_skeleton":
                let projectID = try requireString(params, key: "project_id")
                let path = params["path"] as? String
                let skeleton = try await registry.getSkeleton(projectID: projectID, path: path)
                result = [
                    "text": skeleton.text,
                    "has_errors": skeleton.hasErrors,
                ]
            case "index.update":
                let projectID = try requireString(params, key: "project_id")
                let changedPaths = params["changed_paths"] as? [String] ?? []
                let removedPaths = params["removed_paths"] as? [String] ?? []
                let status = try await registry.update(projectID: projectID, changedPaths: changedPaths, removedPaths: removedPaths)
                result = ["status": encodeStatus(status)]
            case "index.query":
                let projectID = try requireString(params, key: "project_id")
                let query = try requireString(params, key: "q")
                let limit = params["limit"] as? Int ?? 20
                let hits = try await registry.query(projectID: projectID, q: query, limit: limit)
                result = [
                    "hits": hits.map { hit in
                        [
                            "header": hit.header,
                            "file": hit.file,
                            "startLine": hit.startLine as Any,
                            "endLine": hit.endLine as Any,
                        ]
                    },
                ]
            case "index.diagnostics":
                let projectID = try requireString(params, key: "project_id")
                let diagnostics = try await registry.diagnostics(projectID: projectID)
                result = [
                    "parse_error_files": diagnostics.parseErrorFiles,
                    "incomplete_blocks": diagnostics.incompleteBlocks.map {
                        [
                            "file": $0.file,
                            "startLine": $0.startLine as Any,
                            "endLine": $0.endLine as Any,
                        ]
                    },
                ]
            default:
                return errorResponse(id: id, code: -32601, message: "method not found")
            }
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": result,
            ]
        } catch {
            return errorResponse(id: id, code: -32000, message: String(describing: error))
        }
    }

    private static func requireString(_ params: [String: Any], key: String) throws -> String {
        guard let value = params[key] as? String, !value.isEmpty else {
            throw SkeletonError.invalidRequest("missing \(key)")
        }
        return value
    }

    private static func encodeStatus(_ status: IndexStatus) -> [String: Any] {
        [
            "files_indexed": status.filesIndexed,
            "parse_error_files": status.parseErrorFiles,
            "last_update_ts": status.lastUpdateTS,
            "is_watching": status.isWatching,
        ]
    }

    private static func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message,
            ],
        ]
    }
}

import Foundation
import SkeletonIndexCore

public final actor SidecarService: SkeletonIndexService {
    private let executablePath: String
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var nextRequestID = 1

    public init(executablePath: String = "skeletonindexd") {
        self.executablePath = executablePath
    }

    deinit {
        if let process {
            process.terminate()
        }
    }

    public func open(projectRoot: String, languages: [String]) async throws -> OpenResult {
        let value = try send(method: "index.open", params: [
            "project_root": projectRoot,
            "languages": languages,
        ])
        guard
            let result = value as? [String: Any],
            let projectID = result["project_id"] as? String,
            let statusValue = result["status"] as? [String: Any]
        else {
            throw SkeletonError.invalidResponse("index.open result")
        }
        return OpenResult(projectID: projectID, status: try parseStatus(statusValue))
    }

    public func status(projectID: String) async throws -> IndexStatus {
        let value = try send(method: "index.status", params: ["project_id": projectID])
        guard let result = value as? [String: Any] else {
            throw SkeletonError.invalidResponse("index.status result")
        }
        return try parseStatus(result)
    }

    public func getSkeleton(projectID: String, path: String?) async throws -> SkeletonTextResult {
        var params: [String: Any] = ["project_id": projectID]
        if let path {
            params["path"] = path
        }
        let value = try send(method: "index.get_skeleton", params: params)
        guard
            let result = value as? [String: Any],
            let text = result["text"] as? String,
            let hasErrors = result["has_errors"] as? Bool
        else {
            throw SkeletonError.invalidResponse("index.get_skeleton result")
        }
        return SkeletonTextResult(text: text, hasErrors: hasErrors)
    }

    public func update(
        projectID: String,
        changedPaths: [String],
        removedPaths: [String]
    ) async throws -> IndexStatus {
        let value = try send(method: "index.update", params: [
            "project_id": projectID,
            "changed_paths": changedPaths,
            "removed_paths": removedPaths,
        ])
        guard
            let result = value as? [String: Any],
            let statusValue = result["status"] as? [String: Any]
        else {
            throw SkeletonError.invalidResponse("index.update result")
        }
        return try parseStatus(statusValue)
    }

    public func query(projectID: String, q: String, limit: Int) async throws -> [QueryHit] {
        let value = try send(method: "index.query", params: [
            "project_id": projectID,
            "q": q,
            "limit": limit,
        ])
        guard
            let result = value as? [String: Any],
            let hitsValue = result["hits"] as? [[String: Any]]
        else {
            throw SkeletonError.invalidResponse("index.query result")
        }

        return hitsValue.compactMap { value in
            guard
                let header = value["header"] as? String,
                let file = value["file"] as? String
            else {
                return nil
            }
            let startLine = value["startLine"] as? Int
            let endLine = value["endLine"] as? Int
            return QueryHit(header: header, file: file, startLine: startLine, endLine: endLine)
        }
    }

    public func diagnostics(projectID: String) async throws -> IndexDiagnostics {
        let value = try send(method: "index.diagnostics", params: ["project_id": projectID])
        guard let result = value as? [String: Any] else {
            throw SkeletonError.invalidResponse("index.diagnostics result")
        }

        let parseErrorFiles = result["parse_error_files"] as? [String] ?? []
        let incompleteValues = result["incomplete_blocks"] as? [[String: Any]] ?? []
        let incompleteBlocks = incompleteValues.map { value in
            IncompleteBlock(
                file: value["file"] as? String ?? "",
                startLine: value["startLine"] as? Int,
                endLine: value["endLine"] as? Int
            )
        }

        return IndexDiagnostics(parseErrorFiles: parseErrorFiles, incompleteBlocks: incompleteBlocks)
    }

    private func ensureProcess() throws {
        if process != nil {
            return
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = [executablePath]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = FileHandle.nullDevice

        do {
            try child.run()
        } catch {
            throw SkeletonError.invalidResponse("failed to launch \(executablePath)")
        }

        process = child
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
    }

    private func send(method: String, params: [String: Any]) throws -> Any {
        try ensureProcess()
        guard let input, let output else {
            throw SkeletonError.invalidResponse("sidecar handles unavailable")
        }

        let requestID = nextRequestID
        nextRequestID += 1

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params,
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request, options: [])
        input.write(requestData)
        guard let newline = "\n".data(using: .utf8) else {
            throw SkeletonError.invalidResponse("newline encoding")
        }
        input.write(newline)

        let responseLine = try readLine(from: output)
        guard let responseData = responseLine.data(using: .utf8) else {
            throw SkeletonError.invalidResponse("response encoding")
        }
        let rawValue = try JSONSerialization.jsonObject(with: responseData, options: [])
        guard let response = rawValue as? [String: Any] else {
            throw SkeletonError.invalidResponse("response object")
        }

        if let errorValue = response["error"] as? [String: Any] {
            let message = errorValue["message"] as? String ?? "unknown"
            throw SkeletonError.invalidResponse(message)
        }
        guard let result = response["result"] else {
            throw SkeletonError.invalidResponse("result missing")
        }
        return result
    }

    private func readLine(from handle: FileHandle) throws -> String {
        var buffer = Data()

        while true {
            let chunk = handle.readData(ofLength: 1)
            guard !chunk.isEmpty else {
                throw SkeletonError.invalidResponse("sidecar closed")
            }
            if chunk[0] == UInt8(ascii: "\n") {
                break
            }
            buffer.append(chunk)
        }

        guard let line = String(data: buffer, encoding: .utf8) else {
            throw SkeletonError.invalidResponse("invalid utf8 line")
        }
        return line
    }

    private func parseStatus(_ object: [String: Any]) throws -> IndexStatus {
        guard
            let filesIndexed = object["files_indexed"] as? Int,
            let parseErrorFiles = object["parse_error_files"] as? Int,
            let lastUpdateTS = object["last_update_ts"] as? String,
            let isWatching = object["is_watching"] as? Bool
        else {
            throw SkeletonError.invalidResponse("status payload")
        }
        return IndexStatus(
            filesIndexed: filesIndexed,
            parseErrorFiles: parseErrorFiles,
            lastUpdateTS: lastUpdateTS,
            isWatching: isWatching
        )
    }
}

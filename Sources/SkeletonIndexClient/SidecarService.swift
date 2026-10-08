import Foundation
import SkeletonIndexCore

/// Talks to `skltn daemon` over JSON-RPC 2.0 on the child's stdin/stdout.
///
/// Responses are read by a background task and matched to requests by id, so waiting for a
/// response suspends instead of blocking a cooperative thread. A request fails with a thrown
/// error when the daemon cannot be launched, exits, exceeds `requestTimeout`, or the calling
/// task is cancelled; the next request relaunches the daemon.
public final actor SidecarService: SkeletonIndexService {
  private struct Connection {
    let generation: Int
    let process: Process
    let input: FileHandle
    let reader: Task<Void, Never>
  }

  private let executablePath: String
  private let executableArguments: [String]
  private let requestTimeout: Duration
  private var connection: Connection?
  private var generation = 0
  private var nextRequestID = 1
  private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
  private var timeouts: [Int: Task<Void, Never>] = [:]

  public init(
    executablePath: String = "skltn",
    arguments: [String] = ["daemon"],
    requestTimeout: Duration = .seconds(300)
  ) {
    self.executablePath = executablePath
    self.executableArguments = arguments
    self.requestTimeout = requestTimeout
  }

  deinit {
    if let connection {
      connection.reader.cancel()
      if connection.process.isRunning {
        connection.process.terminate()
      }
    }
    for timeout in timeouts.values {
      timeout.cancel()
    }
  }

  /// Stops the daemon and fails every in-flight request. A later request starts a new daemon.
  public func shutdown() {
    terminateConnection(failure: SkeletonError.invalidResponse("sidecar shut down"))
  }

  public func open(projectRoot: String, languages: [String]) async throws -> OpenResult {
    try await open(projectRoot: projectRoot, languages: languages, targetName: nil)
  }

  public func open(
    projectRoot: String,
    languages: [String],
    targetName: String?
  ) async throws -> OpenResult {
    var params: [String: Any] = [
      "project_root": projectRoot,
      "languages": languages,
    ]
    if let targetName {
      params["target"] = targetName
    }
    let result = try object(try await send(method: "index.open", params: params), "index.open result")
    guard
      let projectID = result["project_id"] as? String,
      let statusValue = result["status"] as? [String: Any]
    else {
      throw SkeletonError.invalidResponse("index.open result")
    }
    return OpenResult(projectID: projectID, status: try parseStatus(statusValue))
  }

  public func status(projectID: String) async throws -> IndexStatus {
    let value = try await send(method: "index.status", params: ["project_id": projectID])
    return try parseStatus(try object(value, "index.status result"))
  }

  public func getSkeleton(projectID: String, path: String?) async throws -> SkeletonTextResult {
    try await getSkeleton(projectID: projectID, path: path, options: .default)
  }

  public func getSkeleton(
    projectID: String,
    path: String?,
    options: SkeletonRenderOptions
  ) async throws -> SkeletonTextResult {
    var params: [String: Any] = ["project_id": projectID]
    if let path {
      params["path"] = path
    }
    if let accessBoundary = options.accessBoundary {
      params["access"] = accessBoundary.rawValue
    }
    if !options.kinds.isEmpty {
      params["kinds"] = options.kinds.sorted()
    }
    if options.headersOnly {
      params["headers_only"] = true
    }
    let result = try object(
      try await send(method: "index.get_skeleton", params: params), "index.get_skeleton result")
    guard
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
    let value = try await send(
      method: "index.update",
      params: [
        "project_id": projectID,
        "changed_paths": changedPaths,
        "removed_paths": removedPaths,
      ])
    guard let statusValue = try object(value, "index.update result")["status"] as? [String: Any] else {
      throw SkeletonError.invalidResponse("index.update result")
    }
    return try parseStatus(statusValue)
  }

  public func query(projectID: String, q: String, limit: Int) async throws -> [QueryHit] {
    let value = try await send(
      method: "index.query",
      params: [
        "project_id": projectID,
        "q": q,
        "limit": limit,
      ])
    guard let hitsValue = try object(value, "index.query result")["hits"] as? [[String: Any]] else {
      throw SkeletonError.invalidResponse("index.query result")
    }
    return try hitsValue.map { value in
      guard
        let header = value["header"] as? String,
        let file = value["file"] as? String
      else {
        throw SkeletonError.invalidResponse("index.query hit")
      }
      return QueryHit(
        header: header,
        file: file,
        startLine: try optionalLine(value["startLine"]),
        endLine: try optionalLine(value["endLine"])
      )
    }
  }

  public func diagnostics(projectID: String) async throws -> IndexDiagnostics {
    let result = try object(
      try await send(method: "index.diagnostics", params: ["project_id": projectID]),
      "index.diagnostics result")
    guard
      let parseErrorFiles = result["parse_error_files"] as? [String],
      let incompleteValues = result["incomplete_blocks"] as? [[String: Any]]
    else {
      throw SkeletonError.invalidResponse("index.diagnostics result")
    }
    let incompleteBlocks = try incompleteValues.map { value in
      guard let file = value["file"] as? String else {
        throw SkeletonError.invalidResponse("index.diagnostics incomplete block")
      }
      return IncompleteBlock(
        file: file,
        startLine: try optionalLine(value["startLine"]),
        endLine: try optionalLine(value["endLine"])
      )
    }
    return IndexDiagnostics(parseErrorFiles: parseErrorFiles, incompleteBlocks: incompleteBlocks)
  }

  // MARK: - Transport

  private func send(method: String, params: [String: Any]) async throws -> Any {
    let connection = try ensureConnection()
    let requestID = nextRequestID
    nextRequestID += 1

    var requestData = try JSONSerialization.data(
      withJSONObject: [
        "jsonrpc": "2.0",
        "id": requestID,
        "method": method,
        "params": params,
      ],
      options: []
    )
    requestData.append(0x0A)

    let responseData = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        pending[requestID] = continuation
        do {
          try connection.input.write(contentsOf: requestData)
        } catch {
          terminateConnection(failure: SkeletonError.invalidResponse("sidecar is not accepting requests"))
          return
        }
        scheduleTimeout(requestID: requestID, method: method)
      }
    } onCancel: {
      Task { await self.fail(requestID: requestID, with: CancellationError()) }
    }
    return try decodeResult(responseData)
  }

  private func ensureConnection() throws -> Connection {
    if let connection {
      return connection
    }

    let child = Process()
    child.executableURL = try resolvedExecutableURL()
    child.arguments = executableArguments

    let inputPipe = Pipe()
    let outputPipe = Pipe()
    child.standardInput = inputPipe
    child.standardOutput = outputPipe
    child.standardError = FileHandle.nullDevice

    let input = inputPipe.fileHandleForWriting
    // A write after the daemon exits must fail with EPIPE instead of raising SIGPIPE,
    // which would terminate the host process.
    guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw SkeletonError.invalidResponse("failed to configure sidecar pipe")
    }

    do {
      try child.run()
    } catch {
      throw SkeletonError.invalidResponse("failed to launch \(executablePath): \(error.localizedDescription)")
    }

    generation += 1
    let currentGeneration = generation
    let output = outputPipe.fileHandleForReading
    let reader = Task { [weak self] in
      do {
        for try await line in output.bytes.lines {
          await self?.deliver(line: line)
        }
        await self?.connectionClosed(generation: currentGeneration)
      } catch {
        await self?.connectionClosed(generation: currentGeneration)
      }
    }
    let connection = Connection(generation: currentGeneration, process: child, input: input, reader: reader)
    self.connection = connection
    return connection
  }

  private func resolvedExecutableURL() throws -> URL {
    let fileManager = FileManager.default
    if executablePath.contains("/") {
      guard fileManager.isExecutableFile(atPath: executablePath) else {
        throw SkeletonError.invalidResponse("sidecar executable not found: \(executablePath)")
      }
      return URL(fileURLWithPath: executablePath)
    }
    let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for directory in searchPath.split(separator: ":") where !directory.isEmpty {
      let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executablePath)
      if fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    throw SkeletonError.invalidResponse("sidecar executable not found in PATH: \(executablePath)")
  }

  private func scheduleTimeout(requestID: Int, method: String) {
    let timeout = requestTimeout
    timeouts[requestID] = Task { [weak self] in
      do {
        try await Task.sleep(for: timeout)
      } catch {
        return
      }
      await self?.timeOut(requestID: requestID, method: method)
    }
  }

  private func timeOut(requestID: Int, method: String) {
    guard pending[requestID] != nil else {
      return
    }
    // A daemon that stops answering cannot be trusted for later requests either.
    fail(requestID: requestID, with: SkeletonError.invalidResponse("sidecar request timed out: \(method)"))
    terminateConnection(failure: SkeletonError.invalidResponse("sidecar restarted after a timeout"))
  }

  private func deliver(line: String) {
    let data = Data(line.utf8)
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data, options: [])
    } catch {
      terminateConnection(failure: SkeletonError.invalidResponse("sidecar wrote a non-JSON line"))
      return
    }
    guard let response = object as? [String: Any], let requestID = response["id"] as? Int else {
      // Responses without a request id cannot be matched; the daemon only emits them for
      // malformed input, which this client never sends.
      return
    }
    timeouts.removeValue(forKey: requestID)?.cancel()
    pending.removeValue(forKey: requestID)?.resume(returning: data)
  }

  private func fail(requestID: Int, with error: any Error) {
    timeouts.removeValue(forKey: requestID)?.cancel()
    pending.removeValue(forKey: requestID)?.resume(throwing: error)
  }

  private func connectionClosed(generation closedGeneration: Int) {
    guard connection?.generation == closedGeneration else {
      return
    }
    let status = connection.map { $0.process.isRunning ? "running" : "exit \($0.process.terminationStatus)" }
    terminateConnection(failure: SkeletonError.invalidResponse("sidecar exited (\(status ?? "unknown"))"))
  }

  private func terminateConnection(failure: SkeletonError) {
    if let connection {
      self.connection = nil
      connection.reader.cancel()
      do {
        try connection.input.close()
      } catch {
        // The pipe is already closed when the daemon exited first.
      }
      if connection.process.isRunning {
        connection.process.terminate()
      }
    }
    for requestID in Array(pending.keys) {
      fail(requestID: requestID, with: failure)
    }
  }

  // MARK: - Decoding

  private func decodeResult(_ data: Data) throws -> Any {
    let rawValue = try JSONSerialization.jsonObject(with: data, options: [])
    guard let response = rawValue as? [String: Any] else {
      throw SkeletonError.invalidResponse("response object")
    }
    if let errorValue = response["error"] as? [String: Any] {
      throw decodeError(errorValue)
    }
    guard let result = response["result"] else {
      throw SkeletonError.invalidResponse("result missing")
    }
    return result
  }

  /// Daemon errors carry the `SkeletonError` case in `data`, so callers see the same error
  /// values they would get from `EmbeddedService`.
  private func decodeError(_ errorValue: [String: Any]) -> SkeletonError {
    if let data = errorValue["data"] as? [String: Any],
      let kind = data["kind"] as? String,
      let detail = data["detail"] as? String,
      let error = SkeletonError(kind: kind, detail: detail)
    {
      return error
    }
    let code = (errorValue["code"] as? Int).map(String.init) ?? "?"
    let message = (errorValue["message"] as? String) ?? "unknown"
    if code == "-32602" {
      return .invalidRequest(message)
    }
    return .invalidResponse("json-rpc error \(code): \(message)")
  }

  private func object(_ value: Any, _ context: String) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
      throw SkeletonError.invalidResponse(context)
    }
    return object
  }

  private func optionalLine(_ value: Any?) throws -> Int? {
    switch value {
    case nil, is NSNull:
      return nil
    case let line as Int:
      return line
    default:
      throw SkeletonError.invalidResponse("line number")
    }
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

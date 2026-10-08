import Foundation
import SkeletonIndexCore

/// JSON-RPC 2.0 over newline-delimited stdin/stdout. Each input line is one request,
/// notification, or batch; notifications (requests without an `id` member) get no reply.
func runDaemon() async {
  let core = SkeletonIndexCore(
    parsers: allParsers(),
    projectStructureResolvers: allProjectStructureResolvers()
  )
  let registry = SkeletonProjectRegistry(core: core)
  let stdout = FileHandle.standardOutput

  while let line = readLine() {
    guard let response = await handle(line: line, registry: registry) else {
      continue
    }
    do {
      let data = try JSONSerialization.data(withJSONObject: response, options: [])
      stdout.write(data)
      stdout.write(Data([0x0A]))
    } catch {
      // The result contained a value JSON cannot represent; report it on the same line slot.
      let fallback = errorResponse(id: NSNull(), code: -32603, message: "failed to serialize response")
      do {
        let data = try JSONSerialization.data(withJSONObject: fallback, options: [])
        stdout.write(data)
        stdout.write(Data([0x0A]))
      } catch {
        FileHandle.standardError.write(Data("skltn: error: failed to serialize error response\n".utf8))
      }
    }
  }
}

private enum JSONRPCErrorCode {
  static let parseError = -32700
  static let invalidRequest = -32600
  static let methodNotFound = -32601
  static let invalidParams = -32602
  static let internalError = -32603
  static let serverError = -32000
}

/// Returns nil when nothing must be written: a notification, or a batch of notifications.
private func handle(line: String, registry: SkeletonProjectRegistry) async -> Any? {
  let trimmed = line.trimmingCharacters(in: .whitespaces)
  if trimmed.isEmpty {
    return nil
  }
  let decoded: Any
  do {
    decoded = try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [])
  } catch {
    return errorResponse(id: NSNull(), code: JSONRPCErrorCode.parseError, message: "parse error")
  }

  if let batch = decoded as? [Any] {
    guard !batch.isEmpty else {
      return errorResponse(id: NSNull(), code: JSONRPCErrorCode.invalidRequest, message: "empty batch")
    }
    var responses: [[String: Any]] = []
    for element in batch {
      if let response = await handle(message: element, registry: registry) {
        responses.append(response)
      }
    }
    return responses.isEmpty ? nil : responses
  }
  return await handle(message: decoded, registry: registry)
}

private func handle(message: Any, registry: SkeletonProjectRegistry) async -> [String: Any]? {
  guard let payload = message as? [String: Any] else {
    return errorResponse(id: NSNull(), code: JSONRPCErrorCode.invalidRequest, message: "invalid request")
  }
  let idMember = payload["id"]
  let isNotification = idMember == nil
  let id: Any
  switch idMember {
  case nil, is NSNull:
    id = NSNull()
  case let value as NSNumber where CFGetTypeID(value) != CFBooleanGetTypeID():
    id = value
  case let value as String:
    id = value
  default:
    return errorResponse(id: NSNull(), code: JSONRPCErrorCode.invalidRequest, message: "invalid id")
  }

  guard payload["jsonrpc"] as? String == "2.0", let method = payload["method"] as? String else {
    return errorResponse(id: id, code: JSONRPCErrorCode.invalidRequest, message: "invalid request")
  }

  let response: [String: Any]
  do {
    let params = try Params(payload["params"])
    let result = try await dispatch(method: method, params: params, registry: registry)
    response = ["jsonrpc": "2.0", "id": id, "result": result]
  } catch let error as DaemonRequestError {
    switch error {
    case .methodNotFound:
      response = errorResponse(id: id, code: JSONRPCErrorCode.methodNotFound, message: "method not found: \(method)")
    }
  } catch let error as SkeletonCLIError {
    response = errorResponse(id: id, code: JSONRPCErrorCode.invalidParams, message: "\(error)")
  } catch let error as SkeletonError {
    response = errorResponse(
      id: id,
      code: JSONRPCErrorCode.serverError,
      message: error.description,
      data: ["kind": error.kind, "detail": error.detail]
    )
  } catch {
    response = errorResponse(id: id, code: JSONRPCErrorCode.internalError, message: "\(error)")
  }
  return isNotification ? nil : response
}

private enum DaemonRequestError: Error {
  case methodNotFound
}

private func dispatch(
  method: String,
  params: Params,
  registry: SkeletonProjectRegistry
) async throws -> Any {
  switch method {
  case "index.open":
    let openResult = try await registry.open(
      projectRoot: try params.requiredString("project_root"),
      languages: try params.stringArray("languages"),
      targetName: try params.optionalString("target")
    )
    return [
      "project_id": openResult.projectID,
      "status": encodeStatus(openResult.status),
    ]
  case "index.status":
    let status = try await registry.status(projectID: try params.requiredString("project_id"))
    return encodeStatus(status)
  case "index.get_skeleton":
    let projectID = try params.requiredString("project_id")
    let options = SkeletonRenderOptions(
      accessBoundary: try RequestValidation.accessBoundary(try params.optionalString("access")),
      // Same semantics as EmbeddedService: kinds filter blocks without a fixed allow-list.
      kinds: Set(try params.stringArray("kinds")),
      headersOnly: try params.bool("headers_only")
    )
    let skeleton = try await registry.getSkeleton(
      projectID: projectID,
      path: try params.optionalString("path"),
      options: options
    )
    return [
      "text": skeleton.text,
      "has_errors": skeleton.hasErrors,
    ]
  case "index.update":
    let status = try await registry.update(
      projectID: try params.requiredString("project_id"),
      changedPaths: try params.stringArray("changed_paths"),
      removedPaths: try params.stringArray("removed_paths")
    )
    return ["status": encodeStatus(status)]
  case "index.query":
    let hits = try await registry.query(
      projectID: try params.requiredString("project_id"),
      q: try params.requiredString("q"),
      limit: try params.limit("limit")
    )
    return [
      "hits": hits.map { hit in
        [
          "header": hit.header,
          "file": hit.file,
          "startLine": jsonValue(hit.startLine),
          "endLine": jsonValue(hit.endLine),
        ]
      }
    ]
  case "index.diagnostics":
    let diagnostics = try await registry.diagnostics(projectID: try params.requiredString("project_id"))
    return [
      "parse_error_files": diagnostics.parseErrorFiles,
      "incomplete_blocks": diagnostics.incompleteBlocks.map {
        [
          "file": $0.file,
          "startLine": jsonValue($0.startLine),
          "endLine": jsonValue($0.endLine),
        ]
      },
    ]
  default:
    throw DaemonRequestError.methodNotFound
  }
}

/// Named JSON-RPC params with typed accessors; a wrongly typed member is invalid params,
/// never a silent default.
private struct Params {
  private let values: [String: Any]

  init(_ raw: Any?) throws {
    switch raw {
    case nil:
      values = [:]
    case let object as [String: Any]:
      values = object
    default:
      throw SkeletonCLIError.invalidArguments("params must be an object")
    }
  }

  func requiredString(_ key: String) throws -> String {
    guard let value = try optionalString(key), !value.isEmpty else {
      throw SkeletonCLIError.invalidArguments("missing \(key)")
    }
    return value
  }

  func optionalString(_ key: String) throws -> String? {
    guard let raw = values[key], !(raw is NSNull) else {
      return nil
    }
    guard let value = raw as? String else {
      throw SkeletonCLIError.invalidArguments("\(key) must be a string")
    }
    return value
  }

  func stringArray(_ key: String) throws -> [String] {
    guard let raw = values[key], !(raw is NSNull) else {
      return []
    }
    guard let value = raw as? [String] else {
      throw SkeletonCLIError.invalidArguments("\(key) must be an array of strings")
    }
    return value
  }

  func bool(_ key: String) throws -> Bool {
    guard let raw = values[key], !(raw is NSNull) else {
      return false
    }
    guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
      throw SkeletonCLIError.invalidArguments("\(key) must be a boolean")
    }
    return number.boolValue
  }

  func limit(_ key: String) throws -> Int {
    guard let raw = values[key], !(raw is NSNull) else {
      return try RequestValidation.limit(nil)
    }
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let integer = Int(exactly: number.doubleValue)
    else {
      throw SkeletonCLIError.invalidArguments("\(key) must be a non-negative integer")
    }
    return try RequestValidation.limit(String(integer))
  }
}

private func jsonValue(_ value: Int?) -> Any {
  value.map { $0 as Any } ?? NSNull()
}

private func encodeStatus(_ status: IndexStatus) -> [String: Any] {
  [
    "files_indexed": status.filesIndexed,
    "parse_error_files": status.parseErrorFiles,
    "last_update_ts": status.lastUpdateTS,
    "is_watching": status.isWatching,
  ]
}

private func errorResponse(
  id: Any,
  code: Int,
  message: String,
  data: [String: Any]? = nil
) -> [String: Any] {
  var error: [String: Any] = [
    "code": code,
    "message": message,
  ]
  if let data {
    error["data"] = data
  }
  return [
    "jsonrpc": "2.0",
    "id": id,
    "error": error,
  ]
}

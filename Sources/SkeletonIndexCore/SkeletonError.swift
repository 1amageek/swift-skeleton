import Foundation

public enum SkeletonError: Error, Sendable, Equatable {
  case unsupportedLanguage(String)
  case invalidProjectRoot(String)
  case projectNotFound(String)
  case fileReadFailed(String)
  case invalidRequest(String)
  case invalidResponse(String)
  case projectStructureUnavailable(String)
  case manifestEvaluationFailed(String)
  case targetNotFound(String)
  case targetSourceUnavailable(String)
  case accessFilterUnsupported(String)

  /// Stable case name used to carry the error across the JSON-RPC boundary.
  public var kind: String {
    switch self {
    case .unsupportedLanguage: "unsupportedLanguage"
    case .invalidProjectRoot: "invalidProjectRoot"
    case .projectNotFound: "projectNotFound"
    case .fileReadFailed: "fileReadFailed"
    case .invalidRequest: "invalidRequest"
    case .invalidResponse: "invalidResponse"
    case .projectStructureUnavailable: "projectStructureUnavailable"
    case .manifestEvaluationFailed: "manifestEvaluationFailed"
    case .targetNotFound: "targetNotFound"
    case .targetSourceUnavailable: "targetSourceUnavailable"
    case .accessFilterUnsupported: "accessFilterUnsupported"
    }
  }

  public var detail: String {
    switch self {
    case .unsupportedLanguage(let detail), .invalidProjectRoot(let detail),
      .projectNotFound(let detail), .fileReadFailed(let detail), .invalidRequest(let detail),
      .invalidResponse(let detail), .projectStructureUnavailable(let detail),
      .manifestEvaluationFailed(let detail), .targetNotFound(let detail),
      .targetSourceUnavailable(let detail), .accessFilterUnsupported(let detail):
      detail
    }
  }

  /// Reconstructs an error from its `kind` and `detail`; nil for an unknown kind.
  public init?(kind: String, detail: String) {
    switch kind {
    case "unsupportedLanguage": self = .unsupportedLanguage(detail)
    case "invalidProjectRoot": self = .invalidProjectRoot(detail)
    case "projectNotFound": self = .projectNotFound(detail)
    case "fileReadFailed": self = .fileReadFailed(detail)
    case "invalidRequest": self = .invalidRequest(detail)
    case "invalidResponse": self = .invalidResponse(detail)
    case "projectStructureUnavailable": self = .projectStructureUnavailable(detail)
    case "manifestEvaluationFailed": self = .manifestEvaluationFailed(detail)
    case "targetNotFound": self = .targetNotFound(detail)
    case "targetSourceUnavailable": self = .targetSourceUnavailable(detail)
    case "accessFilterUnsupported": self = .accessFilterUnsupported(detail)
    default: return nil
    }
  }
}

extension SkeletonError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unsupportedLanguage(let detail): "unsupported language: \(detail)"
    case .invalidProjectRoot(let detail): "project root is not a directory: \(detail)"
    case .projectNotFound(let detail): "project not found: \(detail)"
    case .fileReadFailed(let detail): "failed to read file: \(detail)"
    case .invalidRequest(let detail): "invalid request: \(detail)"
    case .invalidResponse(let detail): "invalid response: \(detail)"
    case .projectStructureUnavailable(let detail): "no project structure found for: \(detail)"
    case .manifestEvaluationFailed(let detail): "manifest evaluation failed: \(detail)"
    case .targetNotFound(let detail): "target not found: \(detail)"
    case .targetSourceUnavailable(let detail): "target has no indexable sources: \(detail)"
    case .accessFilterUnsupported(let detail):
      "access filtering is unsupported for languages: \(detail)"
    }
  }
}

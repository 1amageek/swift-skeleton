import Foundation

public enum SkeletonError: Error, Sendable {
    case unsupportedLanguage(String)
    case invalidProjectRoot(String)
    case projectNotFound(String)
    case fileReadFailed(String)
    case invalidRequest(String)
    case invalidResponse(String)
}

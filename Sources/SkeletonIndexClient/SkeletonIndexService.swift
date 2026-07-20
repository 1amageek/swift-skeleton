import Foundation
import SkeletonIndexCore

public protocol SkeletonIndexService: Sendable {
  func open(projectRoot: String, languages: [String]) async throws -> OpenResult
  func open(projectRoot: String, languages: [String], targetName: String?) async throws
    -> OpenResult
  func status(projectID: String) async throws -> IndexStatus
  func getSkeleton(projectID: String, path: String?) async throws -> SkeletonTextResult
  func getSkeleton(
    projectID: String,
    path: String?,
    options: SkeletonRenderOptions
  ) async throws -> SkeletonTextResult
  func update(projectID: String, changedPaths: [String], removedPaths: [String]) async throws
    -> IndexStatus
  func query(projectID: String, q: String, limit: Int) async throws -> [QueryHit]
  func diagnostics(projectID: String) async throws -> IndexDiagnostics
}

import Foundation
import SkeletonIndexCore

public final actor EmbeddedService: SkeletonIndexService {
  private let registry: SkeletonProjectRegistry

  public init(
    parsers: [any SkeletonParser],
    projectStructureResolvers: [any ProjectStructureResolving] = []
  ) {
    let core = SkeletonIndexCore(
      parsers: parsers,
      projectStructureResolvers: projectStructureResolvers
    )
    self.registry = SkeletonProjectRegistry(core: core)
  }

  public func open(projectRoot: String, languages: [String]) async throws -> OpenResult {
    try await registry.open(projectRoot: projectRoot, languages: languages)
  }

  public func open(
    projectRoot: String,
    languages: [String],
    targetName: String?
  ) async throws -> OpenResult {
    try await registry.open(
      projectRoot: projectRoot,
      languages: languages,
      targetName: targetName
    )
  }

  public func status(projectID: String) async throws -> IndexStatus {
    try await registry.status(projectID: projectID)
  }

  public func getSkeleton(projectID: String, path: String?) async throws -> SkeletonTextResult {
    try await registry.getSkeleton(projectID: projectID, path: path)
  }

  public func getSkeleton(
    projectID: String,
    path: String?,
    options: SkeletonRenderOptions
  ) async throws -> SkeletonTextResult {
    try await registry.getSkeleton(projectID: projectID, path: path, options: options)
  }

  public func update(
    projectID: String,
    changedPaths: [String],
    removedPaths: [String]
  ) async throws -> IndexStatus {
    try await registry.update(
      projectID: projectID, changedPaths: changedPaths, removedPaths: removedPaths)
  }

  public func query(projectID: String, q: String, limit: Int) async throws -> [QueryHit] {
    try await registry.query(projectID: projectID, q: q, limit: limit)
  }

  public func diagnostics(projectID: String) async throws -> IndexDiagnostics {
    try await registry.diagnostics(projectID: projectID)
  }
}

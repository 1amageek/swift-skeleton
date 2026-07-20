import Foundation

public actor SkeletonProjectRegistry {
  private let core: SkeletonIndexCore
  private var projects: [String: ProjectIndex]

  public init(core: SkeletonIndexCore) {
    self.core = core
    self.projects = [:]
  }

  public func open(projectRoot: String, languages: [String]) throws -> OpenResult {
    try open(projectRoot: projectRoot, languages: languages, targetName: nil)
  }

  public func open(
    projectRoot: String,
    languages: [String],
    targetName: String?
  ) throws -> OpenResult {
    let index = try core.build(
      projectRoot: projectRoot,
      languages: languages,
      targetName: targetName
    )
    let projectID = UUID().uuidString.lowercased()
    projects[projectID] = index
    return OpenResult(projectID: projectID, status: core.status(index: index))
  }

  public func status(projectID: String) throws -> IndexStatus {
    guard let index = projects[projectID] else {
      throw SkeletonError.projectNotFound(projectID)
    }
    return core.status(index: index)
  }

  public func getSkeleton(projectID: String, path: String?) throws -> SkeletonTextResult {
    try getSkeleton(projectID: projectID, path: path, options: .default)
  }

  public func getSkeleton(
    projectID: String,
    path: String?,
    options: SkeletonRenderOptions
  ) throws -> SkeletonTextResult {
    guard let index = projects[projectID] else {
      throw SkeletonError.projectNotFound(projectID)
    }
    try core.validateRender(index: index, accessBoundary: options.accessBoundary)
    return core.getSkeleton(index: index, path: path, options: options)
  }

  public func update(
    projectID: String,
    changedPaths: [String],
    removedPaths: [String]
  ) throws -> IndexStatus {
    guard var index = projects[projectID] else {
      throw SkeletonError.projectNotFound(projectID)
    }
    let status = try core.update(
      index: &index, changedPaths: changedPaths, removedPaths: removedPaths)
    projects[projectID] = index
    return status
  }

  public func query(projectID: String, q: String, limit: Int) throws -> [QueryHit] {
    guard let index = projects[projectID] else {
      throw SkeletonError.projectNotFound(projectID)
    }
    return core.query(index: index, q: q, limit: limit)
  }

  public func diagnostics(projectID: String) throws -> IndexDiagnostics {
    guard let index = projects[projectID] else {
      throw SkeletonError.projectNotFound(projectID)
    }
    return core.diagnostics(index: index)
  }
}

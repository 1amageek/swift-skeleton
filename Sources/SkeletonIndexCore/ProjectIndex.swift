public struct ProjectIndex: Sendable {
  public let projectRoot: String
  public var files: [String: ParsedFile]
  public var lastUpdateTS: String
  public var isWatching: Bool
  public let projectStructure: ProjectStructure?
  public let focusUnitID: String?
  public let dependencyUnitIDs: [String]
  public let fileUnitIDs: [String: String]

  public init(
    projectRoot: String,
    files: [String: ParsedFile],
    lastUpdateTS: String,
    isWatching: Bool,
    projectStructure: ProjectStructure? = nil,
    focusUnitID: String? = nil,
    dependencyUnitIDs: [String] = [],
    fileUnitIDs: [String: String] = [:]
  ) {
    self.projectRoot = projectRoot
    self.files = files
    self.lastUpdateTS = lastUpdateTS
    self.isWatching = isWatching
    self.projectStructure = projectStructure
    self.focusUnitID = focusUnitID
    self.dependencyUnitIDs = dependencyUnitIDs
    self.fileUnitIDs = fileUnitIDs
  }
}

public enum ProjectUnitKind: String, Sendable, Equatable, Codable {
  case regular
  case executable
  case test
  case macro
  case plugin
  case system
  case binary
  case unknown
}

public struct ProjectUnitDependency: Sendable, Equatable, Codable {
  public let name: String
  public let localUnitID: String?

  public init(name: String, localUnitID: String?) {
    self.name = name
    self.localUnitID = localUnitID
  }
}

public struct ProjectUnit: Sendable, Equatable, Codable {
  public let id: String
  public let name: String
  public let moduleName: String
  public let displayKind: String
  public let kind: ProjectUnitKind
  public let sourceRoots: [String]
  public let dependencies: [ProjectUnitDependency]

  public init(
    id: String,
    name: String,
    moduleName: String,
    displayKind: String,
    kind: ProjectUnitKind,
    sourceRoots: [String],
    dependencies: [ProjectUnitDependency]
  ) {
    self.id = id
    self.name = name
    self.moduleName = moduleName
    self.displayKind = displayKind
    self.kind = kind
    self.sourceRoots = sourceRoots
    self.dependencies = dependencies
  }
}

public struct ProjectStructure: Sendable, Equatable, Codable {
  public let projectRoot: String
  public let packageIdentity: String
  public let units: [ProjectUnit]

  public init(projectRoot: String, packageIdentity: String, units: [ProjectUnit]) {
    self.projectRoot = projectRoot
    self.packageIdentity = packageIdentity
    self.units = units
  }

  public func unit(named name: String) -> ProjectUnit? {
    units.first { $0.name == name || $0.moduleName == name }
  }

  public func unit(id: String) -> ProjectUnit? {
    units.first { $0.id == id }
  }
}

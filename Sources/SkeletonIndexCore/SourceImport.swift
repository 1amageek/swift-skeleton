public struct SourceImport: Sendable, Equatable, Codable {
  public let moduleName: String
  public let access: AccessScope?
  public let isTestable: Bool
  public let isReexported: Bool
  public let spiGroups: [String]
  public let range: SourceRange

  public init(
    moduleName: String,
    access: AccessScope? = nil,
    isTestable: Bool = false,
    isReexported: Bool = false,
    spiGroups: [String] = [],
    range: SourceRange
  ) {
    self.moduleName = moduleName
    self.access = access
    self.isTestable = isTestable
    self.isReexported = isReexported
    self.spiGroups = spiGroups
    self.range = range
  }
}

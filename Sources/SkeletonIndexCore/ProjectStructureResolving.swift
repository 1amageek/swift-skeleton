public protocol ProjectStructureResolving: Sendable {
  func resolve(scopeRoot: String) throws -> ProjectStructure?
}

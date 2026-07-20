public struct MethodSignature: Sendable, Equatable {
  public let name: String
  public let parameterTypeRefs: [String]
  public let returnTypeRef: String?
  public let range: SourceRange
  public let isInitializer: Bool
  public let access: DeclarationAccess

  public init(
    name: String,
    parameterTypeRefs: [String],
    returnTypeRef: String?,
    range: SourceRange,
    isInitializer: Bool,
    access: DeclarationAccess = .unknown
  ) {
    self.name = name
    self.parameterTypeRefs = parameterTypeRefs
    self.returnTypeRef = returnTypeRef
    self.range = range
    self.isInitializer = isInitializer
    self.access = access
  }
}

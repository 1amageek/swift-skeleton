public struct PropertySignature: Sendable, Equatable {
  public let name: String
  public let typeRef: String
  public let range: SourceRange
  public let access: DeclarationAccess

  public init(
    name: String,
    typeRef: String,
    range: SourceRange = SourceRange(startLine: nil, endLine: nil),
    access: DeclarationAccess = .unknown
  ) {
    self.name = name
    self.typeRef = typeRef
    self.range = range
    self.access = access
  }
}

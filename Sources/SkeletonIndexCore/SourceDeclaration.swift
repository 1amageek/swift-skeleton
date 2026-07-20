public enum SourceDeclarationKind: String, Sendable, Equatable, Codable {
  case function
  case variable
  case typealiasDeclaration
  case associatedType
  case enumCase
  case subscriptDeclaration
  case operatorDeclaration
  case macro
}

public struct SourceDeclaration: Sendable, Equatable, Codable {
  public let kind: SourceDeclarationKind
  public let signature: String
  public let range: SourceRange
  public let access: DeclarationAccess

  public init(
    kind: SourceDeclarationKind,
    signature: String,
    range: SourceRange,
    access: DeclarationAccess
  ) {
    self.kind = kind
    self.signature = signature
    self.range = range
    self.access = access
  }
}

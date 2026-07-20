public struct SkeletonBlock: Sendable, Equatable {
  public let kind: SkeletonBlockKind
  public let typeName: String
  public let inheritance: [String]
  public let range: SourceRange
  public let properties: [PropertySignature]
  public let methods: [MethodSignature]
  public let declarations: [SourceDeclaration]
  public let hasErrorNode: Bool
  public let access: DeclarationAccess

  public init(
    kind: SkeletonBlockKind,
    typeName: String,
    inheritance: [String],
    range: SourceRange,
    properties: [PropertySignature],
    methods: [MethodSignature],
    hasErrorNode: Bool,
    access: DeclarationAccess = .unknown,
    declarations: [SourceDeclaration] = []
  ) {
    self.kind = kind
    self.typeName = typeName
    self.inheritance = inheritance
    self.range = range
    self.properties = properties
    self.methods = methods
    self.declarations = declarations
    self.hasErrorNode = hasErrorNode
    self.access = access
  }
}

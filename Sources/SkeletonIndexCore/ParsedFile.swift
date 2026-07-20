public struct ParsedFile: Sendable, Equatable {
  public let path: String
  public let blocks: [SkeletonBlock]
  public let hasParseError: Bool
  public let methodSyntaxEvidence: [MethodSyntaxEvidence]
  public let implementationAnalysis: FileImplementationAnalysis
  public let languageName: String
  public let imports: [SourceImport]
  public let declarations: [SourceDeclaration]

  public init(
    path: String,
    blocks: [SkeletonBlock],
    hasParseError: Bool,
    methodSyntaxEvidence: [MethodSyntaxEvidence] = [],
    implementationAnalysis: FileImplementationAnalysis = .empty,
    languageName: String = "unknown",
    imports: [SourceImport] = [],
    declarations: [SourceDeclaration] = []
  ) {
    self.path = path
    self.blocks = blocks
    self.hasParseError = hasParseError
    self.methodSyntaxEvidence = methodSyntaxEvidence
    self.implementationAnalysis = implementationAnalysis
    self.languageName = languageName
    self.imports = imports
    self.declarations = declarations
  }

  public func replacing(implementationAnalysis: FileImplementationAnalysis) -> ParsedFile {
    ParsedFile(
      path: path,
      blocks: blocks,
      hasParseError: hasParseError,
      methodSyntaxEvidence: methodSyntaxEvidence,
      implementationAnalysis: implementationAnalysis,
      languageName: languageName,
      imports: imports,
      declarations: declarations
    )
  }

  public func replacing(languageName: String) -> ParsedFile {
    ParsedFile(
      path: path,
      blocks: blocks,
      hasParseError: hasParseError,
      methodSyntaxEvidence: methodSyntaxEvidence,
      implementationAnalysis: implementationAnalysis,
      languageName: languageName,
      imports: imports,
      declarations: declarations
    )
  }
}

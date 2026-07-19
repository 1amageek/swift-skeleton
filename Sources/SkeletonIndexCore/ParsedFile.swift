public struct ParsedFile: Sendable, Equatable {
    public let path: String
    public let blocks: [SkeletonBlock]
    public let hasParseError: Bool
    public let methodSyntaxEvidence: [MethodSyntaxEvidence]
    public let implementationAnalysis: FileImplementationAnalysis

    public init(
        path: String,
        blocks: [SkeletonBlock],
        hasParseError: Bool,
        methodSyntaxEvidence: [MethodSyntaxEvidence] = [],
        implementationAnalysis: FileImplementationAnalysis = .empty
    ) {
        self.path = path
        self.blocks = blocks
        self.hasParseError = hasParseError
        self.methodSyntaxEvidence = methodSyntaxEvidence
        self.implementationAnalysis = implementationAnalysis
    }

    public func replacing(implementationAnalysis: FileImplementationAnalysis) -> ParsedFile {
        ParsedFile(
            path: path,
            blocks: blocks,
            hasParseError: hasParseError,
            methodSyntaxEvidence: methodSyntaxEvidence,
            implementationAnalysis: implementationAnalysis
        )
    }
}

public struct ParsedFile: Sendable, Equatable {
    public let path: String
    public let blocks: [SkeletonBlock]
    public let hasParseError: Bool
    public let implementationAnalysis: FileImplementationAnalysis

    public init(
        path: String,
        blocks: [SkeletonBlock],
        hasParseError: Bool,
        implementationAnalysis: FileImplementationAnalysis = .empty
    ) {
        self.path = path
        self.blocks = blocks
        self.hasParseError = hasParseError
        self.implementationAnalysis = implementationAnalysis
    }

    public func replacing(implementationAnalysis: FileImplementationAnalysis) -> ParsedFile {
        ParsedFile(
            path: path,
            blocks: blocks,
            hasParseError: hasParseError,
            implementationAnalysis: implementationAnalysis
        )
    }
}

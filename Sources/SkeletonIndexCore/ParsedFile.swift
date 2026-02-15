public struct ParsedFile: Sendable, Equatable {
    public let path: String
    public let blocks: [SkeletonBlock]
    public let hasParseError: Bool

    public init(path: String, blocks: [SkeletonBlock], hasParseError: Bool) {
        self.path = path
        self.blocks = blocks
        self.hasParseError = hasParseError
    }
}

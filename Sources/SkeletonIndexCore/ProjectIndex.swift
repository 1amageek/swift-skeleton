public struct ProjectIndex: Sendable {
    public let projectRoot: String
    public var files: [String: ParsedFile]
    public var lastUpdateTS: String
    public var isWatching: Bool

    public init(projectRoot: String, files: [String: ParsedFile], lastUpdateTS: String, isWatching: Bool) {
        self.projectRoot = projectRoot
        self.files = files
        self.lastUpdateTS = lastUpdateTS
        self.isWatching = isWatching
    }
}

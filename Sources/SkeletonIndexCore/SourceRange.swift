public struct SourceRange: Sendable, Equatable, Codable {
    public let startLine: Int?
    public let endLine: Int?

    public init(startLine: Int?, endLine: Int?) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

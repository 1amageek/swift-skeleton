public struct DeclarationNode: Sendable {
    public let snippet: String
    public let startLine: Int
    public let endLine: Int?
    public let hasError: Bool

    public init(snippet: String, startLine: Int, endLine: Int?, hasError: Bool) {
        self.snippet = snippet
        self.startLine = startLine
        self.endLine = endLine
        self.hasError = hasError
    }
}

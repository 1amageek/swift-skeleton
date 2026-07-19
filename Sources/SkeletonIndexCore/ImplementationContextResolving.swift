public protocol ImplementationContextResolving: Sendable {
    func resolve(
        files: [String: ParsedFile],
        sources: [String: String]
    ) -> [String: ParsedFile]
}

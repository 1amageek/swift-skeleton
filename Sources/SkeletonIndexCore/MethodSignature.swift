public struct MethodSignature: Sendable, Equatable {
    public let name: String
    public let parameterTypeRefs: [String]
    public let returnTypeRef: String?
    public let range: SourceRange
    public let isInitializer: Bool

    public init(
        name: String,
        parameterTypeRefs: [String],
        returnTypeRef: String?,
        range: SourceRange,
        isInitializer: Bool
    ) {
        self.name = name
        self.parameterTypeRefs = parameterTypeRefs
        self.returnTypeRef = returnTypeRef
        self.range = range
        self.isInitializer = isInitializer
    }
}

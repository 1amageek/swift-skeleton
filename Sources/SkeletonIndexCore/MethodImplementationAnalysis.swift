public struct MethodImplementationAnalysis: Sendable, Equatable, Codable {
    public let typeName: String
    public let methodName: String
    public let range: SourceRange
    public let isInitializer: Bool
    public let fingerprint: ImplementationFingerprint

    public init(
        typeName: String,
        methodName: String,
        range: SourceRange,
        isInitializer: Bool,
        fingerprint: ImplementationFingerprint
    ) {
        self.typeName = typeName
        self.methodName = methodName
        self.range = range
        self.isInitializer = isInitializer
        self.fingerprint = fingerprint
    }

    public func resolving(fingerprint: ImplementationFingerprint) -> MethodImplementationAnalysis {
        MethodImplementationAnalysis(
            typeName: typeName,
            methodName: methodName,
            range: range,
            isInitializer: isInitializer,
            fingerprint: fingerprint
        )
    }
}

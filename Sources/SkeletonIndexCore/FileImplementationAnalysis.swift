public struct FileImplementationAnalysis: Sendable, Equatable, Codable {
    public let language: String
    public let methods: [MethodImplementationAnalysis]
    public let findings: [ImplementationFinding]

    public init(
        language: String,
        methods: [MethodImplementationAnalysis],
        findings: [ImplementationFinding]
    ) {
        self.language = language
        self.methods = methods
        self.findings = findings
    }

    public static let empty = FileImplementationAnalysis(language: "", methods: [], findings: [])
}

public protocol ImplementationAnalyzing: Sendable {
    func analyze(
        path: String,
        blocks: [SkeletonBlock],
        source: String,
        language: String
    ) -> FileImplementationAnalysis
}

public protocol ImplementationAnalyzing: Sendable {
    func analyze(
        path: String,
        blocks: [SkeletonBlock],
        source: String,
        language: String
    ) -> FileImplementationAnalysis

    func analyze(
        path: String,
        blocks: [SkeletonBlock],
        source: String,
        language: String,
        syntaxEvidence: [MethodSyntaxEvidence]
    ) -> FileImplementationAnalysis
}

public extension ImplementationAnalyzing {
    func analyze(
        path: String,
        blocks: [SkeletonBlock],
        source: String,
        language: String,
        syntaxEvidence: [MethodSyntaxEvidence]
    ) -> FileImplementationAnalysis {
        analyze(path: path, blocks: blocks, source: source, language: language)
    }
}

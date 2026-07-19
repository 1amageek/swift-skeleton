import Foundation

public struct SkeletonFormatter: Sendable {
    public init() {}

    public func render(index: ProjectIndex, path: String? = nil) -> SkeletonTextResult {
        let selectedPaths: [String]
        if let path {
            selectedPaths = index.files.keys.filter { $0 == path }.sorted()
        } else {
            selectedPaths = index.files.keys.sorted()
        }

        var lines: [String] = []
        var hasErrors = false

        for filePath in selectedPaths {
            guard let parsedFile = index.files[filePath] else {
                continue
            }
            let fileLines = render(path: filePath, parsedFile: parsedFile)
            hasErrors = hasErrors || fileLines.hasErrors
            lines.append(fileLines.text)
        }

        return SkeletonTextResult(
            text: lines.filter { !$0.isEmpty }.joined(separator: "\n"),
            hasErrors: hasErrors
        )
    }

    public func header(for block: SkeletonBlock, filePath: String) -> String {
        header(for: block, filePath: filePath, findings: [])
    }

    public func header(
        for block: SkeletonBlock,
        filePath: String,
        findings: [ImplementationFinding]
    ) -> String {
        let inheritance = block.inheritance.isEmpty ? "" : ": \(block.inheritance.joined(separator: ", "))"
        let rangeText = "\(lineNumber(block.range.startLine))-\(lineNumber(block.range.endLine))"
        let base: String

        switch block.kind {
        case .type(let keyword):
            base = "\(keyword) \(block.typeName)\(inheritance) [\(filePath):\(rangeText)]"
        case .extension:
            base = "extension \(block.typeName)\(inheritance) [\(filePath):\(rangeText)]"
        }
        let parseMarker = block.hasErrorNode ? " (!)" : ""
        let implementationMarker = blockImplementationMarker(block: block, findings: findings)
        return base + parseMarker + implementationMarker
    }

    private func render(path: String, parsedFile: ParsedFile) -> SkeletonTextResult {
        var lines: [String] = []
        var hasErrors = parsedFile.hasParseError

        if parsedFile.hasParseError {
            lines.append("# parse_error \(path)")
        }

        for block in parsedFile.blocks {
            if block.hasErrorNode {
                hasErrors = true
            }
            let blockFindings = findings(for: block, in: parsedFile.implementationAnalysis.findings)
            lines.append(header(for: block, filePath: path, findings: blockFindings))

            if !block.properties.isEmpty {
                let props = block.properties
                    .map { "\($0.name):\($0.typeRef)" }
                    .joined(separator: ", ")
                lines.append("  props: \(props)")
            }

            if !block.methods.isEmpty {
                lines.append("  methods:")
                for method in block.methods {
                    let params = method.parameterTypeRefs.joined(separator: ", ")
                    let methodRange = "\(lineNumber(method.range.startLine))-\(lineNumber(method.range.endLine))"
                    let marker = primaryMethodFinding(
                        method: method,
                        block: block,
                        findings: blockFindings
                    ).map { " \($0.marker)" } ?? ""
                    if method.isInitializer {
                        lines.append("    init(\(params)) [\(methodRange)]\(marker)")
                    } else if let returnTypeRef = method.returnTypeRef {
                        lines.append("    \(method.name)(\(params)) -> \(returnTypeRef) [\(methodRange)]\(marker)")
                    } else {
                        lines.append("    \(method.name)(\(params)) [\(methodRange)]\(marker)")
                    }
                }
            }
        }

        return SkeletonTextResult(
            text: lines.joined(separator: "\n"),
            hasErrors: hasErrors
        )
    }

    private func lineNumber(_ value: Int?) -> String {
        guard let value else {
            return "?"
        }
        return String(value)
    }

    private func findings(
        for block: SkeletonBlock,
        in findings: [ImplementationFinding]
    ) -> [ImplementationFinding] {
        findings.filter { finding in
            guard finding.typeName == block.typeName else {
                return false
            }
            guard let blockStart = block.range.startLine,
                  let findingStart = finding.range.startLine else {
                return true
            }
            let blockEnd = block.range.endLine ?? Int.max
            let findingEnd = finding.range.endLine ?? findingStart
            return findingStart >= blockStart && findingEnd <= blockEnd
        }
    }

    private func blockImplementationMarker(
        block: SkeletonBlock,
        findings: [ImplementationFinding]
    ) -> String {
        let blockFindings = self.findings(for: block, in: findings)
        let domains = ImplementationFinding.Domain.allCases.filter { domain in
            blockFindings.contains { $0.domain == domain }
        }
        guard !domains.isEmpty else {
            return ""
        }
        return " [impl:\(domains.map(\.rawValue).joined(separator: ","))]"
    }

    private func primaryMethodFinding(
        method: MethodSignature,
        block: SkeletonBlock,
        findings: [ImplementationFinding]
    ) -> ImplementationFinding? {
        findings
            .filter {
                $0.scope == .method &&
                    $0.typeName == block.typeName &&
                    $0.methodName == method.name &&
                    $0.range == method.range
            }
            .sorted { findingPriority($0) < findingPriority($1) }
            .first
    }

    private func findingPriority(_ finding: ImplementationFinding) -> Int {
        let certaintyOffset = finding.certainty == .definite ? 0 : 100
        let reasonPriority: [ImplementationFinding.Reason: Int] = [
            .trap: 0,
            .empty: 1,
            .wire: 2,
            .error: 3,
            .constant: 4,
            .noOperation: 5,
            .flow: 6,
            .dead: 7,
        ]
        return certaintyOffset + (reasonPriority[finding.reason] ?? 99)
    }
}

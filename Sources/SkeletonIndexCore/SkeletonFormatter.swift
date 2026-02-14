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
        let inheritance = block.inheritance.isEmpty ? "" : ": \(block.inheritance.joined(separator: ", "))"
        let rangeText = "\(lineNumber(block.range.startLine))-\(lineNumber(block.range.endLine))"
        let base: String

        switch block.kind {
        case .type(let keyword):
            base = "\(keyword.rawValue) \(block.typeName)\(inheritance) [\(filePath):\(rangeText)]"
        case .extension:
            base = "extension \(block.typeName)\(inheritance) [\(filePath):\(rangeText)]"
        }
        return block.hasErrorNode ? "\(base) (!)" : base
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
            lines.append(header(for: block, filePath: path))

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
                    if method.isInitializer {
                        lines.append("    init(\(params)) [\(methodRange)]")
                    } else if let returnTypeRef = method.returnTypeRef {
                        lines.append("    \(method.name)(\(params)) -> \(returnTypeRef) [\(methodRange)]")
                    } else {
                        lines.append("    \(method.name)(\(params)) [\(methodRange)]")
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
}

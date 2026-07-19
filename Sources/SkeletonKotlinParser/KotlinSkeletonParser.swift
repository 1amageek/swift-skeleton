import Foundation
import SwiftTreeSitter
import TreeSitterKotlinGrammar
import SkeletonIndexCore
import SkeletonTreeSitterSupport

public struct KotlinSkeletonParser: SkeletonParser, Sendable {
    public var languageName: String { "kotlin" }
    public var supportedExtensions: Set<String> { ["kt", "kts"] }

    private static let rules = KotlinLanguageRules()
    private static let extractor = DeclarationExtractor(rules: rules)

    public init() {}

    public func parse(path: String, source: String) -> ParsedFile {
        let parser = Parser()
        do {
            guard let languagePointer = tree_sitter_kotlin() else {
                return ParsedFile(path: path, blocks: [], hasParseError: true)
            }
            let language = Language(languagePointer)
            try parser.setLanguage(language)
        } catch {
            return ParsedFile(path: path, blocks: [], hasParseError: true)
        }

        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return ParsedFile(path: path, blocks: [], hasParseError: true)
        }

        let nodes = collectDeclarationNodes(from: root, source: source)
        let blocks = nodes.compactMap { Self.extractor.extract(from: $0) }

        let evidence = TreeSitterImplementationEvidenceExtractor().extract(
            root: root, source: source, blocks: blocks, language: languageName
        )
        return ParsedFile(
            path: path, blocks: blocks, hasParseError: root.hasError, methodSyntaxEvidence: evidence
        )
    }

    private static let declarationTypes: Set<String> = [
        "class_declaration",
        "object_declaration",
        "interface_declaration",
    ]

    private func collectDeclarationNodes(from node: Node, source: String) -> [DeclarationNode] {
        var results: [DeclarationNode] = []
        walkDeclarations(from: node, source: source, into: &results)
        return results
    }

    private func walkDeclarations(from node: Node, source: String, into results: inout [DeclarationNode]) {
        if let nodeType = node.nodeType {
            if Self.declarationTypes.contains(nodeType) {
                let snippet = nodeText(node: node, source: source)
                let startLine = Int(node.pointRange.lowerBound.row) + 1
                let hasMissingClosingBrace = node.hasError && !snippet.contains("}")
                let endLine = hasMissingClosingBrace ? nil : Int(node.pointRange.upperBound.row) + 1

                results.append(DeclarationNode(
                    snippet: snippet,
                    startLine: startLine,
                    endLine: endLine,
                    hasError: node.hasError
                ))
            }
        }

        for childIndex in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: childIndex) else { continue }
            walkDeclarations(from: child, source: source, into: &results)
        }
    }

    private func nodeText(node: Node, source: String) -> String {
        let lowerUnits = max(0, Int(node.byteRange.lowerBound / 2))
        let upperUnits = max(lowerUnits, Int(node.byteRange.upperBound / 2))
        let clampedLower = min(lowerUnits, source.utf16.count)
        let clampedUpper = min(upperUnits, source.utf16.count)
        let start = String.Index(utf16Offset: clampedLower, in: source)
        let end = String.Index(utf16Offset: clampedUpper, in: source)
        return String(source[start..<end])
    }
}

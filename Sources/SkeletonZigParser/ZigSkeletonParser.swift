import Foundation
import SwiftTreeSitter
import TreeSitterZigGrammar
import SkeletonIndexCore
import SkeletonTreeSitterSupport

public struct ZigSkeletonParser: SkeletonParser, Sendable {
    public var languageName: String { "zig" }
    public var supportedExtensions: Set<String> { ["zig"] }

    public init() {}

    public func parse(path: String, source: String) -> ParsedFile {
        let parser = Parser()
        do {
            guard let languagePointer = tree_sitter_zig() else {
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

        var blocks: [SkeletonBlock] = []
        collectBlocks(from: root, source: source, into: &blocks)

        let evidence = TreeSitterImplementationEvidenceExtractor().extract(
            root: root, source: source, blocks: blocks, language: languageName
        )
        return ParsedFile(
            path: path, blocks: blocks, hasParseError: root.hasError, methodSyntaxEvidence: evidence
        )
    }

    private static let containerKinds: [String: String] = [
        "struct_declaration": "struct",
        "enum_declaration": "enum",
        "union_declaration": "union",
        "opaque_declaration": "opaque",
    ]

    /// Walks the tree in source order. A `variable_declaration` whose value node is a container
    /// declaration becomes a block, and its container is walked again so nested containers are
    /// emitted as their own blocks after their parent.
    private func collectBlocks(from node: Node, source: String, into blocks: inout [SkeletonBlock]) {
        for child in namedChildren(of: node) {
            if child.nodeType == "variable_declaration",
               let (container, kind) = containerValue(of: child) {
                if let block = extractContainer(declaration: child, container: container, kind: kind, source: source) {
                    blocks.append(block)
                }
                collectBlocks(from: container, source: source, into: &blocks)
                continue
            }
            collectBlocks(from: child, source: source, into: &blocks)
        }
    }

    /// Returns the container declaration that is the direct value of `declaration`.
    /// Containers nested inside other expressions are not the declared value.
    private func containerValue(of declaration: Node) -> (container: Node, kind: String)? {
        for child in namedChildren(of: declaration) {
            if let nodeType = child.nodeType, let kind = Self.containerKinds[nodeType] {
                return (child, kind)
            }
        }
        return nil
    }

    private func extractContainer(declaration: Node, container: Node, kind: String, source: String) -> SkeletonBlock? {
        guard let nameNode = namedChildren(of: declaration).first(where: { $0.nodeType == "identifier" }) else {
            return nil
        }
        let name = nodeText(node: nameNode, source: source)
        guard !name.isEmpty else { return nil }

        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []
        for member in namedChildren(of: container) {
            switch member.nodeType {
            case "container_field":
                if let property = extractField(node: member, source: source) {
                    properties.append(property)
                }
            case "function_declaration":
                if let method = extractFunction(node: member, source: source) {
                    methods.append(method)
                }
            default:
                continue
            }
        }

        let endLine = isClosingBraceMissing(container) ? nil : endLine(of: declaration)
        return SkeletonBlock(
            kind: .type(kind),
            typeName: name,
            inheritance: [],
            range: SourceRange(startLine: startLine(of: declaration), endLine: endLine),
            properties: properties,
            methods: methods,
            hasErrorNode: declaration.hasError
        )
    }

    /// Only typed container fields become props; enum tags without a type are omitted.
    private func extractField(node: Node, source: String) -> PropertySignature? {
        guard let nameNode = node.child(byFieldName: "name"),
              let typeNode = node.child(byFieldName: "type")
        else { return nil }
        let name = nodeText(node: nameNode, source: source)
        let typeRef = compactText(node: typeNode, source: source)
        guard !name.isEmpty, !typeRef.isEmpty else { return nil }
        return PropertySignature(name: name, typeRef: typeRef)
    }

    private func extractFunction(node: Node, source: String) -> MethodSignature? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nodeText(node: nameNode, source: source)
        guard !name.isEmpty else { return nil }

        var parameterTypes: [String] = []
        if let parameters = namedChildren(of: node).first(where: { $0.nodeType == "parameters" }) {
            for parameter in namedChildren(of: parameters) where parameter.nodeType == "parameter" {
                guard let typeNode = parameter.child(byFieldName: "type") else {
                    parameterTypes.append("?")
                    continue
                }
                let typeRef = compactText(node: typeNode, source: source)
                // Receiver parameters typed as `Self` / `*Self` are omitted.
                if typeRef.hasSuffix("Self") { continue }
                parameterTypes.append(typeRef)
            }
        }

        let returnType = node.child(byFieldName: "type").map { compactText(node: $0, source: source) }

        return MethodSignature(
            name: name,
            parameterTypeRefs: parameterTypes,
            returnTypeRef: returnType?.isEmpty == false ? returnType : nil,
            range: SourceRange(startLine: startLine(of: node), endLine: endLine(of: node)),
            isInitializer: name == "init"
        )
    }

    private func isClosingBraceMissing(_ container: Node) -> Bool {
        for index in stride(from: container.childCount - 1, through: 0, by: -1) {
            guard let child = container.child(at: index) else { continue }
            if child.nodeType == "}" {
                return child.isMissing
            }
        }
        return true
    }

    private func namedChildren(of node: Node) -> [Node] {
        (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
    }

    private func startLine(of node: Node) -> Int {
        Int(node.pointRange.lowerBound.row) + 1
    }

    private func endLine(of node: Node) -> Int {
        Int(node.pointRange.upperBound.row) + 1
    }

    /// Materializes a short signature fragment (a type reference) with whitespace runs
    /// collapsed, so multi-line types render on one skeleton line.
    private func compactText(node: Node, source: String) -> String {
        nodeText(node: node, source: source)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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

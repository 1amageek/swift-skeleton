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

    private static let containerTypes: Set<String> = [
        "struct_declaration", "enum_declaration", "union_declaration",
    ]

    private func collectBlocks(from node: Node, source: String, into blocks: inout [SkeletonBlock]) {
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            if childType == "variable_declaration" {
                if let block = extractContainerFromVarDecl(node: child, source: source) {
                    blocks.append(block)
                    continue
                }
            }

            let snippet = nodeText(node: child, source: source)
            if snippet.contains("= struct") || snippet.contains("= enum") || snippet.contains("= union") {
                if let block = extractFromSnippetFallback(node: child, source: source) {
                    blocks.append(block)
                    continue
                }
            }

            collectBlocks(from: child, source: source, into: &blocks)
        }
    }

    private func extractContainerFromVarDecl(node: Node, source: String) -> SkeletonBlock? {
        var containerNode: Node?
        var kind: String?
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i), let ct = child.nodeType else { continue }
            if ct == "struct_declaration" { containerNode = child; kind = "struct"; break }
            if ct == "enum_declaration"   { containerNode = child; kind = "enum"; break }
            if ct == "union_declaration"  { containerNode = child; kind = "union"; break }
        }

        if containerNode == nil {
            return extractFromSnippetFallback(node: node, source: source)
        }

        let varText = nodeText(node: node, source: source)
        let namePattern = #"(?:pub\s+)?(?:const\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*="#
        guard let name = TextUtilities.firstRegex(pattern: namePattern, in: varText) else { return nil }

        let startLine = Int(node.pointRange.lowerBound.row) + 1

        let (properties, methods) = extractMembersFromContainer(
            containerNode: containerNode!, source: source, baseLine: startLine
        )

        let hasMissingClosingBrace = node.hasError && !varText.contains("}")
        let endLine = hasMissingClosingBrace ? nil : Int(node.pointRange.upperBound.row) + 1

        return SkeletonBlock(
            kind: .type(kind!),
            typeName: name,
            inheritance: [],
            range: SourceRange(startLine: startLine, endLine: endLine),
            properties: properties,
            methods: methods,
            hasErrorNode: node.hasError
        )
    }

    private func extractMembersFromContainer(containerNode: Node, source: String, baseLine: Int)
        -> (properties: [PropertySignature], methods: [MethodSignature])
    {
        let text = nodeText(node: containerNode, source: source)
        let lines = text.components(separatedBy: "\n")
        var depth = 0
        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []

        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let depthBefore = depth

            if depthBefore == 1 {
                if let method = parseZigFn(trimmed: trimmed, lineIdx: lineIdx, lines: lines, baseLine: baseLine) {
                    methods.append(method)
                } else if let prop = parseZigField(trimmed: trimmed) {
                    properties.append(prop)
                }
            }

            depth += TextUtilities.braceBalance(line)
        }

        return (properties, methods)
    }

    private func extractFromSnippetFallback(node: Node, source: String) -> SkeletonBlock? {
        let text = nodeText(node: node, source: source)
        return parseContainerFromText(text: text, node: node)
    }

    private func parseContainerFromText(text: String, node: Node) -> SkeletonBlock? {
        let patterns: [(keyword: String, kind: String)] = [
            ("= struct", "struct"),
            ("= enum", "enum"),
            ("= union", "union"),
        ]

        for (keyword, kind) in patterns {
            guard text.contains(keyword) else { continue }

            let namePattern = #"(?:pub\s+)?(?:const\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*="#
            guard let name = TextUtilities.firstRegex(pattern: namePattern, in: text) else { continue }

            let startLine = Int(node.pointRange.lowerBound.row) + 1

            var methods: [MethodSignature] = []
            var properties: [PropertySignature] = []

            let lines = text.components(separatedBy: "\n")
            var depth = 0
            for (lineIdx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let depthBefore = depth

                if depthBefore == 1 {
                    if let method = parseZigFn(trimmed: trimmed, lineIdx: lineIdx, lines: lines, baseLine: startLine) {
                        methods.append(method)
                    } else if let prop = parseZigField(trimmed: trimmed) {
                        properties.append(prop)
                    }
                }

                depth += TextUtilities.braceBalance(line)
            }

            let hasMissingClosingBrace = node.hasError && !text.contains("}")
            let endLine = hasMissingClosingBrace ? nil : Int(node.pointRange.upperBound.row) + 1

            return SkeletonBlock(
                kind: .type(kind),
                typeName: name,
                inheritance: [],
                range: SourceRange(startLine: startLine, endLine: endLine),
                properties: properties,
                methods: methods,
                hasErrorNode: node.hasError
            )
        }

        return nil
    }

    private func parseZigFn(trimmed: String, lineIdx: Int, lines: [String], baseLine: Int) -> MethodSignature? {
        let fnPattern = #"(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let name = TextUtilities.firstRegex(pattern: fnPattern, in: trimmed) else { return nil }

        let params = TextUtilities.betweenParentheses(trimmed) ?? ""
        let paramTypes = parseZigParams(params)

        var returnType: String?
        if let closeIdx = trimmed.lastIndex(of: ")") {
            let after = String(trimmed[trimmed.index(after: closeIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = after.trimmingCharacters(in: CharacterSet(charactersIn: "{")).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                returnType = cleaned
            }
        }

        let startLine = baseLine + lineIdx
        var endLine = startLine
        var depth = 0
        for i in lineIdx..<lines.count {
            depth += TextUtilities.braceBalance(lines[i])
            if depth == 0 && i >= lineIdx {
                endLine = baseLine + i
                break
            }
        }

        return MethodSignature(
            name: name,
            parameterTypeRefs: paramTypes,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: name == "init"
        )
    }

    private func parseZigField(trimmed: String) -> PropertySignature? {
        guard !trimmed.hasPrefix("fn "), !trimmed.hasPrefix("pub fn ") else { return nil }
        let pattern = #"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^,=]+)"#
        guard let capture = TextUtilities.firstRegexCapture(pattern: pattern, in: trimmed) else { return nil }
        return PropertySignature(name: capture.0, typeRef: capture.1.trimmingCharacters(in: CharacterSet(charactersIn: ",")))
    }

    private func parseZigParams(_ paramSection: String) -> [String] {
        let trimmed = paramSection.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let chunks = TextUtilities.splitTopLevel(trimmed, by: ",")
        return chunks.compactMap { chunk in
            let part = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if part == "self" || part == "*self" || part == "*const self" || part.hasSuffix("Self") { return nil }
            guard let colon = TextUtilities.firstTopLevelIndex(in: part, character: ":") else { return nil }
            let typeRef = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return typeRef.isEmpty ? nil : typeRef
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

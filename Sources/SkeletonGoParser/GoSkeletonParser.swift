import Foundation
import SwiftTreeSitter
import TreeSitterGoGrammar
import SkeletonIndexCore

public struct GoSkeletonParser: SkeletonParser, Sendable {
    public var languageName: String { "go" }
    public var supportedExtensions: Set<String> { ["go"] }

    public init() {}

    public func parse(path: String, source: String) -> ParsedFile {
        let parser = Parser()
        do {
            guard let languagePointer = tree_sitter_go() else {
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
        var receiverMethods: [String: [MethodSignature]] = [:]

        for childIndex in 0..<root.namedChildCount {
            guard let child = root.namedChild(at: childIndex) else { continue }
            guard let nodeType = child.nodeType else { continue }

            if nodeType == "type_declaration" {
                if let block = extractTypeDeclaration(node: child, source: source) {
                    blocks.append(block)
                }
            } else if nodeType == "method_declaration" {
                if let (receiverType, method) = extractMethodDeclaration(node: child, source: source) {
                    receiverMethods[receiverType, default: []].append(method)
                }
            }
        }

        blocks = blocks.map { block in
            guard let additionalMethods = receiverMethods[block.typeName], !additionalMethods.isEmpty else {
                return block
            }
            return SkeletonBlock(
                kind: block.kind,
                typeName: block.typeName,
                inheritance: block.inheritance,
                range: block.range,
                properties: block.properties,
                methods: block.methods + additionalMethods,
                hasErrorNode: block.hasErrorNode
            )
        }

        return ParsedFile(path: path, blocks: blocks, hasParseError: root.hasError)
    }

    private func extractTypeDeclaration(node: Node, source: String) -> SkeletonBlock? {
        guard let typeSpec = findChild(named: "type_spec", in: node) else { return nil }
        guard let nameNode = findChild(named: "type_identifier", in: typeSpec) else { return nil }

        let typeName = nodeText(node: nameNode, source: source)
        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        var kind = "type"
        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []
        var inheritance: [String] = []

        if let structType = findChild(named: "struct_type", in: typeSpec) {
            kind = "struct"
            if let fieldList = findChild(named: "field_declaration_list", in: structType) {
                for i in 0..<fieldList.namedChildCount {
                    guard let field = fieldList.namedChild(at: i) else { continue }
                    guard let fieldType = field.nodeType else { continue }
                    if fieldType == "field_declaration" {
                        if let prop = extractFieldProperty(node: field, source: source) {
                            properties.append(prop)
                        }
                    }
                }
            }
        } else if let interfaceType = findChild(named: "interface_type", in: typeSpec) {
            kind = "interface"
            for i in 0..<interfaceType.namedChildCount {
                guard let child = interfaceType.namedChild(at: i) else { continue }
                guard let childType = child.nodeType else { continue }
                if childType == "method_elem" || childType == "method_spec" {
                    if let method = extractInterfaceMethod(node: child, source: source, baseLine: startLine) {
                        methods.append(method)
                    }
                } else if childType == "type_elem" || childType == "constraint_elem" {
                    let text = nodeText(node: child, source: source).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        inheritance.append(text)
                    }
                }
            }
        }

        return SkeletonBlock(
            kind: .type(kind),
            typeName: typeName,
            inheritance: inheritance,
            range: SourceRange(startLine: startLine, endLine: endLine),
            properties: properties,
            methods: methods,
            hasErrorNode: node.hasError
        )
    }

    private func extractFieldProperty(node: Node, source: String) -> PropertySignature? {
        var nameText: String?
        var typeText: String?

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }
            if childType == "field_identifier" {
                nameText = nodeText(node: child, source: source)
            } else if nameText != nil && typeText == nil {
                typeText = nodeText(node: child, source: source)
            }
        }

        guard let name = nameText, let typeRef = typeText else { return nil }
        return PropertySignature(name: name, typeRef: typeRef)
    }

    private func extractInterfaceMethod(node: Node, source: String, baseLine: Int) -> MethodSignature? {
        let text = nodeText(node: node, source: source).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("(") else { return nil }

        guard let nameEnd = text.firstIndex(of: "(") else { return nil }
        let name = String(text[text.startIndex..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let params = TextUtilities.betweenParentheses(text) ?? ""
        let paramTypes = parseGoParams(params)

        var returnType: String?
        if let closeIndex = text.lastIndex(of: ")") {
            let afterParen = String(text[text.index(after: closeIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterParen.isEmpty && afterParen != "{" {
                returnType = afterParen
            }
        }

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        return MethodSignature(
            name: name,
            parameterTypeRefs: paramTypes,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: false
        )
    }

    private func extractMethodDeclaration(node: Node, source: String) -> (String, MethodSignature)? {
        var receiverType: String?
        var methodName: String?

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            if childType == "parameter_list" && receiverType == nil && methodName == nil {
                let paramText = nodeText(node: child, source: source)
                receiverType = extractReceiverType(paramText)
            } else if childType == "field_identifier" {
                methodName = nodeText(node: child, source: source)
            }
        }

        guard let recv = receiverType, let name = methodName else { return nil }

        let text = nodeText(node: node, source: source)
        let params: [String]
        if let firstParen = text.firstIndex(of: "("),
           let afterReceiver = text[text.index(after: firstParen)...].firstIndex(of: ")") {
            let afterReceiverClose = text.index(after: afterReceiver)
            let rest = String(text[afterReceiverClose...])
            let paramSection = TextUtilities.betweenParentheses(rest) ?? ""
            params = parseGoParams(paramSection)
        } else {
            params = []
        }

        var returnType: String?
        let lines = text.components(separatedBy: "\n")
        if let firstLine = lines.first {
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lastClose = trimmed.lastIndex(of: ")") {
                let afterClose = String(trimmed[trimmed.index(after: lastClose)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterClose.isEmpty && afterClose != "{" {
                    returnType = afterClose.hasSuffix("{") ? String(afterClose.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) : afterClose
                }
            }
        }

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        let method = MethodSignature(
            name: name,
            parameterTypeRefs: params,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: false
        )

        return (recv, method)
    }

    private func extractReceiverType(_ text: String) -> String? {
        let inner = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = inner.split(separator: " ", maxSplits: 1).map(String.init)
        guard let typePart = parts.last else { return nil }
        return typePart.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseGoParams(_ paramSection: String) -> [String] {
        let trimmed = paramSection.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let chunks = TextUtilities.splitTopLevel(trimmed, by: ",")
        return chunks.compactMap { chunk in
            let parts = chunk.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            guard let typePart = parts.last else { return nil }
            return String(typePart)
        }
    }

    private func findChild(named name: String, in node: Node) -> Node? {
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            if child.nodeType == name { return child }
        }
        return nil
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

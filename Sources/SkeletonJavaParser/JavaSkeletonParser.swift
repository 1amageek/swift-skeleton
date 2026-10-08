import Foundation
import SwiftTreeSitter
import TreeSitterJavaGrammar
import SkeletonIndexCore
import SkeletonTreeSitterSupport

public struct JavaSkeletonParser: SkeletonParser, Sendable {
    public var languageName: String { "java" }
    public var supportedExtensions: Set<String> { ["java"] }

    public init() {}

    public func parse(path: String, source: String) -> ParsedFile {
        let parser = Parser()
        do {
            guard let languagePointer = tree_sitter_java() else {
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

    private static let declarationTypes: Set<String> = [
        "class_declaration",
        "interface_declaration",
        "enum_declaration",
        "record_declaration",
        "annotation_type_declaration",
    ]

    private func collectBlocks(from node: Node, source: String, into blocks: inout [SkeletonBlock]) {
        if let nodeType = node.nodeType, Self.declarationTypes.contains(nodeType) {
            if let block = extractBlock(node: node, nodeType: nodeType, source: source) {
                blocks.append(block)
            }
        }

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            collectBlocks(from: child, source: source, into: &blocks)
        }
    }

    private func extractBlock(node: Node, nodeType: String, source: String) -> SkeletonBlock? {
        let kind: String
        switch nodeType {
        case "class_declaration": kind = "class"
        case "interface_declaration": kind = "interface"
        case "enum_declaration": kind = "enum"
        case "record_declaration": kind = "record"
        case "annotation_type_declaration": kind = "annotation"
        default: return nil
        }

        guard let nameNode = findChild(named: "identifier", in: node) else { return nil }
        let typeName = nodeText(node: nameNode, source: source)

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        var inheritance: [String] = []
        if let superclass = findChild(named: "superclass", in: node) {
            inheritance.append(contentsOf: typeTexts(in: superclass, source: source))
        }
        // `implements` (classes, enums, records) and `extends` (interfaces) both wrap a
        // `type_list`; reading its type children keeps generic arguments such as `Map<K, V>` intact.
        for clauseName in ["super_interfaces", "extends_interfaces"] {
            if let clause = findChild(named: clauseName, in: node),
               let typeList = findChild(named: "type_list", in: clause) {
                inheritance.append(contentsOf: typeTexts(in: typeList, source: source))
            }
        }

        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []

        if let body = findChild(named: "class_body", in: node) ?? findChild(named: "interface_body", in: node) ?? findChild(named: "enum_body", in: node) {
            extractMembers(from: body, source: source, properties: &properties, methods: &methods)
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

    private func extractMembers(from body: Node, source: String, properties: inout [PropertySignature], methods: inout [MethodSignature]) {
        for i in 0..<body.namedChildCount {
            guard let child = body.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            switch childType {
            case "field_declaration", "constant_declaration":
                properties.append(contentsOf: extractFields(node: child, source: source))
            case "method_declaration":
                if let method = extractMethod(node: child, source: source, isConstructor: false) {
                    methods.append(method)
                }
            case "constructor_declaration":
                if let method = extractMethod(node: child, source: source, isConstructor: true) {
                    methods.append(method)
                }
            case "enum_body_declarations":
                // Fields, constructors, and methods of an enum follow its constants inside this node.
                extractMembers(from: child, source: source, properties: &properties, methods: &methods)
            default:
                break
            }
        }
    }

    /// Returns one property per `variable_declarator`, so `int a, b;` yields both `a` and `b`.
    private func extractFields(node: Node, source: String) -> [PropertySignature] {
        guard let typeNode = node.child(byFieldName: "type") else { return [] }
        let typeRef = nodeText(node: typeNode, source: source)

        var properties: [PropertySignature] = []
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i), child.nodeType == "variable_declarator" else { continue }
            guard let nameNode = child.child(byFieldName: "name") else { continue }
            properties.append(PropertySignature(name: nodeText(node: nameNode, source: source), typeRef: typeRef))
        }
        return properties
    }

    private func extractMethod(node: Node, source: String, isConstructor: Bool) -> MethodSignature? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nodeText(node: nameNode, source: source)

        var returnType: String?
        if !isConstructor, let typeNode = node.child(byFieldName: "type") {
            returnType = nodeText(node: typeNode, source: source)
        }

        var params: [String] = []
        if let parameters = node.child(byFieldName: "parameters") {
            params = extractFormalParams(node: parameters, source: source)
        }

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        return MethodSignature(
            name: name,
            parameterTypeRefs: params,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: isConstructor
        )
    }

    private func extractFormalParams(node: Node, source: String) -> [String] {
        var params: [String] = []
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }
            if childType == "formal_parameter" || childType == "spread_parameter" {
                // `spread_parameter` has no `type` field, so fall back to its first type child.
                guard let typeNode = child.child(byFieldName: "type") ?? firstTypeChild(of: child) else {
                    params.append("?")
                    continue
                }
                var typeRef = nodeText(node: typeNode, source: source)
                if childType == "spread_parameter" { typeRef += "..." }
                params.append(typeRef)
            }
        }
        return params
    }

    private func isTypeNode(_ nodeType: String) -> Bool {
        nodeType.hasSuffix("_type") || nodeType == "type_identifier" || nodeType == "scoped_type_identifier"
    }

    private func firstTypeChild(of node: Node) -> Node? {
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i), let childType = child.nodeType else { continue }
            if isTypeNode(childType) { return child }
        }
        return nil
    }

    private func typeTexts(in node: Node, source: String) -> [String] {
        var texts: [String] = []
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i), let childType = child.nodeType else { continue }
            if isTypeNode(childType) { texts.append(nodeText(node: child, source: source)) }
        }
        return texts
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

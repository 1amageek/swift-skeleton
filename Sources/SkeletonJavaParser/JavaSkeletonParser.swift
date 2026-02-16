import Foundation
import SwiftTreeSitter
import TreeSitterJavaGrammar
import SkeletonIndexCore

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

        return ParsedFile(path: path, blocks: blocks, hasParseError: root.hasError)
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
            let text = nodeText(node: superclass, source: source)
            let cleaned = text.replacingOccurrences(of: "extends", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { inheritance.append(cleaned) }
        }
        if let interfaces = findChild(named: "super_interfaces", in: node) {
            let text = nodeText(node: interfaces, source: source)
            let cleaned = text.replacingOccurrences(of: "implements", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            inheritance.append(contentsOf: parts.filter { !$0.isEmpty })
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
            case "field_declaration":
                if let prop = extractField(node: child, source: source) {
                    properties.append(prop)
                }
            case "method_declaration":
                if let method = extractMethod(node: child, source: source, isConstructor: false) {
                    methods.append(method)
                }
            case "constructor_declaration":
                if let method = extractMethod(node: child, source: source, isConstructor: true) {
                    methods.append(method)
                }
            default:
                break
            }
        }
    }

    private func extractField(node: Node, source: String) -> PropertySignature? {
        var typeText: String?
        var nameText: String?

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            if childType.hasSuffix("_type") || childType == "type_identifier" || childType == "generic_type" || childType == "integral_type" || childType == "floating_point_type" || childType == "boolean_type" || childType == "array_type" || childType == "void_type" {
                typeText = nodeText(node: child, source: source)
            } else if childType == "variable_declarator" {
                if let nameChild = findChild(named: "identifier", in: child) {
                    nameText = nodeText(node: nameChild, source: source)
                }
            }
        }

        guard let name = nameText, let typeRef = typeText else { return nil }
        return PropertySignature(name: name, typeRef: typeRef)
    }

    private func extractMethod(node: Node, source: String, isConstructor: Bool) -> MethodSignature? {
        var nameText: String?
        var returnType: String?
        var params: [String] = []

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            if childType == "identifier" && nameText == nil {
                nameText = nodeText(node: child, source: source)
            } else if childType.hasSuffix("_type") || childType == "type_identifier" || childType == "generic_type" || childType == "void_type" || childType == "array_type" {
                if !isConstructor && returnType == nil && nameText == nil {
                    returnType = nodeText(node: child, source: source)
                }
            } else if childType == "formal_parameters" {
                params = extractFormalParams(node: child, source: source)
            }
        }

        guard let name = nameText else { return nil }

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        return MethodSignature(
            name: name,
            parameterTypeRefs: params,
            returnTypeRef: isConstructor ? nil : returnType,
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
                for j in 0..<child.namedChildCount {
                    guard let paramChild = child.namedChild(at: j) else { continue }
                    guard let paramChildType = paramChild.nodeType else { continue }
                    if paramChildType.hasSuffix("_type") || paramChildType == "type_identifier" || paramChildType == "generic_type" || paramChildType == "array_type" {
                        var typeRef = nodeText(node: paramChild, source: source)
                        if childType == "spread_parameter" { typeRef += "..." }
                        params.append(typeRef)
                        break
                    }
                }
            }
        }
        return params
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

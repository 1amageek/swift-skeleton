import Foundation
import SwiftTreeSitter
import TreeSitterCppGrammar
import SkeletonIndexCore
import SkeletonTreeSitterSupport

public struct CppSkeletonParser: SkeletonParser, Sendable {
    public var languageName: String { "cpp" }
    public var supportedExtensions: Set<String> { ["cpp", "cxx", "cc", "h", "hpp", "hxx"] }

    public init() {}

    public func parse(path: String, source: String) -> ParsedFile {
        let parser = Parser()
        do {
            guard let languagePointer = tree_sitter_cpp() else {
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
        "class_specifier",
        "struct_specifier",
        "enum_specifier",
        "union_specifier",
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
        case "class_specifier": kind = "class"
        case "struct_specifier": kind = "struct"
        case "enum_specifier": kind = "enum"
        case "union_specifier": kind = "union"
        default: return nil
        }

        guard let nameNode = findChild(named: "name", in: node) ?? findChild(named: "type_identifier", in: node) else { return nil }
        let typeName = nodeText(node: nameNode, source: source)

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        var inheritance: [String] = []
        if let baseClause = findChild(named: "base_class_clause", in: node) {
            for i in 0..<baseClause.namedChildCount {
                guard let child = baseClause.namedChild(at: i) else { continue }
                let text = nodeText(node: child, source: source).trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = text
                    .replacingOccurrences(of: "public ", with: "")
                    .replacingOccurrences(of: "protected ", with: "")
                    .replacingOccurrences(of: "private ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned != ":" {
                    inheritance.append(cleaned)
                }
            }
        }

        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []

        if let body = findChild(named: "field_declaration_list", in: node) {
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
            case "function_definition":
                if let method = extractFunction(node: child, source: source) {
                    methods.append(method)
                }
            case "declaration":
                if let method = extractFunctionDeclaration(node: child, source: source) {
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

            if childType.hasSuffix("_type") || childType == "type_identifier" || childType == "primitive_type" || childType == "template_type" || childType == "auto" {
                typeText = nodeText(node: child, source: source)
            } else if childType == "field_identifier" || childType == "identifier" {
                nameText = nodeText(node: child, source: source)
            } else if childType == "init_declarator" || childType == "function_declarator" {
                if findChild(named: "parameter_list", in: child) != nil {
                    return nil
                }
                if let idChild = findChild(named: "field_identifier", in: child) ?? findChild(named: "identifier", in: child) {
                    nameText = nodeText(node: idChild, source: source)
                }
            }
        }

        guard let name = nameText, let typeRef = typeText else { return nil }
        return PropertySignature(name: name, typeRef: typeRef)
    }

    private func extractFunction(node: Node, source: String) -> MethodSignature? {
        var returnType: String?
        var nameText: String?
        var params: [String] = []
        var isConstructor = false

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            if childType.hasSuffix("_type") || childType == "type_identifier" || childType == "primitive_type" || childType == "auto" || childType == "template_type" {
                returnType = nodeText(node: child, source: source)
            } else if childType == "function_declarator" {
                if let idChild = findChild(named: "field_identifier", in: child) ?? findChild(named: "identifier", in: child) ?? findChild(named: "destructor_name", in: child) {
                    nameText = nodeText(node: idChild, source: source)
                }
                if let paramList = findChild(named: "parameter_list", in: child) {
                    params = extractParams(node: paramList, source: source)
                }
            }
        }

        if nameText == nil && returnType != nil {
            nameText = returnType
            returnType = nil
            isConstructor = true
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

    private func extractFunctionDeclaration(node: Node, source: String) -> MethodSignature? {
        let text = nodeText(node: node, source: source)
        guard text.contains("(") else { return nil }

        var returnType: String?
        var nameText: String?
        var params: [String] = []

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            if childType.hasSuffix("_type") || childType == "type_identifier" || childType == "primitive_type" || childType == "auto" || childType == "template_type" {
                returnType = nodeText(node: child, source: source)
            } else if childType == "function_declarator" || childType == "init_declarator" {
                if let funcDecl = findChild(named: "function_declarator", in: child) ?? (childType == "function_declarator" ? child : nil) {
                    if let idChild = findChild(named: "field_identifier", in: funcDecl) ?? findChild(named: "identifier", in: funcDecl) {
                        nameText = nodeText(node: idChild, source: source)
                    }
                    if let paramList = findChild(named: "parameter_list", in: funcDecl) {
                        params = extractParams(node: paramList, source: source)
                    }
                }
            }
        }

        guard let name = nameText else { return nil }

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        return MethodSignature(
            name: name,
            parameterTypeRefs: params,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: false
        )
    }

    private func extractParams(node: Node, source: String) -> [String] {
        var params: [String] = []
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }
            if childType == "parameter_declaration" || childType == "optional_parameter_declaration" {
                for j in 0..<child.namedChildCount {
                    guard let paramChild = child.namedChild(at: j) else { continue }
                    guard let paramChildType = paramChild.nodeType else { continue }
                    if paramChildType.hasSuffix("_type") || paramChildType == "type_identifier" || paramChildType == "primitive_type" || paramChildType == "auto" || paramChildType == "template_type" {
                        params.append(nodeText(node: paramChild, source: source))
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

import Foundation
import SwiftTreeSitter
import TreeSitterGoGrammar
import SkeletonIndexCore
import SkeletonTreeSitterSupport

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
        collectDeclarations(from: root, source: source, blocks: &blocks, receiverMethods: &receiverMethods)

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

        let evidence = TreeSitterImplementationEvidenceExtractor().extract(
            root: root, source: source, blocks: blocks, language: languageName
        )
        return ParsedFile(
            path: path, blocks: blocks, hasParseError: root.hasError, methodSyntaxEvidence: evidence
        )
    }

    private func collectDeclarations(
        from node: Node,
        source: String,
        blocks: inout [SkeletonBlock],
        receiverMethods: inout [String: [MethodSignature]]
    ) {
        for childIndex in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: childIndex) else { continue }
            switch child.nodeType {
            case "type_declaration":
                blocks.append(contentsOf: extractTypeDeclaration(node: child, source: source))
            case "method_declaration":
                if let (receiverType, method) = extractMethodDeclaration(node: child, source: source) {
                    receiverMethods[receiverType, default: []].append(method)
                }
            case "ERROR":
                blocks.append(contentsOf: recoverTypeDeclarations(errorNode: child, source: source))
                collectDeclarations(
                    from: child, source: source, blocks: &blocks, receiverMethods: &receiverMethods
                )
            default:
                continue
            }
        }
    }

    /// Emits one block per `type_spec`. A grouped declaration `type ( A ...; B ... )`
    /// gives each spec its own range; a single declaration keeps the declaration range.
    private func extractTypeDeclaration(node: Node, source: String) -> [SkeletonBlock] {
        let isGrouped = hasToken("(", in: node)
        return namedChildren(of: node)
            .filter { $0.nodeType == "type_spec" }
            .compactMap { spec in
                extractTypeSpec(spec: spec, rangeNode: isGrouped ? spec : node, source: source)
            }
    }

    private func extractTypeSpec(spec: Node, rangeNode: Node, source: String) -> SkeletonBlock? {
        guard let nameNode = spec.child(byFieldName: "name") else { return nil }
        let typeName = nodeText(node: nameNode, source: source)
        guard !typeName.isEmpty else { return nil }

        var kind = "type"
        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []
        var inheritance: [String] = []

        if let typeNode = spec.child(byFieldName: "type") {
            switch typeNode.nodeType {
            case "struct_type":
                kind = "struct"
                if let fieldList = findChild(named: "field_declaration_list", in: typeNode) {
                    properties = extractFieldProperties(fields: namedChildren(of: fieldList), source: source)
                }
            case "interface_type":
                kind = "interface"
                (methods, inheritance) = extractInterfaceMembers(
                    elements: namedChildren(of: typeNode), source: source
                )
            default:
                break
            }
        }

        return SkeletonBlock(
            kind: .type(kind),
            typeName: typeName,
            inheritance: inheritance,
            range: SourceRange(startLine: startLine(of: rangeNode), endLine: endLine(of: rangeNode)),
            properties: properties,
            methods: methods,
            hasErrorNode: rangeNode.hasError
        )
    }

    /// Recovers type declarations whose closing brace is missing. Tree-sitter reports them as an
    /// ERROR node holding the `type` keyword, the name, the `struct`/`interface` keyword, and the
    /// members parsed before the error. The end line stays unknown unless a real `}` is present.
    private func recoverTypeDeclarations(errorNode: Node, source: String) -> [SkeletonBlock] {
        var blocks: [SkeletonBlock] = []
        var pending: RecoveredTypeDeclaration?

        func flush() {
            defer { pending = nil }
            guard let declaration = pending, let typeName = declaration.typeName else { return }
            var properties: [PropertySignature] = []
            var methods: [MethodSignature] = []
            var inheritance: [String] = []
            if declaration.kind == "struct" {
                properties = extractFieldProperties(fields: declaration.members, source: source)
            } else if declaration.kind == "interface" {
                (methods, inheritance) = extractInterfaceMembers(elements: declaration.members, source: source)
            }
            blocks.append(SkeletonBlock(
                kind: .type(declaration.kind),
                typeName: typeName,
                inheritance: inheritance,
                range: SourceRange(startLine: declaration.startLine, endLine: declaration.endLine),
                properties: properties,
                methods: methods,
                hasErrorNode: true
            ))
        }

        for childIndex in 0..<errorNode.childCount {
            guard let child = errorNode.child(at: childIndex), let childType = child.nodeType else { continue }
            switch childType {
            case "type":
                flush()
                pending = RecoveredTypeDeclaration(startLine: startLine(of: child))
            case "identifier", "type_identifier":
                if pending?.typeName == nil, pending?.hasBody == false {
                    pending?.typeName = nodeText(node: child, source: source)
                }
            case "struct", "interface":
                if pending?.typeName != nil, pending?.hasBody == false {
                    pending?.kind = childType
                }
            case "{":
                if pending?.typeName != nil {
                    pending?.hasBody = true
                }
            case "}":
                if pending?.hasBody == true, !child.isMissing {
                    pending?.endLine = endLine(of: child)
                    flush()
                }
            case "field_declaration", "method_elem", "method_spec", "type_elem", "constraint_elem":
                if pending?.hasBody == true {
                    pending?.members.append(child)
                }
            case "field_declaration_list":
                if pending?.typeName != nil {
                    pending?.hasBody = true
                    pending?.members.append(contentsOf: namedChildren(of: child))
                }
            default:
                continue
            }
        }
        flush()
        return blocks
    }

    private func extractFieldProperties(fields: [Node], source: String) -> [PropertySignature] {
        var properties: [PropertySignature] = []
        for field in fields where field.nodeType == "field_declaration" {
            // Embedded fields have no `name` field; they and untyped fields are omitted.
            guard let typeNode = field.child(byFieldName: "type") else { continue }
            let typeRef = compactText(node: typeNode, source: source)
            for nameNode in fieldNodes(named: "name", in: field) {
                properties.append(PropertySignature(
                    name: nodeText(node: nameNode, source: source),
                    typeRef: typeRef
                ))
            }
        }
        return properties
    }

    private func extractInterfaceMembers(elements: [Node], source: String)
        -> (methods: [MethodSignature], inheritance: [String])
    {
        var methods: [MethodSignature] = []
        var inheritance: [String] = []
        for element in elements {
            switch element.nodeType {
            case "method_elem", "method_spec":
                if let method = extractSignature(node: element, source: source) {
                    methods.append(method)
                }
            case "type_elem", "constraint_elem":
                let text = compactText(node: element, source: source)
                if !text.isEmpty {
                    inheritance.append(text)
                }
            default:
                continue
            }
        }
        return (methods, inheritance)
    }

    private func extractMethodDeclaration(node: Node, source: String) -> (String, MethodSignature)? {
        guard let receiverList = node.child(byFieldName: "receiver"),
              let receiverType = receiverTypeName(receiverList: receiverList, source: source),
              let method = extractSignature(node: node, source: source)
        else { return nil }
        return (receiverType, method)
    }

    /// Builds a signature from the `name`, `parameters`, and `result` fields shared by
    /// `method_declaration` and interface `method_elem` nodes. The range is the node's own lines.
    private func extractSignature(node: Node, source: String) -> MethodSignature? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nodeText(node: nameNode, source: source)
        guard !name.isEmpty else { return nil }

        let parameterTypes = node.child(byFieldName: "parameters")
            .map { parameterTypeRefs(parameterList: $0, source: source) } ?? []
        let returnType = node.child(byFieldName: "result")
            .map { resultTypeRef(result: $0, source: source) }

        return MethodSignature(
            name: name,
            parameterTypeRefs: parameterTypes,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine(of: node), endLine: endLine(of: node)),
            isInitializer: false
        )
    }

    /// Expands grouped names so that `a, b int` yields one type reference per name.
    private func parameterTypeRefs(parameterList: Node, source: String) -> [String] {
        var typeRefs: [String] = []
        for parameter in namedChildren(of: parameterList) {
            let isVariadic: Bool
            switch parameter.nodeType {
            case "parameter_declaration": isVariadic = false
            case "variadic_parameter_declaration": isVariadic = true
            default: continue
            }
            let typeRef: String
            if let typeNode = parameter.child(byFieldName: "type") {
                let text = compactText(node: typeNode, source: source)
                typeRef = isVariadic ? "..." + text : text
            } else {
                typeRef = "?"
            }
            let nameCount = max(1, fieldNodes(named: "name", in: parameter).count)
            typeRefs.append(contentsOf: Array(repeating: typeRef, count: nameCount))
        }
        return typeRefs
    }

    /// A parenthesized result renders as `(T1, T2)` with result names dropped,
    /// so `(n int, err error)` and `(int, error)` render identically.
    private func resultTypeRef(result: Node, source: String) -> String {
        guard result.nodeType == "parameter_list" else {
            return compactText(node: result, source: source)
        }
        let types = parameterTypeRefs(parameterList: result, source: source)
        return "(" + types.joined(separator: ", ") + ")"
    }

    /// Resolves the receiver base type name, removing pointer and type-argument syntax
    /// so `(s *Stack[T])` matches the `Stack` block.
    private func receiverTypeName(receiverList: Node, source: String) -> String? {
        guard let declaration = namedChildren(of: receiverList).first(where: {
            $0.nodeType == "parameter_declaration"
        }), var typeNode = declaration.child(byFieldName: "type") else { return nil }

        while true {
            switch typeNode.nodeType {
            case "pointer_type", "parenthesized_type":
                guard let inner = typeNode.namedChild(at: 0) else { return nil }
                typeNode = inner
            case "generic_type":
                guard let base = typeNode.child(byFieldName: "type") else { return nil }
                typeNode = base
            case "type_identifier":
                let name = nodeText(node: typeNode, source: source)
                return name.isEmpty ? nil : name
            default:
                return nil
            }
        }
    }

    private func namedChildren(of node: Node) -> [Node] {
        (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
    }

    private func fieldNodes(named fieldName: String, in node: Node) -> [Node] {
        (0..<node.childCount).compactMap { index in
            node.fieldNameForChild(at: index) == fieldName ? node.child(at: index) : nil
        }
    }

    private func hasToken(_ token: String, in node: Node) -> Bool {
        (0..<node.childCount).contains { node.child(at: $0)?.nodeType == token }
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

/// Accumulates the pieces of a type declaration recovered from an ERROR node.
private struct RecoveredTypeDeclaration {
    let startLine: Int
    var typeName: String?
    var kind = "type"
    var hasBody = false
    var endLine: Int?
    var members: [Node] = []
}

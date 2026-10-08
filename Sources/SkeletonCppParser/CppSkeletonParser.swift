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

    /// Named children of `base_class_clause` that qualify a base instead of naming it.
    private static let baseClassModifierTypes: Set<String> = [
        "access_specifier",
        "comment",
        "virtual",
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

        // A specifier without a body is a forward declaration (`class Foo;`) or an
        // elaborated type reference (`struct Foo* p;`), not a type definition.
        guard let body = node.child(byFieldName: "body") else { return nil }
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let typeName = nodeText(node: nameNode, source: source)

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []

        if body.nodeType == "field_declaration_list" {
            extractMembers(
                from: body,
                className: simpleName(of: nameNode, source: source),
                source: source,
                properties: &properties,
                methods: &methods
            )
        }

        return SkeletonBlock(
            kind: .type(kind),
            typeName: typeName,
            inheritance: baseClassNames(of: node, source: source),
            range: SourceRange(startLine: startLine, endLine: endLine),
            properties: properties,
            methods: methods,
            hasErrorNode: node.hasError
        )
    }

    private func baseClassNames(of node: Node, source: String) -> [String] {
        guard let baseClause = findChild(named: "base_class_clause", in: node) else { return [] }
        var names: [String] = []
        for i in 0..<baseClause.namedChildCount {
            guard let child = baseClause.namedChild(at: i), let childType = child.nodeType else { continue }
            if Self.baseClassModifierTypes.contains(childType) { continue }
            names.append(nodeText(node: child, source: source))
        }
        return names
    }

    /// Returns the unqualified, non-template name used to spell constructors
    /// (`Foo` for `Foo`, `ns::Foo`, and `Foo<int>`).
    private func simpleName(of node: Node, source: String) -> String {
        switch node.nodeType {
        case "qualified_identifier", "template_type":
            if let inner = node.child(byFieldName: "name") {
                return simpleName(of: inner, source: source)
            }
            return nodeText(node: node, source: source)
        default:
            return nodeText(node: node, source: source)
        }
    }

    private func extractMembers(
        from body: Node,
        className: String,
        source: String,
        properties: inout [PropertySignature],
        methods: inout [MethodSignature]
    ) {
        for i in 0..<body.namedChildCount {
            guard let child = body.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            switch childType {
            case "field_declaration":
                for declarator in declarators(of: child) {
                    let resolved = resolveDeclarator(declarator)
                    if resolved.core.nodeType == "function_declarator" {
                        if let method = makeMethod(
                            node: child, resolved: resolved, className: className, source: source
                        ) {
                            methods.append(method)
                        }
                    } else if let property = makeProperty(node: child, resolved: resolved, source: source) {
                        properties.append(property)
                    }
                }
            case "function_definition", "declaration":
                for declarator in declarators(of: child) {
                    let resolved = resolveDeclarator(declarator)
                    if let method = makeMethod(
                        node: child, resolved: resolved, className: className, source: source
                    ) {
                        methods.append(method)
                    }
                }
            default:
                break
            }
        }
    }

    private func makeProperty(node: Node, resolved: ResolvedDeclarator, source: String) -> PropertySignature? {
        guard let coreType = resolved.core.nodeType,
              coreType == "field_identifier" || coreType == "identifier" else { return nil }
        guard let baseType = declaredTypeText(of: node, source: source) else { return nil }
        return PropertySignature(
            name: nodeText(node: resolved.core, source: source),
            typeRef: baseType + resolved.suffix
        )
    }

    private func makeMethod(
        node: Node,
        resolved: ResolvedDeclarator,
        className: String,
        source: String
    ) -> MethodSignature? {
        guard resolved.core.nodeType == "function_declarator" else { return nil }
        guard let nameNode = resolved.core.child(byFieldName: "declarator") else { return nil }
        let name = nodeText(node: nameNode, source: source)

        var params: [String] = []
        if let paramList = resolved.core.child(byFieldName: "parameters") {
            params = extractParams(node: paramList, source: source)
        }

        let declaredType = declaredTypeText(of: node, source: source)
        // Constructors have no declared type and are spelled with the class name itself.
        // Destructors (`~Foo`) and typed members returning the class (`Foo* self()`) are not.
        let isConstructor = declaredType == nil
            && resolved.suffix.isEmpty
            && nameNode.nodeType == "identifier"
            && name == className
        let returnType = declaredType.map { $0 + resolved.suffix }

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

    private func extractParams(node: Node, source: String) -> [String] {
        var params: [String] = []
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }
            if childType == "parameter_declaration" || childType == "optional_parameter_declaration" {
                guard let baseType = declaredTypeText(of: child, source: source) else {
                    params.append("?")
                    continue
                }
                let suffix = child.child(byFieldName: "declarator").map { resolveDeclarator($0).suffix } ?? ""
                params.append(baseType + suffix)
            }
        }
        return params
    }

    /// The innermost declarator and the pointer/reference tokens that wrap it, in source order.
    /// `*&` for `int*& r`, `&&` for `std::string&& s`.
    private struct ResolvedDeclarator {
        let core: Node
        let suffix: String
    }

    private func resolveDeclarator(_ declarator: Node) -> ResolvedDeclarator {
        var suffix = ""
        var current = declarator
        while true {
            let inner: Node?
            switch current.nodeType {
            case "pointer_declarator", "abstract_pointer_declarator":
                suffix += "*"
                inner = current.child(byFieldName: "declarator")
            case "reference_declarator", "abstract_reference_declarator":
                suffix += referenceToken(of: current)
                // Reference declarators hold their target as the only named child, without a field.
                inner = current.namedChildCount > 0 ? current.namedChild(at: 0) : nil
            default:
                return ResolvedDeclarator(core: current, suffix: suffix)
            }
            guard let inner else {
                return ResolvedDeclarator(core: current, suffix: suffix)
            }
            current = inner
        }
    }

    private func referenceToken(of node: Node) -> String {
        for i in 0..<node.childCount {
            if node.child(at: i)?.nodeType == "&&" { return "&&" }
        }
        return "&"
    }

    private func declarators(of node: Node) -> [Node] {
        var result: [Node] = []
        for i in 0..<node.childCount where node.fieldNameForChild(at: i) == "declarator" {
            if let child = node.child(at: i) {
                result.append(child)
            }
        }
        return result
    }

    /// The declared type of a declaration, prefixed with its direct type qualifiers
    /// (`const char` for `const char* p`, `const Foo` for `Foo const& f`).
    /// Returns nil when the declaration has no type (constructors, destructors) or the
    /// type is an anonymous class/struct/enum/union definition.
    private func declaredTypeText(of node: Node, source: String) -> String? {
        guard let typeNode = node.child(byFieldName: "type") else { return nil }
        let baseType: String
        if let typeNodeType = typeNode.nodeType, Self.declarationTypes.contains(typeNodeType) {
            guard let nameNode = typeNode.child(byFieldName: "name") else { return nil }
            baseType = nodeText(node: nameNode, source: source)
        } else {
            baseType = nodeText(node: typeNode, source: source)
        }

        var qualifiers: [String] = []
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i), child.nodeType == "type_qualifier" else { continue }
            qualifiers.append(nodeText(node: child, source: source))
        }
        return (qualifiers + [baseType]).joined(separator: " ")
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

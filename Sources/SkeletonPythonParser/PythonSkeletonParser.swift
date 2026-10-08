import Foundation
import SwiftTreeSitter
import TreeSitterPythonGrammar
import SkeletonIndexCore
import SkeletonTreeSitterSupport

public struct PythonSkeletonParser: SkeletonParser, Sendable {
    public var languageName: String { "python" }
    public var supportedExtensions: Set<String> { ["py", "pyi"] }

    public init() {}

    public func parse(path: String, source: String) -> ParsedFile {
        let parser = Parser()
        do {
            guard let languagePointer = tree_sitter_python() else {
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

    /// Collects every `class_definition` in pre-order, including classes nested in other classes,
    /// in function bodies, under decorators, and inside `if` / `try` / `with` blocks.
    /// Each nested class becomes its own block; members are attributed only to the class whose
    /// body directly contains them (see `extractMembers`).
    private func collectBlocks(from node: Node, source: String, into blocks: inout [SkeletonBlock]) {
        if node.nodeType == "class_definition", let block = extractClass(node: node, source: source) {
            blocks.append(block)
        }

        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            collectBlocks(from: child, source: source, into: &blocks)
        }
    }

    private func extractClass(node: Node, source: String) -> SkeletonBlock? {
        guard let nameNode = findChild(named: "identifier", in: node) else { return nil }
        let typeName = nodeText(node: nameNode, source: source)

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        var inheritance: [String] = []
        if let argList = findChild(named: "argument_list", in: node) {
            for i in 0..<argList.namedChildCount {
                guard let child = argList.namedChild(at: i) else { continue }
                let text = nodeText(node: child, source: source).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && !text.contains("=") {
                    inheritance.append(text)
                }
            }
        }

        var methods: [MethodSignature] = []
        var properties: [PropertySignature] = []

        if let body = findChild(named: "block", in: node) {
            extractMembers(from: body, source: source, methods: &methods, properties: &properties)
        }

        return SkeletonBlock(
            kind: .type("class"),
            typeName: typeName,
            inheritance: inheritance,
            range: SourceRange(startLine: startLine, endLine: endLine),
            properties: properties,
            methods: methods,
            hasErrorNode: node.hasError
        )
    }

    private func extractMembers(from body: Node, source: String, methods: inout [MethodSignature], properties: inout [PropertySignature]) {
        for i in 0..<body.namedChildCount {
            guard let child = body.namedChild(at: i) else { continue }
            guard let childType = child.nodeType else { continue }

            var funcNode: Node?
            if childType == "function_definition" {
                funcNode = child
            } else if childType == "decorated_definition" {
                for j in 0..<child.namedChildCount {
                    guard let inner = child.namedChild(at: j) else { continue }
                    if inner.nodeType == "function_definition" {
                        funcNode = inner
                        break
                    }
                }
            }

            if let funcNode = funcNode {
                if let method = extractMethod(node: funcNode, source: source) {
                    methods.append(method)
                }
            }

            if childType == "expression_statement" {
                if let prop = extractProperty(node: child, source: source) {
                    properties.append(prop)
                }
            }
        }
    }

    private func extractMethod(node: Node, source: String) -> MethodSignature? {
        guard let nameNode = findChild(named: "identifier", in: node) else { return nil }
        let name = nodeText(node: nameNode, source: source)

        let isInitializer = name == "__init__"

        var params: [String] = []
        if let paramNode = findChild(named: "parameters", in: node) {
            params = extractParams(node: paramNode, source: source)
        }

        var returnType: String?
        if let retType = findChild(named: "type", in: node) {
            returnType = nodeText(node: retType, source: source)
        }

        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let endLine = Int(node.pointRange.upperBound.row) + 1

        return MethodSignature(
            name: name,
            parameterTypeRefs: params,
            returnTypeRef: isInitializer ? nil : returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: isInitializer
        )
    }

    private static let parameterNodeTypes: Set<String> = [
        "identifier", "typed_parameter", "default_parameter", "typed_default_parameter",
        "list_splat_pattern", "dictionary_splat_pattern", "keyword_separator", "positional_separator",
    ]

    private func extractParams(node: Node, source: String) -> [String] {
        var params: [String] = []
        var isFirstParameter = true
        for i in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            guard let childType = child.nodeType, Self.parameterNodeTypes.contains(childType) else { continue }
            defer { isFirstParameter = false }

            // Only the leading receiver (`self` / `cls`) is implicit; names that merely start
            // with those words, or appear later in the list, are real parameters.
            if isFirstParameter, let name = parameterName(of: child, source: source), name == "self" || name == "cls" {
                continue
            }

            if childType == "identifier" {
                params.append("?")
            } else if childType == "typed_parameter" {
                let text = nodeText(node: child, source: source)
                if let colon = TextUtilities.firstTopLevelIndex(in: text, character: ":") {
                    let typeRef = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    params.append(typeRef.isEmpty ? "?" : typeRef)
                } else {
                    params.append("?")
                }
            } else if childType == "typed_default_parameter" || childType == "default_parameter" {
                let text = nodeText(node: child, source: source)
                if let colon = TextUtilities.firstTopLevelIndex(in: text, character: ":") {
                    let afterColon = String(text[text.index(after: colon)...])
                    if let eq = TextUtilities.firstTopLevelIndex(in: afterColon, character: "=") {
                        let typeRef = String(afterColon[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
                        params.append(typeRef.isEmpty ? "?" : typeRef)
                    } else {
                        params.append("?")
                    }
                } else {
                    params.append("?")
                }
            } else if childType == "list_splat_pattern" || childType == "dictionary_splat_pattern" {
                params.append("?")
            }
        }
        return params
    }

    /// Returns the declared name of a plain, typed, or defaulted parameter, or nil for splats and separators.
    private func parameterName(of node: Node, source: String) -> String? {
        switch node.nodeType {
        case "identifier":
            return nodeText(node: node, source: source)
        case "default_parameter", "typed_default_parameter":
            guard let nameNode = node.child(byFieldName: "name"), nameNode.nodeType == "identifier" else { return nil }
            return nodeText(node: nameNode, source: source)
        case "typed_parameter":
            // `typed_parameter` has no name field; its leading named child is the bound pattern.
            guard let nameNode = node.namedChild(at: 0), nameNode.nodeType == "identifier" else { return nil }
            return nodeText(node: nameNode, source: source)
        default:
            return nil
        }
    }

    private func extractProperty(node: Node, source: String) -> PropertySignature? {
        let text = nodeText(node: node, source: source).trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=]+)"#
        guard let capture = TextUtilities.firstRegexCapture(pattern: pattern, in: text) else { return nil }
        return PropertySignature(
            name: capture.0,
            typeRef: capture.1.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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

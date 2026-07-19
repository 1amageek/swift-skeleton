import Foundation
import SkeletonIndexCore
import SwiftTreeSitter

public struct TreeSitterImplementationEvidenceExtractor: Sendable {
    private static let methodNodeFragments = [
        "function", "method", "constructor", "declaration", "definition", "init",
    ]

    private static let bodyNodeTypes: Set<String> = [
        "block", "block_expression", "compound_statement", "constructor_body", "function_body",
        "statement_block",
    ]

    private static let returnNodeTypes: Set<String> = [
        "co_return_statement", "return", "return_expression", "return_statement",
    ]

    private static let callNodeTypes: Set<String> = [
        "builtin_function", "call", "call_expression", "macro_invocation", "method_invocation",
        "new_expression", "object_creation_expression",
    ]

    private static let assignmentNodeTypes: Set<String> = [
        "assignment", "assignment_expression", "assignment_statement", "augmented_assignment",
    ]

    private static let catchNodeTypes: Set<String> = [
        "catch_block", "catch_clause", "catch_expression", "except_clause",
    ]

    private static let throwNodeTypes: Set<String> = [
        "_throw_statement", "raise_statement", "throw", "throw_expression", "throw_keyword", "throw_statement",
    ]

    private static let branchNodeTypes: Set<String> = [
        "case_clause", "catch_block", "catch_clause", "catch_expression", "conditional_expression",
        "else_clause", "except_clause", "guard_statement", "if_expression", "if_statement",
        "match_arm", "switch_case", "switch_entry", "switch_expression", "switch_statement",
        "when_entry", "when_expression",
    ]

    private static let identifierNodeTypes: Set<String> = [
        "field_identifier", "identifier", "property_identifier", "simple_identifier", "type_identifier",
    ]

    private static let literalFragments = [
        "boolean", "character", "float", "integer", "literal", "null", "number", "string",
    ]

    private static let trapNames: Set<String> = [
        "NotImplementedError", "TODO", "UnsupportedOperationException", "abort", "assertionFailure",
        "fatalError", "panic", "preconditionFailure", "todo", "unimplemented", "unreachable",
    ]

    public init() {}

    public func extract(
        root: Node,
        source: String,
        blocks: [SkeletonBlock],
        language: String
    ) -> [MethodSyntaxEvidence] {
        var result: [MethodSyntaxEvidence] = []
        for block in blocks {
            for method in block.methods {
                guard let methodNode = findMethodNode(root: root, range: method.range) else {
                    continue
                }
                result.append(makeEvidence(
                    methodNode: methodNode,
                    block: block,
                    method: method,
                    source: source,
                    language: language
                ))
            }
        }
        return result
    }

    private func makeEvidence(
        methodNode: Node,
        block: SkeletonBlock,
        method: MethodSignature,
        source: String,
        language: String
    ) -> MethodSyntaxEvidence {
        let methodSource = nodeText(methodNode, source: source)
        let parameters = parameterNames(from: methodSource, language: language)
        guard let body = findBody(in: methodNode) else {
            return MethodSyntaxEvidence(
                typeName: block.typeName,
                methodName: method.name,
                range: method.range,
                bodyState: .absent,
                syntaxState: methodNode.hasError ? .incomplete : .complete,
                parameterNames: parameters,
                referencedIdentifiers: [],
                returns: [],
                callTargets: [],
                assignmentTargets: [],
                controlFlowPaths: 1,
                throwsError: false,
                trapCalls: [],
                catches: [],
                asyncOperations: [],
                executableStatementCount: 0
            )
        }

        var summary = summarize(node: body, source: source, excludingNestedMethods: true)
        if summary.returns.isEmpty, method.returnTypeRef != nil,
           let expression = implicitResultExpression(in: body),
           let implicitReturn = expressionEvidence(expression: expression, source: source) {
            summary.returns.append(implicitReturn)
        }
        let empty = !hasMeaningfulBodyContent(body, source: source)
        if !empty {
            summary.executableStatementCount = max(1, summary.executableStatementCount)
        }
        let bodyState: ImplementationFingerprint.BodyState
        if empty && isAbstractRequirement(
            methodSource: methodSource,
            source: source,
            range: method.range,
            language: language
        ) {
            bodyState = .absent
        } else {
            bodyState = empty ? .empty : .concrete
        }
        return MethodSyntaxEvidence(
            typeName: block.typeName,
            methodName: method.name,
            range: method.range,
            bodyState: bodyState,
            syntaxState: body.hasError || methodNode.hasError ? .incomplete : .complete,
            parameterNames: parameters,
            referencedIdentifiers: summary.identifiers,
            returns: summary.returns,
            callTargets: summary.callTargets,
            assignmentTargets: summary.assignmentTargets,
            controlFlowPaths: max(1, summary.branchCount + 1),
            throwsError: summary.throwsError,
            trapCalls: summary.trapCalls,
            catches: summary.catches,
            asyncOperations: summary.hasAwait ? ["await"] : [],
            executableStatementCount: summary.executableStatementCount
        )
    }

    private func isAbstractRequirement(
        methodSource: String,
        source: String,
        range: SourceRange,
        language: String
    ) -> Bool {
        let methodIdentifiers = Set(lexicalIdentifiers(in: methodSource))
        if methodIdentifiers.contains("abstract") || methodIdentifiers.contains("abstractmethod") {
            return true
        }
        guard language == "python", let startLine = range.startLine, startLine > 1 else { return false }
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var index = startLine - 2
        while index >= 0 {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                index -= 1
                continue
            }
            guard line.hasPrefix("@") else { return false }
            if Set(lexicalIdentifiers(in: line)).contains("abstractmethod") { return true }
            index -= 1
        }
        return false
    }

    private struct Summary {
        var identifiers: [String] = []
        var returns: [MethodSyntaxEvidence.ReturnEvidence] = []
        var callTargets: [String] = []
        var assignmentTargets: [String] = []
        var trapCalls: [String] = []
        var catches: [MethodSyntaxEvidence.CatchEvidence] = []
        var branchCount = 0
        var throwsError = false
        var hasAwait = false
        var executableStatementCount = 0
    }

    private func summarize(node: Node, source: String, excludingNestedMethods: Bool) -> Summary {
        var summary = Summary()
        walk(node: node, source: source, isRoot: true, excludingNestedMethods: excludingNestedMethods, summary: &summary)
        summary.identifiers = orderedUnique(summary.identifiers)
        summary.callTargets = orderedUnique(summary.callTargets)
        summary.assignmentTargets = orderedUnique(summary.assignmentTargets)
        summary.trapCalls = orderedUnique(summary.trapCalls)
        return summary
    }

    private func walk(
        node: Node,
        source: String,
        isRoot: Bool,
        excludingNestedMethods: Bool,
        summary: inout Summary
    ) {
        let type = node.nodeType ?? ""
        if !isRoot && excludingNestedMethods && isMethodNodeType(type) {
            return
        }
        if !isRoot && Self.catchNodeTypes.contains(type) {
            let nested = summarize(node: node, source: source, excludingNestedMethods: true)
            summary.catches.append(MethodSyntaxEvidence.CatchEvidence(
                executableStatementCount: nested.executableStatementCount,
                callTargets: nested.callTargets,
                assignmentTargets: nested.assignmentTargets,
                returns: nested.returns,
                throwsError: nested.throwsError,
                trapCalls: nested.trapCalls
            ))
        }
        if Self.identifierNodeTypes.contains(type) {
            summary.identifiers.append(nodeText(node, source: source))
        }
        if Self.returnNodeTypes.contains(type), let evidence = returnEvidence(node: node, source: source) {
            summary.returns.append(evidence)
            summary.executableStatementCount += 1
        }
        if Self.callNodeTypes.contains(type) {
            if let target = callTarget(node: node, source: source) {
                summary.callTargets.append(target)
                if Self.trapNames.contains(target) {
                    summary.trapCalls.append(target)
                }
            }
            summary.executableStatementCount += 1
        }
        if Self.assignmentNodeTypes.contains(type) {
            if let target = assignmentTarget(node: node, source: source) {
                summary.assignmentTargets.append(target)
            }
            summary.executableStatementCount += 1
        }
        if Self.throwNodeTypes.contains(type) {
            summary.throwsError = true
            summary.executableStatementCount += 1
        }
        if Self.branchNodeTypes.contains(type) {
            summary.branchCount += 1
        }
        if type == "await" || type == "await_expression" {
            summary.hasAwait = true
        }
        if node.isNamed && isExecutableLeaf(type: type, node: node) {
            summary.executableStatementCount += 1
        }

        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            walk(
                node: child,
                source: source,
                isRoot: false,
                excludingNestedMethods: excludingNestedMethods,
                summary: &summary
            )
        }
    }

    private func returnEvidence(node: Node, source: String) -> MethodSyntaxEvidence.ReturnEvidence? {
        let expression: Node?
        if node.isNamed {
            expression = node.child(byFieldName: "value") ??
                node.child(byFieldName: "expression") ??
                firstMeaningfulNamedChild(of: node)
        } else {
            expression = node.nextNamedSibling
        }
        guard let expression else {
            return MethodSyntaxEvidence.ReturnEvidence(kind: .unknown, identifiers: [], signature: "void")
        }
        return expressionEvidence(expression: expression, source: source)
    }

    private func expressionEvidence(
        expression: Node,
        source: String
    ) -> MethodSyntaxEvidence.ReturnEvidence? {
        let expressionType = expression.nodeType ?? ""
        let identifiers = descendantIdentifiers(in: expression, source: source)
        let containsCall = containsNode(in: expression) { Self.callNodeTypes.contains($0) }
        let text = nodeText(expression, source: source)
        let kind: MethodSyntaxEvidence.ExpressionKind
        if containsCall {
            let target = callTarget(node: expression, source: source) ?? identifiers.first ?? ""
            kind = target.first?.isUppercase == true ? .constructed : .call
        } else if isLiteralNode(type: expressionType, text: text) {
            kind = .literal
        } else if !identifiers.isEmpty {
            kind = .identifier
        } else {
            kind = .unknown
        }
        return MethodSyntaxEvidence.ReturnEvidence(
            kind: kind,
            identifiers: orderedUnique(identifiers),
            signature: stableSignature(for: expression, source: source)
        )
    }

    private func implicitResultExpression(in body: Node) -> Node? {
        var candidate = body
        var unwrapped = false
        let wrapperTypes = Self.bodyNodeTypes.union(["expression_statement", "statements"])
        while wrapperTypes.contains(candidate.nodeType ?? ""), candidate.namedChildCount == 1,
              let child = candidate.namedChild(at: 0) {
            candidate = child
            unwrapped = true
        }
        guard unwrapped else { return nil }
        let type = candidate.nodeType ?? ""
        if Self.returnNodeTypes.contains(type) || Self.throwNodeTypes.contains(type) ||
            Self.assignmentNodeTypes.contains(type) || Self.branchNodeTypes.contains(type) ||
            isMethodNodeType(type) {
            return nil
        }
        return candidate
    }

    private func hasMeaningfulBodyContent(_ node: Node, source: String, isRoot: Bool = true) -> Bool {
        let type = node.nodeType ?? ""
        if !isRoot && (type == "comment" || type == "doc_comment" || type == "pass_statement") {
            return false
        }
        if !isRoot && node.isNamed && !Self.bodyNodeTypes.contains(type) && type != "statements" {
            let text = nodeText(node, source: source).trimmingCharacters(in: .whitespacesAndNewlines)
            if text != "..." { return true }
        }
        for index in 0..<node.namedChildCount {
            if let child = node.namedChild(at: index),
               hasMeaningfulBodyContent(child, source: source, isRoot: false) {
                return true
            }
        }
        return false
    }

    private func callTarget(node: Node, source: String) -> String? {
        if node.nodeType == "macro_invocation" {
            return firstIdentifier(in: nodeText(node, source: source))
        }
        let targetNode = node.child(byFieldName: "function") ?? node.child(byFieldName: "name") ??
            node.child(byFieldName: "callee") ?? node.child(byFieldName: "method")
        let text = targetNode.map { nodeText($0, source: source) } ?? nodeText(node, source: source)
        return lastIdentifier(beforeOpeningParenthesisIn: text)
    }

    private func assignmentTarget(node: Node, source: String) -> String? {
        let target = node.child(byFieldName: "left") ?? node.child(byFieldName: "target") ?? node.namedChild(at: 0)
        guard let target else { return nil }
        return descendantIdentifiers(in: target, source: source).last ?? lastIdentifier(in: nodeText(target, source: source))
    }

    private func findMethodNode(root: Node, range: SourceRange) -> Node? {
        guard let startLine = range.startLine else { return nil }
        let endLine = range.endLine ?? startLine
        var candidates: [(node: Node, exact: Bool, hasBody: Bool, size: Int)] = []
        collectMethodCandidates(node: root, startLine: startLine, endLine: endLine, into: &candidates)
        return candidates.sorted {
            if $0.exact != $1.exact { return $0.exact && !$1.exact }
            if $0.hasBody != $1.hasBody { return $0.hasBody && !$1.hasBody }
            return $0.size < $1.size
        }.first?.node
    }

    private func collectMethodCandidates(
        node: Node,
        startLine: Int,
        endLine: Int,
        into candidates: inout [(node: Node, exact: Bool, hasBody: Bool, size: Int)]
    ) {
        let nodeStart = Int(node.pointRange.lowerBound.row) + 1
        let nodeEnd = Int(node.pointRange.upperBound.row) + 1
        guard nodeStart <= startLine, nodeEnd >= endLine else { return }
        let type = node.nodeType ?? ""
        if isMethodNodeType(type) {
            candidates.append((
                node,
                nodeStart == startLine && nodeEnd == endLine,
                findBody(in: node) != nil,
                node.byteRange.count
            ))
        }
        for index in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: index) else { continue }
            collectMethodCandidates(node: child, startLine: startLine, endLine: endLine, into: &candidates)
        }
    }

    private func findBody(in methodNode: Node) -> Node? {
        for field in ["body", "value"] {
            if let child = methodNode.child(byFieldName: field), isBodyOrExpression(child) {
                return child
            }
        }
        for index in 0..<methodNode.namedChildCount {
            guard let child = methodNode.namedChild(at: index) else { continue }
            if isBodyOrExpression(child) {
                return child
            }
        }
        return nil
    }

    private func isBodyOrExpression(_ node: Node) -> Bool {
        let type = node.nodeType ?? ""
        if Self.bodyNodeTypes.contains(type) { return true }
        return type.hasSuffix("expression") && type != "type_expression"
    }

    private func isMethodNodeType(_ type: String) -> Bool {
        Self.methodNodeFragments.contains { type.contains($0) } &&
            !type.contains("builtin") && !type.contains("call") && !type.contains("parameter") &&
            !type.contains("body")
    }

    private func isExecutableLeaf(type: String, node: Node) -> Bool {
        guard node.namedChildCount == 0 else { return false }
        return type.hasSuffix("statement") && !Self.returnNodeTypes.contains(type) &&
            !Self.throwNodeTypes.contains(type) && type != "empty_statement" && type != "pass_statement"
    }

    private func firstMeaningfulNamedChild(of node: Node) -> Node? {
        for index in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: index) else { continue }
            let type = child.nodeType ?? ""
            if !type.contains("type") { return child }
        }
        return nil
    }

    private func containsNode(in node: Node, predicate: (String) -> Bool) -> Bool {
        if predicate(node.nodeType ?? "") { return true }
        for index in 0..<node.namedChildCount {
            if let child = node.namedChild(at: index), containsNode(in: child, predicate: predicate) { return true }
        }
        return false
    }

    private func descendantIdentifiers(in node: Node, source: String) -> [String] {
        var values: [String] = []
        collectIdentifiers(node: node, source: source, into: &values)
        return values
    }

    private func collectIdentifiers(node: Node, source: String, into values: inout [String]) {
        let type = node.nodeType ?? ""
        if Self.identifierNodeTypes.contains(type) {
            values.append(nodeText(node, source: source))
        }
        for index in 0..<node.namedChildCount {
            if let child = node.namedChild(at: index) {
                collectIdentifiers(node: child, source: source, into: &values)
            }
        }
    }

    private func isLiteralNode(type: String, text: String) -> Bool {
        if Self.literalFragments.contains(where: type.contains) { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["false", "nil", "null", "none", "true"].contains(trimmed.lowercased()) || Double(trimmed) != nil
    }

    private func parameterNames(from methodSource: String, language: String) -> [String] {
        guard let opening = methodSource.firstIndex(of: "("),
              let closing = matchingClosingParenthesis(in: methodSource, opening: opening) else { return [] }
        let text = String(methodSource[methodSource.index(after: opening)..<closing])
        return orderedUnique(splitTopLevel(text).compactMap { component in
            let declaration = component.split(separator: "=", maxSplits: 1).first.map(String.init) ?? component
            let prefix = declaration.split(separator: ":", maxSplits: 1).first.map(String.init) ?? declaration
            let identifiers = lexicalIdentifiers(in: prefix)
            let name = language == "go" ? identifiers.first : identifiers.last
            guard let name, !["_", "self", "this"].contains(name) else { return nil }
            return name
        })
    }

    private func matchingClosingParenthesis(in text: String, opening: String.Index) -> String.Index? {
        var depth = 0
        var index = opening
        while index < text.endIndex {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func splitTopLevel(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if "([{<".contains(character) { depth += 1 }
            if ")]} >".filter({ !$0.isWhitespace }).contains(character) { depth = max(0, depth - 1) }
            if character == "," && depth == 0 {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
    }

    private func stableSignature(for node: Node, source: String) -> String {
        let normalized = nodeText(node, source: source).filter { !$0.isWhitespace }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func lastIdentifier(beforeOpeningParenthesisIn text: String) -> String? {
        let prefix = text.split(separator: "(", maxSplits: 1).first.map(String.init) ?? text
        return lastIdentifier(in: prefix)
    }

    private func firstIdentifier(in text: String) -> String? {
        lexicalIdentifiers(in: text).first
    }

    private func lastIdentifier(in text: String) -> String? {
        lexicalIdentifiers(in: text).last
    }

    private func lexicalIdentifiers(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func nodeText(_ node: Node, source: String) -> String {
        let lower = min(max(0, Int(node.byteRange.lowerBound / 2)), source.utf16.count)
        let upper = min(max(lower, Int(node.byteRange.upperBound / 2)), source.utf16.count)
        let start = String.Index(utf16Offset: lower, in: source)
        let end = String.Index(utf16Offset: upper, in: source)
        return String(source[start..<end])
    }

    private func orderedUnique<Element: Hashable>(_ values: [Element]) -> [Element] {
        var seen: Set<Element> = []
        return values.filter { seen.insert($0).inserted }
    }
}

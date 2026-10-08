import Foundation
import SkeletonIndexCore
import SwiftTreeSitter

public struct TreeSitterImplementationEvidenceExtractor: Sendable {
    /// Declared callables across the built-in grammars. They are method candidates and also
    /// scope boundaries: a nested declared function does not contribute to its parent's evidence.
    private static let declaredFunctionNodeTypes: Set<String> = [
        // Swift
        "deinit_declaration", "function_declaration", "init_declaration", "protocol_function_declaration",
        "subscript_declaration",
        // Kotlin
        "anonymous_initializer", "getter", "secondary_constructor", "setter",
        // TypeScript
        "abstract_method_signature", "function_signature", "generator_function_declaration",
        "method_definition", "method_signature",
        // Go
        "method_declaration", "method_elem",
        // Rust
        "function_item", "function_signature_item",
        // Java
        "compact_constructor_declaration", "constructor_declaration",
        // C++ and Python
        "function_definition",
    ]

    /// Body-less C++ member and free function declarations (`void f(int);`, `virtual int g() = 0;`).
    /// They are method candidates only when their declarator is a function declarator.
    private static let functionDeclarationNodeTypes: Set<String> = ["declaration", "field_declaration"]

    /// Anonymous callables. They can be the method node of a field-style method
    /// (`handle = () => {}`) but otherwise belong to the evidence of their enclosing method.
    private static let closureNodeTypes: Set<String> = [
        "arrow_function", "function_expression", "generator_function",
    ]

    /// Nested type declarations are separate blocks; their members are not part of a method.
    private static let nestedTypeNodeTypes: Set<String> = [
        "abstract_class_declaration", "annotation_type_declaration", "class", "class_declaration",
        "class_definition", "class_specifier", "enum_declaration", "enum_item", "enum_specifier",
        "extension_declaration", "impl_item", "interface_declaration", "object_declaration",
        "opaque_declaration", "protocol_declaration", "record_declaration", "struct_declaration",
        "struct_item", "struct_specifier", "trait_item", "type_declaration", "union_declaration",
        "union_item", "union_specifier",
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
        "augmented_assignment_expression", "compound_assignment_expr",
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

    private static let receiverNodeTypes: Set<String> = ["self", "self_expression", "this", "this_expression"]

    private static let literalFragments = [
        "boolean", "character", "float", "integer", "literal", "null", "number", "string",
    ]

    private static let trapNames: Set<String> = [
        "NotImplementedError", "TODO", "UnsupportedOperationException", "abort", "assertionFailure",
        "fatalError", "panic", "preconditionFailure", "todo", "unimplemented", "unreachable",
    ]

    private static let zigDeclarationKeywords: Set<String> = ["const", "var"]

    private struct MethodCandidate {
        let node: Node
        let startLine: Int
        let endLine: Int
        let hasBody: Bool
        /// Lower is preferred: declared functions, then body-less declarations, then closures.
        let rank: Int
        let size: Int
    }

    public init() {}

    public func extract(
        root: Node,
        source: String,
        blocks: [SkeletonBlock],
        language: String
    ) -> [MethodSyntaxEvidence] {
        // One traversal collects every method candidate; each method is then resolved from
        // this index instead of re-walking the tree from the root.
        let candidates = collectMethodCandidates(root: root)
        var exactCandidates: [String: [MethodCandidate]] = [:]
        for candidate in candidates {
            exactCandidates["\(candidate.startLine):\(candidate.endLine)", default: []].append(candidate)
        }

        var result: [MethodSyntaxEvidence] = []
        for block in blocks {
            for method in block.methods {
                guard let methodNode = findMethodNode(
                    range: method.range,
                    exactCandidates: exactCandidates,
                    candidates: candidates
                ) else {
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
        let body = findBody(in: methodNode)
        // Only the signature is materialized; the body is inspected through the AST.
        let signatureText = nodeText(
            lowerBound: methodNode.byteRange.lowerBound,
            upperBound: body?.byteRange.lowerBound ?? methodNode.byteRange.upperBound,
            source: source
        )
        let parameters = parameterNames(from: signatureText, language: language)
        guard let body else {
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

        var summary = summarize(node: body, source: source, language: language)
        if summary.returns.isEmpty, method.returnTypeRef != nil,
           let expression = implicitResultExpression(in: body),
           let implicitReturn = expressionEvidence(expression: expression, source: source) {
            summary.returns.append(implicitReturn)
        }
        let empty = !hasMeaningfulBodyContent(body)
        if !empty {
            summary.executableStatementCount = max(1, summary.executableStatementCount)
        }
        let bodyState: ImplementationFingerprint.BodyState
        if empty && isAbstractRequirement(
            signatureText: signatureText,
            source: source,
            range: method.range,
            language: language
        ) {
            bodyState = .absent
        } else {
            bodyState = empty ? .empty : .concrete
        }
        // Python binds a local on assignment; other languages require a declaration.
        let boundLocals = language == "python" ? summary.writes.filter { !$0.isMember }.map(\.name) : []
        let declaredLocals = Set(summary.localNames).union(boundLocals)
        let externalWrites = summary.writes.compactMap { write -> String? in
            if write.isMember {
                // Member and subscript writes through a local value stay local; through
                // `self`, a parameter, or captured state they are observable.
                return declaredLocals.contains(write.root) ? nil : write.name
            }
            return declaredLocals.contains(write.root) || parameters.contains(write.root) ? nil : write.name
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
            externalWriteTargets: orderedUnique(externalWrites),
            controlFlowPaths: max(1, summary.branchCount + 1),
            throwsError: summary.throwsError,
            trapCalls: summary.trapCalls,
            catches: summary.catches,
            asyncOperations: summary.hasAwait ? ["await"] : [],
            executableStatementCount: summary.executableStatementCount
        )
    }

    private func isAbstractRequirement(
        signatureText: String,
        source: String,
        range: SourceRange,
        language: String
    ) -> Bool {
        let signatureIdentifiers = Set(lexicalIdentifiers(in: signatureText))
        if signatureIdentifiers.contains("abstract") || signatureIdentifiers.contains("abstractmethod") {
            return true
        }
        guard language == "python", let startLine = range.startLine, startLine > 1 else { return false }
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        guard startLine - 1 <= lines.count else { return false }
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

    private struct Write {
        let name: String
        let root: String
        let isMember: Bool
    }

    private struct Summary {
        var identifiers: [String] = []
        var returns: [MethodSyntaxEvidence.ReturnEvidence] = []
        var callTargets: [String] = []
        var assignmentTargets: [String] = []
        var writes: [Write] = []
        var localNames: [String] = []
        var trapCalls: [String] = []
        var catches: [MethodSyntaxEvidence.CatchEvidence] = []
        var branchCount = 0
        var throwsError = false
        var hasAwait = false
        var executableStatementCount = 0
    }

    private func summarize(node: Node, source: String, language: String) -> Summary {
        var summary = Summary()
        walk(node: node, source: source, language: language, isRoot: true, summary: &summary)
        summary.identifiers = orderedUnique(summary.identifiers)
        summary.callTargets = orderedUnique(summary.callTargets)
        summary.assignmentTargets = orderedUnique(summary.assignmentTargets)
        summary.localNames = orderedUnique(summary.localNames)
        summary.trapCalls = orderedUnique(summary.trapCalls)
        return summary
    }

    private func walk(
        node: Node,
        source: String,
        language: String,
        isRoot: Bool,
        summary: inout Summary
    ) {
        let type = node.nodeType ?? ""
        if !isRoot && isNestedScopeNodeType(type) {
            return
        }
        if !isRoot && Self.catchNodeTypes.contains(type) {
            let nested = summarize(node: node, source: source, language: language)
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
        if let declaredNames = localDeclarationNames(node: node, type: type, source: source, language: language) {
            summary.localNames.append(contentsOf: declaredNames)
        } else if let targetNode = assignmentTargetNode(node: node, type: type, language: language) {
            if let target = assignmentTarget(targetNode, source: source) {
                summary.assignmentTargets.append(target)
            }
            if let write = write(targetNode: targetNode, source: source) {
                summary.writes.append(write)
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

        // Anonymous tokens are visited too: Swift `return` and `throw` are unnamed keyword children.
        for child in children(of: node, namedOnly: false) {
            walk(node: child.node, source: source, language: language, isRoot: false, summary: &summary)
        }
    }

    // MARK: - Local declarations and writes

    /// Names introduced by a local declaration node, or nil when the node is not one.
    private func localDeclarationNames(
        node: Node,
        type: String,
        source: String,
        language: String
    ) -> [String]? {
        switch type {
        case "property_declaration":
            if let name = node.child(byFieldName: "name") {
                return descendantIdentifiers(in: name, source: source)
            }
            return children(of: node)
                .filter { ["variable_declaration", "multi_variable_declaration"].contains($0.node.nodeType ?? "") }
                .flatMap { descendantIdentifiers(in: $0.node, source: source) }
        case "lexical_declaration":
            return declaratorNames(of: node, source: source)
        case "variable_declaration":
            if language == "zig" {
                guard isZigDeclaration(node) else { return nil }
                return firstNamedChild(of: node).map { descendantIdentifiers(in: $0, source: source) } ?? []
            }
            return declaratorNames(of: node, source: source)
        case "short_var_declaration":
            return node.child(byFieldName: "left").map { descendantIdentifiers(in: $0, source: source) } ?? []
        case "var_declaration":
            return children(of: node)
                .filter { $0.node.nodeType == "var_spec" }
                .flatMap { spec in
                    children(of: spec.node)
                        .filter { $0.fieldName == "name" }
                        .map { nodeText($0.node, source: source) }
                }
        case "let_declaration":
            return node.child(byFieldName: "pattern").map { descendantIdentifiers(in: $0, source: source) } ?? []
        case "local_variable_declaration":
            return children(of: node)
                .filter { $0.fieldName == "declarator" }
                .compactMap { $0.node.child(byFieldName: "name").map { nodeText($0, source: source) } }
        case "declaration" where language == "cpp":
            return children(of: node)
                .filter { $0.fieldName == "declarator" }
                .compactMap { declaredIdentifier(in: $0.node, source: source) }
        default:
            return nil
        }
    }

    private func declaratorNames(of node: Node, source: String) -> [String] {
        children(of: node)
            .filter { $0.node.nodeType == "variable_declarator" }
            .flatMap { declarator in
                declarator.node.child(byFieldName: "name").map { descendantIdentifiers(in: $0, source: source) } ?? []
            }
    }

    /// Follows C/C++ declarators (`init_declarator`, `pointer_declarator`, ...) to the declared name.
    private func declaredIdentifier(in node: Node, source: String) -> String? {
        var current = node
        while !Self.identifierNodeTypes.contains(current.nodeType ?? "") {
            guard let next = current.child(byFieldName: "declarator") ?? firstNamedChild(of: current) else {
                return nil
            }
            current = next
        }
        return nodeText(current, source: source)
    }

    /// The Zig grammar represents both `const x = v;` and `x = v;` as `variable_declaration`;
    /// only the former starts with a declaration keyword.
    private func isZigDeclaration(_ node: Node) -> Bool {
        children(of: node, namedOnly: false).contains { child in
            !child.node.isNamed && Self.zigDeclarationKeywords.contains(child.node.nodeType ?? "")
        }
    }

    private func assignmentTargetNode(node: Node, type: String, language: String) -> Node? {
        if Self.assignmentNodeTypes.contains(type) {
            return node.child(byFieldName: "left") ?? node.child(byFieldName: "target") ?? firstNamedChild(of: node)
        }
        if language == "zig" && type == "variable_declaration" {
            return firstNamedChild(of: node)
        }
        return nil
    }

    private func assignmentTarget(_ target: Node, source: String) -> String? {
        descendantIdentifiers(in: target, source: source).last
    }

    private func write(targetNode: Node, source: String) -> Write? {
        var target = targetNode
        // Unwrap single-element wrappers such as Go `expression_list` and Swift
        // `directly_assignable_expression` around a bare identifier.
        while !Self.identifierNodeTypes.contains(target.nodeType ?? ""),
              target.namedChildCount == 1,
              let only = firstNamedChild(of: target) {
            target = only
        }
        if Self.identifierNodeTypes.contains(target.nodeType ?? "") {
            let name = nodeText(target, source: source)
            // `_ = value` discards a value; it writes nothing.
            return name == "_" ? nil : Write(name: name, root: name, isMember: false)
        }
        guard let name = assignmentTarget(target, source: source) else { return nil }
        return Write(name: name, root: rootIdentifier(of: target, source: source), isMember: true)
    }

    private func rootIdentifier(of node: Node, source: String) -> String {
        var current = node
        while true {
            let type = current.nodeType ?? ""
            if Self.receiverNodeTypes.contains(type) {
                return "self"
            }
            if Self.identifierNodeTypes.contains(type) {
                return nodeText(current, source: source)
            }
            guard let next = firstNamedChild(of: current) else {
                return ""
            }
            current = next
        }
    }

    // MARK: - Expressions

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
        let kind: MethodSyntaxEvidence.ExpressionKind
        if containsCall {
            let target = callTarget(node: expression, source: source) ?? identifiers.first ?? ""
            kind = target.first?.isUppercase == true ? .constructed : .call
        } else if isLiteralNode(type: expressionType, expression: expression, source: source) {
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
              let child = firstNamedChild(of: candidate) {
            candidate = child
            unwrapped = true
        }
        guard unwrapped else { return nil }
        let type = candidate.nodeType ?? ""
        if Self.returnNodeTypes.contains(type) || Self.throwNodeTypes.contains(type) ||
            Self.assignmentNodeTypes.contains(type) || Self.branchNodeTypes.contains(type) ||
            isNestedScopeNodeType(type) {
            return nil
        }
        return candidate
    }

    /// A body is empty when it holds only comments, `pass`, or a Python `...` placeholder.
    private func hasMeaningfulBodyContent(_ node: Node, isRoot: Bool = true) -> Bool {
        let type = node.nodeType ?? ""
        if !isRoot && (type == "comment" || type == "doc_comment" || type == "pass_statement") {
            return false
        }
        if !isRoot && isEllipsisOnly(node) {
            return false
        }
        if !isRoot && node.isNamed && !Self.bodyNodeTypes.contains(type) && type != "statements" {
            return true
        }
        return children(of: node).contains { hasMeaningfulBodyContent($0.node, isRoot: false) }
    }

    private func isEllipsisOnly(_ node: Node) -> Bool {
        if node.nodeType == "ellipsis" {
            return true
        }
        guard node.nodeType == "expression_statement", node.namedChildCount == 1,
              let only = firstNamedChild(of: node) else {
            return false
        }
        return isEllipsisOnly(only)
    }

    private func callTarget(node: Node, source: String) -> String? {
        if node.nodeType == "macro_invocation" {
            let macro = node.child(byFieldName: "macro") ?? firstNamedChild(of: node)
            return macro.flatMap { descendantIdentifiers(in: $0, source: source).last }
        }
        let targetNode = node.child(byFieldName: "function") ?? node.child(byFieldName: "name") ??
            node.child(byFieldName: "callee") ?? node.child(byFieldName: "method") ??
            node.child(byFieldName: "constructor") ?? node.child(byFieldName: "type") ??
            firstNamedChild(of: node)
        guard let targetNode else { return nil }
        if Self.identifierNodeTypes.contains(targetNode.nodeType ?? "") {
            return nodeText(targetNode, source: source)
        }
        if let last = calleeIdentifier(in: targetNode, source: source) {
            return last
        }
        // Builtins such as Zig `@panic` have no identifier node; the callee node itself is short.
        return lexicalIdentifiers(in: nodeText(targetNode, source: source)).last
    }

    /// The last identifier of a callee expression, ignoring identifiers inside nested argument lists.
    private func calleeIdentifier(in node: Node, source: String) -> String? {
        var last: String?
        for child in children(of: node) {
            let type = child.node.nodeType ?? ""
            if type.contains("argument") || type.contains("call_suffix") || type.contains("type_arguments") {
                continue
            }
            if Self.identifierNodeTypes.contains(type) {
                last = nodeText(child.node, source: source)
            } else if let nested = calleeIdentifier(in: child.node, source: source) {
                last = nested
            }
        }
        return last
    }

    // MARK: - Method lookup

    private func collectMethodCandidates(root: Node) -> [MethodCandidate] {
        var candidates: [MethodCandidate] = []
        let cursor = root.treeCursor
        var reachedEnd = false
        while !reachedEnd {
            if let node = cursor.currentNode, node.isNamed, let rank = candidateRank(of: node) {
                candidates.append(MethodCandidate(
                    node: node,
                    startLine: Int(node.pointRange.lowerBound.row) + 1,
                    endLine: Int(node.pointRange.upperBound.row) + 1,
                    hasBody: findBody(in: node) != nil,
                    rank: rank,
                    size: node.byteRange.count
                ))
            }
            if cursor.goToFirstChild() || cursor.gotoNextSibling() {
                continue
            }
            while true {
                guard cursor.gotoParent() else {
                    reachedEnd = true
                    break
                }
                if cursor.gotoNextSibling() {
                    break
                }
            }
        }
        return candidates
    }

    private func candidateRank(of node: Node) -> Int? {
        let type = node.nodeType ?? ""
        if Self.declaredFunctionNodeTypes.contains(type) {
            return 0
        }
        if Self.functionDeclarationNodeTypes.contains(type),
           node.child(byFieldName: "declarator")?.nodeType == "function_declarator" {
            return 1
        }
        if Self.closureNodeTypes.contains(type) {
            return 2
        }
        return nil
    }

    private func findMethodNode(
        range: SourceRange,
        exactCandidates: [String: [MethodCandidate]],
        candidates: [MethodCandidate]
    ) -> Node? {
        guard let startLine = range.startLine else { return nil }
        let endLine = range.endLine ?? startLine
        let exact = exactCandidates["\(startLine):\(endLine)"] ?? []
        let pool = exact.isEmpty
            ? candidates.filter { $0.startLine <= startLine && $0.endLine >= endLine }
            : exact
        return pool.min { lhs, rhs in
            if lhs.hasBody != rhs.hasBody { return lhs.hasBody }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.size < rhs.size
        }?.node
    }

    private func findBody(in methodNode: Node) -> Node? {
        for field in ["body", "value"] {
            if let child = methodNode.child(byFieldName: field), isBodyOrExpression(child) {
                return child
            }
        }
        return children(of: methodNode).first { isBodyOrExpression($0.node) }?.node
    }

    private func isBodyOrExpression(_ node: Node) -> Bool {
        let type = node.nodeType ?? ""
        if Self.bodyNodeTypes.contains(type) { return true }
        return type.hasSuffix("expression") && type != "type_expression"
    }

    private func isNestedScopeNodeType(_ type: String) -> Bool {
        Self.declaredFunctionNodeTypes.contains(type) || Self.nestedTypeNodeTypes.contains(type)
    }

    private func isExecutableLeaf(type: String, node: Node) -> Bool {
        guard node.namedChildCount == 0 else { return false }
        return type.hasSuffix("statement") && !Self.returnNodeTypes.contains(type) &&
            !Self.throwNodeTypes.contains(type) && type != "empty_statement" && type != "pass_statement"
    }

    // MARK: - Tree helpers

    /// Children in order via a tree cursor; `Node.child(at:)` is linear in the index,
    /// which made iterating wide nodes quadratic.
    private func children(of node: Node, namedOnly: Bool = true) -> [(node: Node, fieldName: String?)] {
        var result: [(node: Node, fieldName: String?)] = []
        let cursor = node.treeCursor
        guard cursor.goToFirstChild() else { return result }
        repeat {
            if let child = cursor.currentNode, !namedOnly || child.isNamed {
                result.append((child, cursor.currentFieldName))
            }
        } while cursor.gotoNextSibling()
        return result
    }

    private func firstNamedChild(of node: Node) -> Node? {
        children(of: node).first?.node
    }

    private func firstMeaningfulNamedChild(of node: Node) -> Node? {
        children(of: node).first { !($0.node.nodeType ?? "").contains("type") }?.node
    }

    private func containsNode(in node: Node, predicate: (String) -> Bool) -> Bool {
        if predicate(node.nodeType ?? "") { return true }
        return children(of: node).contains { containsNode(in: $0.node, predicate: predicate) }
    }

    private func descendantIdentifiers(in node: Node, source: String) -> [String] {
        var values: [String] = []
        collectIdentifiers(node: node, source: source, into: &values)
        return values
    }

    private func collectIdentifiers(node: Node, source: String, into values: inout [String]) {
        if Self.identifierNodeTypes.contains(node.nodeType ?? "") {
            values.append(nodeText(node, source: source))
        }
        for child in children(of: node) {
            collectIdentifiers(node: child.node, source: source, into: &values)
        }
    }

    private func isLiteralNode(type: String, expression: Node, source: String) -> Bool {
        if Self.literalFragments.contains(where: type.contains) { return true }
        // Keyword literals and bare numbers without a literal node type are short leaves.
        guard expression.namedChildCount == 0, expression.byteRange.count <= 64 else { return false }
        let trimmed = nodeText(expression, source: source).trimmingCharacters(in: .whitespacesAndNewlines)
        return ["false", "nil", "null", "none", "true"].contains(trimmed.lowercased()) || Double(trimmed) != nil
    }

    private func parameterNames(from signatureText: String, language: String) -> [String] {
        guard let opening = signatureText.firstIndex(of: "("),
              let closing = matchingClosingParenthesis(in: signatureText, opening: opening) else { return [] }
        let text = String(signatureText[signatureText.index(after: opening)..<closing])
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
            if ")]}>".contains(character) { depth = max(0, depth - 1) }
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

    /// FNV-1a over the expression's non-whitespace UTF-16 units, read in place from the source.
    private func stableSignature(for node: Node, source: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let (start, end) = utf16Bounds(
            lowerBound: node.byteRange.lowerBound,
            upperBound: node.byteRange.upperBound,
            source: source
        )
        for unit in source.utf16[start..<end] where !isWhitespaceUnit(unit) {
            hash ^= UInt64(unit & 0xFF)
            hash &*= 1_099_511_628_211
            if unit > 0xFF {
                hash ^= UInt64(unit >> 8)
                hash &*= 1_099_511_628_211
            }
        }
        return String(hash, radix: 16)
    }

    private func isWhitespaceUnit(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
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
        nodeText(lowerBound: node.byteRange.lowerBound, upperBound: node.byteRange.upperBound, source: source)
    }

    private func nodeText(lowerBound: UInt32, upperBound: UInt32, source: String) -> String {
        let (start, end) = utf16Bounds(lowerBound: lowerBound, upperBound: upperBound, source: source)
        return String(source[start..<end])
    }

    /// SwiftTreeSitter parses Swift strings as UTF-16, so byte offsets are twice the UTF-16 offset.
    private func utf16Bounds(
        lowerBound: UInt32,
        upperBound: UInt32,
        source: String
    ) -> (String.Index, String.Index) {
        let count = source.utf16.count
        let lower = min(max(0, Int(lowerBound / 2)), count)
        let upper = min(max(lower, Int(upperBound / 2)), count)
        return (String.Index(utf16Offset: lower, in: source), String.Index(utf16Offset: upper, in: source))
    }

    private func orderedUnique<Element: Hashable>(_ values: [Element]) -> [Element] {
        var seen: Set<Element> = []
        return values.filter { seen.insert($0).inserted }
    }
}

import Foundation

public struct DeclarationExtractor: Sendable {
    private let rules: any LanguageRules

    public init(rules: any LanguageRules) {
        self.rules = rules
    }

    public func extract(from node: DeclarationNode) -> SkeletonBlock? {
        guard let declaration = declarationHeader(from: node.snippet) else {
            return nil
        }

        let range = SourceRange(
            startLine: node.startLine,
            endLine: node.endLine
        )

        let members = parseMembers(in: node.snippet, declarationStartLine: node.startLine)

        return SkeletonBlock(
            kind: declaration.kind,
            typeName: declaration.typeName,
            inheritance: declaration.inheritance,
            range: range,
            properties: members.properties,
            methods: members.methods,
            hasErrorNode: node.hasError
        )
    }

    // MARK: - Declaration Header

    private func declarationHeader(from snippet: String) -> (kind: SkeletonBlockKind, typeName: String, inheritance: [String])? {
        let header = snippet.split(separator: "{", maxSplits: 1).first.map(String.init) ?? snippet
        let compact = header.replacingOccurrences(of: "\n", with: " ")

        if let extensionPattern = rules.extensionPattern {
            let fullPattern = #"\b"# + extensionPattern.keyword + #"\s+"# + extensionPattern.typeNamePattern
            if let typeName = TextUtilities.firstRegex(pattern: fullPattern, in: compact) {
                return (kind: .extension, typeName: typeName, inheritance: rules.parseInheritance(from: compact))
            }
        }

        guard let keyword = TextUtilities.firstRegex(pattern: rules.typeKeywordPattern, in: compact) else {
            return nil
        }
        guard let typeName = TextUtilities.firstRegex(pattern: rules.typeNamePattern, in: compact) else {
            return nil
        }
        return (kind: .type(keyword), typeName: typeName, inheritance: rules.parseInheritance(from: compact))
    }

    // MARK: - Members

    private func parseMembers(in snippet: String, declarationStartLine: Int) -> (properties: [PropertySignature], methods: [MethodSignature]) {
        let lines = snippet.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.isEmpty {
            return ([], [])
        }

        var properties: [PropertySignature] = []
        var methods: [MethodSignature] = []
        var depth = 0
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let depthBefore = depth
            if depthBefore == 1 {
                if let capture = TextUtilities.firstRegexCapture(
                    pattern: rules.propertyPattern,
                    in: line
                ) {
                    properties.append(PropertySignature(name: capture.0, typeRef: capture.1))
                }

                if let method = parseMethodLine(
                    line: line,
                    lineIndex: lineIndex,
                    lines: lines,
                    declarationStartLine: declarationStartLine
                ) {
                    methods.append(method)
                }
            }
            depth += TextUtilities.braceBalance(line)
            lineIndex += 1
        }

        return (properties, methods)
    }

    // MARK: - Method Parsing

    private func parseMethodLine(
        line: String,
        lineIndex: Int,
        lines: [String],
        declarationStartLine: Int
    ) -> MethodSignature? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodStart = rules.parseMethodStart(from: trimmed) else {
            return nil
        }

        let fullSignature = TextUtilities.collectFullSignature(lines: lines, startIndex: lineIndex)
        let params = TextUtilities.parseParameterTypeRefs(TextUtilities.betweenParentheses(fullSignature) ?? "")
        let returnType = methodStart.isInitializer ? nil : parseReturnType(fullSignature)
        let startLine = declarationStartLine + lineIndex
        let endLine = TextUtilities.blockEndLine(lines: lines, startIndex: lineIndex).map { declarationStartLine + $0 }

        return MethodSignature(
            name: methodStart.name,
            parameterTypeRefs: params,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: methodStart.isInitializer
        )
    }

    // MARK: - Return Type

    private func parseReturnType(_ signatureText: String) -> String? {
        guard let closeIndex = closingParenIndex(in: signatureText) else {
            return nil
        }
        let afterParen = String(signatureText[signatureText.index(after: closeIndex)...])
        guard let tokenRange = afterParen.range(of: rules.returnTypeToken) else {
            return nil
        }
        var returnText = String(afterParen[tokenRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let brace = returnText.firstIndex(of: "{") {
            returnText = String(returnText[..<brace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        returnText = rules.cleanReturnType(returnText)
        return returnText.isEmpty ? nil : returnText
    }

    private func closingParenIndex(in text: String) -> String.Index? {
        var depth = 0
        for index in text.indices {
            let char = text[index]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }
}

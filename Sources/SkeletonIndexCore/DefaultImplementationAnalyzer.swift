import Foundation

public struct DefaultImplementationAnalyzer: ImplementationAnalyzing, Sendable {
    private struct BodySlice {
        let state: ImplementationFingerprint.BodyState
        let raw: String
        let sanitized: String
        let isExpression: Bool
    }

    public init() {}

    public func analyze(
        path: String,
        blocks: [SkeletonBlock],
        source: String,
        language: String
    ) -> FileImplementationAnalysis {
        var methods: [MethodImplementationAnalysis] = []
        var findings: [ImplementationFinding] = []

        for block in blocks {
            for method in block.methods {
                let methodSource = sourceSlice(source: source, range: method.range)
                var body = extractBody(from: methodSource, language: language)
                if isAbstractRequirement(
                    methodSource: methodSource,
                    source: source,
                    range: method.range,
                    language: language,
                    body: body
                ) {
                    body = BodySlice(state: .absent, raw: "", sanitized: "", isExpression: false)
                }
                let parameters = parameterNames(from: methodSource, language: language)
                let fingerprint = makeFingerprint(
                    body: body,
                    parameters: parameters,
                    properties: block.properties.map(\.name),
                    range: method.range,
                    blockHasError: block.hasErrorNode
                )
                let analysis = MethodImplementationAnalysis(
                    typeName: block.typeName,
                    methodName: method.name,
                    range: method.range,
                    isInitializer: method.isInitializer,
                    fingerprint: fingerprint
                )
                methods.append(analysis)
                findings.append(contentsOf: makeFindings(
                    analysis: analysis,
                    parameters: parameters,
                    body: body
                ))
            }
        }

        return FileImplementationAnalysis(
            language: language,
            methods: methods,
            findings: findings
        )
    }

    private func makeFingerprint(
        body: BodySlice,
        parameters: [String],
        properties: [String],
        range: SourceRange,
        blockHasError: Bool
    ) -> ImplementationFingerprint {
        let identifiers = identifierSet(in: body.sanitized)
        let parameterReads = parameters.filter { identifiers.contains($0) }
        let stateReads = properties.filter { identifiers.contains($0) }
        let stateWrites = properties.filter { isAssigned(identifier: $0, in: body.sanitized) }
        let calls = callTargets(in: body.sanitized)
        let returnExpressions = extractedReturnExpressions(from: body.raw, isExpression: body.isExpression)
        let returnOrigins = orderedUnique(returnExpressions.map {
            returnOrigin(
                expression: $0,
                parameters: parameters,
                properties: properties,
                calls: calls
            )
        })
        let traps = containsTrap(in: body.sanitized)
        let throwsError = containsAnyIdentifier(["throw", "throws", "raise"], in: body.sanitized)
        let caughtErrors = caughtErrorMarkers(in: body.sanitized)
        let asyncOperations = containsIdentifier("await", in: body.sanitized) ? ["await"] : []
        let syntaxState: ImplementationFingerprint.SyntaxState =
            blockHasError || range.startLine == nil || range.endLine == nil ? .incomplete : .complete

        var terminalBehaviors: [ImplementationFingerprint.TerminalBehavior] = []
        if traps {
            terminalBehaviors.append(.traps)
        }
        if throwsError {
            terminalBehaviors.append(.throwsError)
        }
        if !returnExpressions.isEmpty {
            terminalBehaviors.append(.returns)
        }
        if terminalBehaviors.isEmpty && body.state == .concrete {
            terminalBehaviors.append(.fallsThrough)
        }

        var externalEffects = stateWrites.map { "write:\($0)" }
        externalEffects.append(contentsOf: calls.map { "call:\($0)" })
        if throwsError {
            externalEffects.append("throw")
        }

        return ImplementationFingerprint(
            bodyState: body.state,
            syntaxState: syntaxState,
            parameterReads: parameterReads,
            returnOrigins: returnOrigins,
            stateReads: stateReads,
            stateWrites: stateWrites,
            callTargets: calls,
            controlFlowPaths: controlFlowPathCount(in: body.sanitized),
            terminalBehaviors: orderedUnique(terminalBehaviors),
            caughtErrors: caughtErrors,
            asyncOperations: asyncOperations,
            externalEffects: orderedUnique(externalEffects)
        )
    }

    private func makeFindings(
        analysis: MethodImplementationAnalysis,
        parameters: [String],
        body: BodySlice
    ) -> [ImplementationFinding] {
        let fingerprint = analysis.fingerprint
        guard fingerprint.bodyState != .absent, fingerprint.syntaxState == .complete else {
            return []
        }

        var findings: [ImplementationFinding] = []
        if fingerprint.terminalBehaviors.contains(.traps) {
            findings.append(finding(analysis: analysis, certainty: .definite, domain: .body, reason: .trap))
        }
        if fingerprint.bodyState == .empty {
            if analysis.isInitializer {
                return findings
            }
            findings.append(finding(analysis: analysis, certainty: .definite, domain: .body, reason: .empty))
            return findings
        }

        let unusedInputs = !parameters.isEmpty && fingerprint.parameterReads.isEmpty
        let hasLiteralOnlyReturn = !fingerprint.returnOrigins.isEmpty &&
            Set(fingerprint.returnOrigins) == Set([.literal])
        let hasObservableWork = !fingerprint.stateWrites.isEmpty ||
            !fingerprint.callTargets.isEmpty ||
            fingerprint.terminalBehaviors.contains(.throwsError)

        if hasLiteralOnlyReturn && unusedInputs && !hasObservableWork {
            findings.append(finding(analysis: analysis, certainty: .suspicious, domain: .body, reason: .constant))
        }

        if !analysis.isInitializer && fingerprint.returnOrigins.isEmpty && !hasObservableWork &&
            !fingerprint.terminalBehaviors.contains(.traps) {
            findings.append(finding(analysis: analysis, certainty: .suspicious, domain: .body, reason: .noOperation))
        }

        if !fingerprint.caughtErrors.isEmpty &&
            !containsAnyIdentifier(["throw", "raise"], in: body.sanitized) &&
            !fingerprint.terminalBehaviors.contains(.returns) &&
            !containsLoggingCall(fingerprint.callTargets) {
            findings.append(finding(analysis: analysis, certainty: .suspicious, domain: .error, reason: .error))
        }

        let returnExpressions = extractedReturnExpressions(from: body.raw, isExpression: body.isExpression)
            .map(normalizedExpression)
            .filter { !$0.isEmpty }
        if fingerprint.controlFlowPaths > 1 && returnExpressions.count > 1 &&
            Set(returnExpressions).count == 1 && returnExpressions.allSatisfy(isLiteralExpression) {
            findings.append(finding(analysis: analysis, certainty: .suspicious, domain: .flow, reason: .flow))
        }

        return findings
    }

    private func finding(
        analysis: MethodImplementationAnalysis,
        certainty: ImplementationFinding.Certainty,
        domain: ImplementationFinding.Domain,
        reason: ImplementationFinding.Reason
    ) -> ImplementationFinding {
        ImplementationFinding(
            scope: .method,
            typeName: analysis.typeName,
            methodName: analysis.methodName,
            range: analysis.range,
            certainty: certainty,
            domain: domain,
            reason: reason
        )
    }

    private func sourceSlice(source: String, range: SourceRange) -> String {
        guard let startLine = range.startLine else {
            return ""
        }
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty, startLine > 0, startLine <= lines.count else {
            return ""
        }
        let endLine = min(max(range.endLine ?? startLine, startLine), lines.count)
        return lines[(startLine - 1)..<endLine].joined(separator: "\n")
    }

    private func extractBody(from methodSource: String, language: String) -> BodySlice {
        let trimmed = methodSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return BodySlice(state: .absent, raw: "", sanitized: "", isExpression: false)
        }

        if language == "python" {
            return extractPythonBody(from: methodSource)
        }

        let signatureEnd = matchingClosingParenthesis(in: methodSource)
        let searchStart = signatureEnd.map { methodSource.index(after: $0) } ?? methodSource.startIndex
        if let openingBrace = methodSource[searchStart...].firstIndex(of: "{"),
           let closingBrace = methodSource.lastIndex(of: "}"), openingBrace < closingBrace {
            let raw = String(methodSource[methodSource.index(after: openingBrace)..<closingBrace])
            return concreteBody(raw: raw, isExpression: false)
        }

        let tail = String(methodSource[searchStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if supportsExpressionBody(language: language),
           let equals = assignmentEquals(in: tail) {
            let expression = String(tail[tail.index(after: equals)...])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))
            return concreteBody(raw: expression, isExpression: true)
        }

        return BodySlice(state: .absent, raw: "", sanitized: "", isExpression: false)
    }

    private func extractPythonBody(from methodSource: String) -> BodySlice {
        guard let closingParenthesis = matchingClosingParenthesis(in: methodSource),
              let colon = methodSource[closingParenthesis...].firstIndex(of: ":") else {
            return BodySlice(state: .absent, raw: "", sanitized: "", isExpression: false)
        }
        let raw = String(methodSource[methodSource.index(after: colon)...])
        return concreteBody(raw: raw, isExpression: false)
    }

    private func isAbstractRequirement(
        methodSource: String,
        source: String,
        range: SourceRange,
        language: String,
        body: BodySlice
    ) -> Bool {
        guard body.state == .empty else {
            return false
        }
        let signatureIdentifiers = identifierSet(in: methodSource)
        if signatureIdentifiers.contains("abstract") {
            return true
        }
        guard language == "python", let startLine = range.startLine, startLine > 1 else {
            return false
        }
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var lineIndex = startLine - 2
        while lineIndex >= 0 {
            let line = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                lineIndex -= 1
                continue
            }
            guard line.hasPrefix("@") else {
                break
            }
            if identifierSet(in: line).contains("abstractmethod") {
                return true
            }
            lineIndex -= 1
        }
        return false
    }

    private func concreteBody(raw: String, isExpression: Bool) -> BodySlice {
        let sanitized = sanitizedSource(raw)
        let compact = sanitized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ";", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let emptyTokens: Set<String> = ["", "pass", "...", "todo", "TODO"]
        let state: ImplementationFingerprint.BodyState = emptyTokens.contains(compact) ? .empty : .concrete
        return BodySlice(state: state, raw: raw, sanitized: sanitized, isExpression: isExpression)
    }

    private func supportsExpressionBody(language: String) -> Bool {
        ["kotlin", "typescript", "zig"].contains(language)
    }

    private func matchingClosingParenthesis(in text: String) -> String.Index? {
        guard let opening = text.firstIndex(of: "(") else {
            return nil
        }
        var depth = 0
        var index = opening
        while index < text.endIndex {
            let character = text[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func assignmentEquals(in text: String) -> String.Index? {
        for index in text.indices where text[index] == "=" {
            let previous = index > text.startIndex ? text[text.index(before: index)] : " "
            let nextIndex = text.index(after: index)
            let next = nextIndex < text.endIndex ? text[nextIndex] : " "
            if previous != "=" && previous != "!" && previous != "<" && previous != ">" && next != "=" && next != ">" {
                return index
            }
        }
        return nil
    }

    private func parameterNames(from methodSource: String, language: String) -> [String] {
        guard let opening = methodSource.firstIndex(of: "("),
              let closing = matchingClosingParenthesis(in: methodSource), opening < closing else {
            return []
        }
        let parameterText = String(methodSource[methodSource.index(after: opening)..<closing])
        let components = splitTopLevel(parameterText, separator: ",")
        var names: [String] = []

        for component in components {
            let withoutDefault = component.split(separator: "=", maxSplits: 1).first.map(String.init) ?? component
            let candidate: String
            if let colon = withoutDefault.firstIndex(of: ":") {
                let prefix = String(withoutDefault[..<colon])
                candidate = lastIdentifier(in: prefix) ?? ""
            } else if language == "go" {
                candidate = identifiers(in: withoutDefault).first ?? ""
            } else {
                candidate = lastIdentifier(in: withoutDefault) ?? ""
            }
            if !candidate.isEmpty && candidate != "_" && candidate != "self" && candidate != "this" {
                names.append(candidate)
            }
        }
        return orderedUnique(names)
    }

    private func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var results: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if "([{<".contains(character) {
                depth += 1
            } else if ")]} >".filter({ !$0.isWhitespace }).contains(character) {
                depth = max(0, depth - 1)
            }
            if character == separator && depth == 0 {
                results.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        results.append(current)
        return results
    }

    private func lastIdentifier(in text: String) -> String? {
        identifiers(in: text).last
    }

    private func identifierSet(in text: String) -> Set<String> {
        Set(identifiers(in: text))
    }

    private func identifiers(in text: String) -> [String] {
        var results: [String] = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                results.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }

    private func containsIdentifier(_ identifier: String, in text: String) -> Bool {
        identifierSet(in: text).contains(identifier)
    }

    private func containsAnyIdentifier(_ identifiers: [String], in text: String) -> Bool {
        let found = identifierSet(in: text)
        return identifiers.contains { found.contains($0) }
    }

    private func callTargets(in text: String) -> [String] {
        let excluded: Set<String> = [
            "if", "for", "while", "switch", "catch", "guard", "return", "throw", "raise",
            "sizeof", "typeof", "alignof", "match", "when", "synchronized",
        ]
        var results: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index] == "_" else {
                index = text.index(after: index)
                continue
            }
            let start = index
            index = text.index(after: index)
            while index < text.endIndex && (text[index].isLetter || text[index].isNumber || text[index] == "_") {
                index = text.index(after: index)
            }
            let identifier = String(text[start..<index])
            var lookahead = index
            while lookahead < text.endIndex && text[lookahead].isWhitespace {
                lookahead = text.index(after: lookahead)
            }
            if lookahead < text.endIndex && text[lookahead] == "(" && !excluded.contains(identifier) {
                results.append(identifier)
            }
        }
        return orderedUnique(results)
    }

    private func containsTrap(in text: String) -> Bool {
        let trapCalls: Set<String> = [
            "fatalError", "preconditionFailure", "assertionFailure", "panic", "todo", "unimplemented",
            "NotImplementedError", "UnsupportedOperationException", "abort", "unreachable",
        ]
        return !trapCalls.isDisjoint(with: identifierSet(in: text)) || containsIdentifier("TODO", in: text)
    }

    private func extractedReturnExpressions(from raw: String, isExpression: Bool) -> [String] {
        if isExpression {
            return [raw.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        var expressions: [String] = []
        let lines = raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for keyword in ["return", "raise", "throw"] {
                if trimmed == keyword {
                    expressions.append("")
                } else if trimmed.hasPrefix(keyword + " ") {
                    let value = String(trimmed.dropFirst(keyword.count))
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";}")))
                    expressions.append(value)
                }
            }
        }
        if expressions.isEmpty {
            let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let structure = sanitizedSource(compact).trimmingCharacters(in: .whitespacesAndNewlines)
            let statementKeywords = ["let ", "var ", "if ", "for ", "while ", "switch ", "guard ", "do ", "defer "]
            let beginsWithStatement = statementKeywords.contains { structure.hasPrefix($0) }
            if !compact.isEmpty && !beginsWithStatement &&
                assignmentEquals(in: structure) == nil && !structure.contains(";") {
                expressions.append(compact)
            }
        }
        return expressions
    }

    private func returnOrigin(
        expression: String,
        parameters: [String],
        properties: [String],
        calls: [String]
    ) -> ImplementationFingerprint.ReturnOrigin {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let expressionIdentifiers = identifierSet(in: sanitizedSource(trimmed))
        if isLiteralExpression(trimmed) {
            return .literal
        }
        if parameters.contains(where: { expressionIdentifiers.contains($0) }) {
            return .parameter
        }
        if properties.contains(where: { expressionIdentifiers.contains($0) }) {
            return .state
        }
        if calls.contains(where: { expressionIdentifiers.contains($0) }) {
            return .call
        }
        if trimmed.contains("(") || trimmed.contains("{") || trimmed.contains("[") {
            return .constructed
        }
        return .unknown
    }

    private func isLiteralExpression(_ expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }
        let words: Set<String> = ["true", "false", "nil", "null", "none", "None", "undefined", "void"]
        if words.contains(trimmed) || trimmed.hasPrefix(".none") {
            return true
        }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) ||
            (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) ||
            (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) {
            return true
        }
        return Double(trimmed.replacingOccurrences(of: "_", with: "")) != nil
    }

    private func isAssigned(identifier: String, in text: String) -> Bool {
        let characters = Array(text)
        let needle = Array(identifier)
        guard !needle.isEmpty, characters.count >= needle.count else {
            return false
        }
        for start in 0...(characters.count - needle.count) where Array(characters[start..<(start + needle.count)]) == needle {
            let beforeIsIdentifier = start > 0 && isIdentifierCharacter(characters[start - 1])
            let afterPosition = start + needle.count
            let afterIsIdentifier = afterPosition < characters.count && isIdentifierCharacter(characters[afterPosition])
            if beforeIsIdentifier || afterIsIdentifier {
                continue
            }
            var cursor = afterPosition
            while cursor < characters.count && characters[cursor].isWhitespace {
                cursor += 1
            }
            if cursor < characters.count && characters[cursor] == "=" {
                let next = cursor + 1 < characters.count ? characters[cursor + 1] : " "
                if next != "=" && next != ">" {
                    return true
                }
            }
        }
        return false
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private func controlFlowPathCount(in text: String) -> Int {
        let branchIdentifiers: Set<String> = ["if", "else", "case", "catch", "except", "guard", "match", "when"]
        let count = identifiers(in: text).filter { branchIdentifiers.contains($0) }.count
        return max(1, 1 + count)
    }

    private func caughtErrorMarkers(in text: String) -> [String] {
        let markers = ["catch", "except", "rescue"]
        return markers.filter { containsIdentifier($0, in: text) }
    }

    private func containsLoggingCall(_ calls: [String]) -> Bool {
        let loggingCalls: Set<String> = ["print", "println", "log", "debug", "info", "warn", "warning", "error"]
        return !loggingCalls.isDisjoint(with: Set(calls))
    }

    private func normalizedExpression(_ expression: String) -> String {
        expression.filter { !$0.isWhitespace && $0 != ";" && $0 != "}" }
    }

    private func sanitizedSource(_ source: String) -> String {
        enum State {
            case code
            case lineComment
            case blockComment
            case string(Character)
        }

        let characters = Array(source)
        var output = Array(repeating: Character(" "), count: characters.count)
        var state = State.code
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : "\0"
            switch state {
            case .code:
                if character == "/" && next == "/" {
                    state = .lineComment
                    index += 1
                } else if character == "/" && next == "*" {
                    state = .blockComment
                    index += 1
                } else if character == "#" {
                    state = .lineComment
                } else if character == "\"" || character == "'" || character == "`" {
                    state = .string(character)
                } else {
                    output[index] = character
                }
            case .lineComment:
                if character == "\n" {
                    output[index] = character
                    state = .code
                }
            case .blockComment:
                if character == "*" && next == "/" {
                    state = .code
                    index += 1
                } else if character == "\n" {
                    output[index] = character
                }
            case .string(let quote):
                if character == "\\" {
                    index += 1
                } else if character == quote {
                    state = .code
                } else if character == "\n" {
                    output[index] = character
                }
            }
            index += 1
        }
        return String(output)
    }

    private func orderedUnique<Element: Hashable>(_ values: [Element]) -> [Element] {
        var seen: Set<Element> = []
        return values.filter { seen.insert($0).inserted }
    }
}

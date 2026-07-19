import Foundation

public struct DefaultImplementationContextResolver: ImplementationContextResolving, Sendable {
    private struct ProjectIdentifierIndex {
        let identifierCounts: [String: Int]
        let callCounts: [String: Int]
    }

    private enum SourceDialect {
        case swift
        case kotlin
        case typeScript
        case python
        case cStyle

        init(path: String) {
            switch URL(fileURLWithPath: path).pathExtension.lowercased() {
            case "swift": self = .swift
            case "kt", "kts": self = .kotlin
            case "js", "jsx", "mjs", "cjs", "ts", "tsx": self = .typeScript
            case "py": self = .python
            default: self = .cStyle
            }
        }
    }

    private enum InterpolationStyle {
        case none
        case swift
        case dollar
        case python
    }

    private enum ScanMode {
        case code(terminator: Character?, depth: Int)
        case lineComment
        case blockComment
        case string(quote: Character, delimiterLength: Int, interpolation: InterpolationStyle)
    }

    public init() {}

    public func resolve(
        files: [String: ParsedFile],
        sources: [String: String]
    ) -> [String: ParsedFile] {
        let productionSources = sources.filter { !isNonProduction(path: $0.key) }
        let identifierIndex = makeIdentifierIndex(sources: productionSources)
        var resolvedFiles: [String: ParsedFile] = [:]

        for path in files.keys.sorted() {
            guard let file = files[path] else {
                continue
            }
            let nonProduction = isNonProduction(path: path)
            let source = sources[path] ?? ""
            var resolvedMethods: [MethodImplementationAnalysis] = []
            var findings = nonProduction ? [] : file.implementationAnalysis.findings

            for method in file.implementationAnalysis.methods {
                let binding = implementationBinding(
                    typeName: method.typeName,
                    nonProduction: nonProduction
                )
                let reachability = productionReachability(
                    method: method,
                    source: source,
                    path: path,
                    identifierIndex: identifierIndex,
                    nonProduction: nonProduction
                )
                let fingerprint = method.fingerprint.resolving(
                    reachability: reachability,
                    binding: binding
                )
                resolvedMethods.append(method.resolving(fingerprint: fingerprint))

                if reachability == .unreferenced {
                    findings.append(ImplementationFinding(
                        scope: .method,
                        typeName: method.typeName,
                        methodName: method.methodName,
                        range: method.range,
                        certainty: .suspicious,
                        domain: .dead,
                        reason: .dead
                    ))
                }
            }

            if !nonProduction {
                findings.append(contentsOf: wiringFindings(
                    file: file,
                    identifierIndex: identifierIndex
                ))
            }

            let analysis = FileImplementationAnalysis(
                language: file.implementationAnalysis.language,
                methods: resolvedMethods,
                findings: uniqueFindings(findings)
            )
            resolvedFiles[path] = file.replacing(implementationAnalysis: analysis)
        }

        return resolvedFiles
    }

    private func productionReachability(
        method: MethodImplementationAnalysis,
        source: String,
        path: String,
        identifierIndex: ProjectIdentifierIndex,
        nonProduction: Bool
    ) -> ImplementationFingerprint.ProductionReachability {
        if nonProduction {
            return .nonProduction
        }
        let methodSource = sourceSlice(source: source, range: method.range)
        guard isExplicitlyPrivate(methodSource: methodSource, path: path) else {
            return .external
        }
        let references = identifierIndex.identifierCounts[method.methodName, default: 0]
        return references > 1 ? .referenced : .unreferenced
    }

    private func implementationBinding(
        typeName: String,
        nonProduction: Bool
    ) -> ImplementationFingerprint.ImplementationBinding {
        if nonProduction {
            return .testOnly
        }
        return isFakeLike(typeName: typeName) ? .fakeLike : .production
    }

    private func wiringFindings(
        file: ParsedFile,
        identifierIndex: ProjectIdentifierIndex
    ) -> [ImplementationFinding] {
        var findings: [ImplementationFinding] = []
        for block in file.blocks where isFakeLike(typeName: block.typeName) {
            if identifierIndex.callCounts[block.typeName, default: 0] > 0 {
                findings.append(ImplementationFinding(
                    scope: .type,
                    typeName: block.typeName,
                    methodName: nil,
                    range: block.range,
                    certainty: .suspicious,
                    domain: .wire,
                    reason: .wire
                ))
            }
        }
        return findings
    }

    private func isNonProduction(path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/").map(String.init)
        let nonProductionDirectories: Set<String> = [
            "example", "examples", "fixture", "fixtures", "generated", "mock", "mocks", "preview",
            "previews", "sample", "samples", "stub", "stubs", "test", "testing", "tests",
        ]
        if parts.dropLast().contains(where: { nonProductionDirectories.contains($0.lowercased()) }) {
            return true
        }
        guard let fileName = parts.last else { return false }
        let stem = fileName.split(separator: ".", omittingEmptySubsequences: false).dropLast().joined(separator: ".")
        let lowerStem = stem.lowercased()
        return stem.hasSuffix("Test") || stem.hasSuffix("Tests") || lowerStem == "test" || lowerStem == "tests" ||
            lowerStem.hasPrefix("test_") || lowerStem.hasSuffix("_test") || lowerStem.hasSuffix(".test") ||
            lowerStem.hasSuffix("-test")
    }

    private func isFakeLike(typeName: String) -> Bool {
        let normalized = typeName.lowercased()
        let markers = ["fake", "mock", "stub", "preview", "dummy", "inmemory"]
        return markers.contains { normalized.contains($0) }
    }

    private func isExplicitlyPrivate(methodSource: String, path: String) -> Bool {
        let signature = methodSource.split(separator: "{", maxSplits: 1).first.map(String.init) ?? methodSource
        let identifiers = Set(rawIdentifierTokens(in: codeOnlySource(signature, path: path)))
        return identifiers.contains("private") || identifiers.contains("fileprivate")
    }

    private func sourceSlice(source: String, range: SourceRange) -> String {
        guard let startLine = range.startLine else {
            return ""
        }
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard startLine > 0, startLine <= lines.count else {
            return ""
        }
        let endLine = min(max(range.endLine ?? startLine, startLine), lines.count)
        return lines[(startLine - 1)..<endLine].joined(separator: "\n")
    }

    private func makeIdentifierIndex(sources: [String: String]) -> ProjectIdentifierIndex {
        var identifierCounts: [String: Int] = [:]
        var callCounts: [String: Int] = [:]
        for (path, source) in sources {
            let code = codeOnlySource(source, path: path)
            for identifier in rawIdentifierTokens(in: code) {
                identifierCounts[identifier, default: 0] += 1
            }
            for target in callTargets(in: code) {
                callCounts[target, default: 0] += 1
            }
        }
        return ProjectIdentifierIndex(identifierCounts: identifierCounts, callCounts: callCounts)
    }

    private func callTargets(in source: String) -> [String] {
        let excluded: Set<String> = [
            "catch", "for", "guard", "if", "match", "raise", "return", "sizeof", "switch", "throw",
            "typeof", "when", "while",
        ]
        var result: [String] = []
        var index = source.startIndex
        while index < source.endIndex {
            guard source[index].isLetter || source[index] == "_" else {
                index = source.index(after: index)
                continue
            }
            let start = index
            index = source.index(after: index)
            while index < source.endIndex &&
                (source[index].isLetter || source[index].isNumber || source[index] == "_") {
                index = source.index(after: index)
            }
            let identifier = String(source[start..<index])
            var lookahead = index
            while lookahead < source.endIndex && source[lookahead].isWhitespace {
                lookahead = source.index(after: lookahead)
            }
            if lookahead < source.endIndex && source[lookahead] == "(" && !excluded.contains(identifier) {
                result.append(identifier)
            }
        }
        return result
    }

    private func rawIdentifierTokens(in source: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in source {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func codeOnlySource(_ source: String, path: String) -> String {
        let dialect = SourceDialect(path: path)
        let characters = Array(source)
        var output = Array(repeating: Character(" "), count: characters.count)
        var modes: [ScanMode] = [.code(terminator: nil, depth: 0)]
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : "\0"
            switch modes.last {
            case .code(let terminator, let depth):
                if let terminator {
                    let opener: Character = terminator == ")" ? "(" : "{"
                    if character == opener {
                        output[index] = character
                        modes[modes.count - 1] = .code(terminator: terminator, depth: depth + 1)
                        index += 1
                        continue
                    }
                    if character == terminator {
                        if depth == 0 {
                            modes.removeLast()
                        } else {
                            output[index] = character
                            modes[modes.count - 1] = .code(terminator: terminator, depth: depth - 1)
                        }
                        index += 1
                        continue
                    }
                }

                if dialect == .python, character == "#" {
                    modes.append(.lineComment)
                    index += 1
                    continue
                }
                if dialect != .python, character == "/" && next == "/" {
                    modes.append(.lineComment)
                    index += 2
                    continue
                }
                if dialect != .python, character == "/" && next == "*" {
                    modes.append(.blockComment)
                    index += 2
                    continue
                }
                if character == "\"" || character == "'" || character == "`" {
                    let delimiterLength = repeatedDelimiterLength(
                        quote: character,
                        characters: characters,
                        index: index
                    )
                    modes.append(.string(
                        quote: character,
                        delimiterLength: delimiterLength,
                        interpolation: interpolationStyle(
                            dialect: dialect,
                            quote: character,
                            characters: characters,
                            index: index
                        )
                    ))
                    index += delimiterLength
                    continue
                }
                output[index] = character
                index += 1
            case .lineComment:
                if character == "\n" {
                    output[index] = character
                    modes.removeLast()
                }
                index += 1
            case .blockComment:
                if character == "*" && next == "/" {
                    modes.removeLast()
                    index += 2
                } else if character == "\n" {
                    output[index] = character
                    index += 1
                } else {
                    index += 1
                }
            case .string(let quote, let delimiterLength, let interpolation):
                if matchesDelimiter(
                    quote: quote,
                    length: delimiterLength,
                    characters: characters,
                    index: index
                ) {
                    modes.removeLast()
                    index += delimiterLength
                    continue
                }
                if interpolation == .swift, character == "\\",
                   let openingParenthesis = swiftInterpolationOpeningParenthesis(
                    characters: characters,
                    index: index
                   ) {
                    modes.append(.code(terminator: ")", depth: 0))
                    index = openingParenthesis + 1
                    continue
                }
                if interpolation == .dollar, character == "$", next == "{" {
                    modes.append(.code(terminator: "}", depth: 0))
                    index += 2
                    continue
                }
                if interpolation == .dollar, character == "$", isIdentifierStart(next) {
                    index += 1
                    while index < characters.count, isIdentifierContinuation(characters[index]) {
                        output[index] = characters[index]
                        index += 1
                    }
                    continue
                }
                if interpolation == .python, character == "{", next != "{" {
                    modes.append(.code(terminator: "}", depth: 0))
                    index += 1
                    continue
                }
                if interpolation == .python, character == "{", next == "{" {
                    index += 2
                    continue
                }
                if character == "\\" {
                    index += min(2, characters.count - index)
                } else {
                    if character == "\n" {
                        output[index] = character
                    }
                    index += 1
                }
            case nil:
                index += 1
            }
        }
        return String(output)
    }

    private func repeatedDelimiterLength(
        quote: Character,
        characters: [Character],
        index: Int
    ) -> Int {
        guard quote != "`", index + 2 < characters.count,
              characters[index + 1] == quote, characters[index + 2] == quote else {
            return 1
        }
        return 3
    }

    private func matchesDelimiter(
        quote: Character,
        length: Int,
        characters: [Character],
        index: Int
    ) -> Bool {
        guard index + length <= characters.count else { return false }
        return (0..<length).allSatisfy { characters[index + $0] == quote }
    }

    private func interpolationStyle(
        dialect: SourceDialect,
        quote: Character,
        characters: [Character],
        index: Int
    ) -> InterpolationStyle {
        switch dialect {
        case .swift:
            return quote == "\"" ? .swift : .none
        case .kotlin:
            return quote == "\"" ? .dollar : .none
        case .typeScript:
            return quote == "`" ? .dollar : .none
        case .python:
            return isPythonFormattedString(characters: characters, quoteIndex: index) ? .python : .none
        case .cStyle:
            return .none
        }
    }

    private func isPythonFormattedString(characters: [Character], quoteIndex: Int) -> Bool {
        var start = quoteIndex
        while start > 0, characters[start - 1].isLetter {
            start -= 1
        }
        let prefix = String(characters[start..<quoteIndex]).lowercased()
        return prefix == "f" || prefix == "fr" || prefix == "rf"
    }

    private func swiftInterpolationOpeningParenthesis(
        characters: [Character],
        index: Int
    ) -> Int? {
        var cursor = index + 1
        while cursor < characters.count, characters[cursor] == "#" {
            cursor += 1
        }
        return cursor < characters.count && characters[cursor] == "(" ? cursor : nil
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private func uniqueFindings(_ findings: [ImplementationFinding]) -> [ImplementationFinding] {
        var seen: Set<String> = []
        return findings.filter {
            let key = "\($0.scope.rawValue)|\($0.typeName)|\($0.methodName ?? "")|\($0.range.startLine ?? 0)|\($0.reason.rawValue)"
            return seen.insert(key).inserted
        }
    }
}

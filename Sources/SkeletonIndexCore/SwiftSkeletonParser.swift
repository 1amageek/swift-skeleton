import Foundation
import SwiftTreeSitter
import TreeSitterSwiftGrammar

public struct SwiftSkeletonParser: Sendable {
    public init() {}

    public func parse(path: String, source: String) -> ParsedFile {
        let parser = Parser()
        do {
            guard let languagePointer = tree_sitter_swift() else {
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

        var declarationNodes: [Node] = []
        collectDeclarationNodes(from: root, into: &declarationNodes)

        let blocks = declarationNodes.compactMap { node in
            block(from: node, source: source)
        }

        return ParsedFile(path: path, blocks: blocks, hasParseError: root.hasError)
    }

    private func collectDeclarationNodes(from node: Node, into nodes: inout [Node]) {
        let declarationTypes: Set<String> = [
            "class_declaration",
            "struct_declaration",
            "enum_declaration",
            "protocol_declaration",
            "extension_declaration",
        ]

        if let nodeType = node.nodeType, declarationTypes.contains(nodeType) {
            nodes.append(node)
        }

        for childIndex in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: childIndex) else {
                continue
            }
            collectDeclarationNodes(from: child, into: &nodes)
        }
    }

    private func block(from node: Node, source: String) -> SkeletonBlock? {
        let snippet = nodeText(node: node, source: source)
        guard let declaration = declarationHeader(from: snippet) else {
            return nil
        }

        let hasMissingClosingBrace = node.hasError && !snippet.contains("}")
        let startLine = Int(node.pointRange.lowerBound.row) + 1
        let range = SourceRange(
            startLine: startLine,
            endLine: hasMissingClosingBrace ? nil : Int(node.pointRange.upperBound.row) + 1
        )

        let members = parseMembers(in: snippet, declarationStartLine: startLine)

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

    private func declarationHeader(from snippet: String) -> (kind: SkeletonBlockKind, typeName: String, inheritance: [String])? {
        let header = snippet.split(separator: "{", maxSplits: 1).first.map(String.init) ?? snippet
        let compact = header.replacingOccurrences(of: "\n", with: " ")
        guard let keyword = firstRegex(pattern: #"\b(class|struct|enum|protocol|extension)\b"#, in: compact) else {
            return nil
        }

        if keyword == "extension" {
            guard let typeName = firstRegex(pattern: #"\bextension\s+([A-Za-z_][A-Za-z0-9_<>.]*)"#, in: compact) else {
                return nil
            }
            return (kind: .extension, typeName: typeName, inheritance: parseInheritance(from: compact))
        }

        guard
            let typeKeyword = SkeletonTypeKeyword(rawValue: keyword),
            let typeName = firstRegex(pattern: #"\b(?:class|struct|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: compact)
        else {
            return nil
        }
        return (kind: .type(typeKeyword), typeName: typeName, inheritance: parseInheritance(from: compact))
    }

    private func parseInheritance(from snippet: String) -> [String] {
        guard let header = snippet.split(separator: "{", maxSplits: 1).first.map(String.init) else {
            return []
        }
        guard let colon = firstTopLevelIndex(in: header, character: ":") else {
            return []
        }
        let inheritanceText = String(header[header.index(after: colon)...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if inheritanceText.isEmpty {
            return []
        }
        return splitTopLevel(inheritanceText, by: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

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
                if let capture = firstRegexCapture(
                    pattern: #"^\s*(?:public|private|internal|fileprivate|open|static|class|final|lazy|weak|unowned|\s)*(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^={]+)"#,
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
            depth += braceDelta(line)
            lineIndex += 1
        }

        return (properties, methods)
    }

    private func parseMethodLine(
        line: String,
        lineIndex: Int,
        lines: [String],
        declarationStartLine: Int
    ) -> MethodSignature? {
        let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let isInitializer = trimmed.contains("init(")
        let isFunction = trimmed.contains("func ")
        guard isInitializer || isFunction else {
            return nil
        }

        let name: String
        if isInitializer {
            name = "init"
        } else if let functionName = firstRegex(pattern: #"func\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: trimmed) {
            name = functionName
        } else {
            return nil
        }

        let params = parseParameterTypeRefs(betweenParentheses(trimmed) ?? "")
        let returnType = isInitializer ? nil : parseReturnType(trimmed)
        let startLine = declarationStartLine + lineIndex
        let endLine = methodEndLine(lines: lines, methodStartIndex: lineIndex).map { declarationStartLine + $0 }

        return MethodSignature(
            name: name,
            parameterTypeRefs: params,
            returnTypeRef: returnType,
            range: SourceRange(startLine: startLine, endLine: endLine),
            isInitializer: isInitializer
        )
    }

    private func methodEndLine(lines: [String], methodStartIndex: Int) -> Int? {
        let firstLine = lines[methodStartIndex]
        if !firstLine.contains("{") {
            return methodStartIndex
        }

        var balance = 0
        for index in methodStartIndex..<lines.count {
            for scalar in lines[index].unicodeScalars {
                if scalar == "{" {
                    balance += 1
                } else if scalar == "}" {
                    balance -= 1
                    if balance == 0 {
                        return index
                    }
                }
            }
        }
        return nil
    }

    private func braceDelta(_ line: String) -> Int {
        var delta = 0
        for scalar in line.unicodeScalars {
            if scalar == "{" {
                delta += 1
            } else if scalar == "}" {
                delta -= 1
            }
        }
        return delta
    }

    private func parseParameterTypeRefs(_ parameterSection: String) -> [String] {
        if parameterSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        let chunks = splitTopLevel(parameterSection, by: ",")
        return chunks.map { chunk in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "?"
            }
            guard let colon = firstTopLevelIndex(in: trimmed, character: ":") else {
                return "?"
            }
            let typeStart = trimmed.index(after: colon)
            var typeRef = String(trimmed[typeStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let equalIndex = firstTopLevelIndex(in: typeRef, character: "=") {
                typeRef = String(typeRef[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return typeRef.isEmpty ? "?" : typeRef
        }
    }

    private func parseReturnType(_ signatureText: String) -> String? {
        guard let arrow = signatureText.range(of: "->") else {
            return nil
        }
        var returnText = signatureText[arrow.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let whereRange = returnText.range(of: " where ") {
            returnText = returnText[..<whereRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let brace = returnText.firstIndex(of: "{") {
            returnText = returnText[..<brace].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return returnText.isEmpty ? nil : String(returnText)
    }

    private func betweenParentheses(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "(") else {
            return nil
        }

        var depth = 0
        var close: String.Index?

        for index in text.indices where index >= open {
            let char = text[index]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    close = index
                    break
                }
            }
        }
        guard let close else {
            return nil
        }
        return String(text[text.index(after: open)..<close])
    }

    private func splitTopLevel(_ text: String, by delimiter: Character) -> [String] {
        var results: [String] = []
        var current = ""
        var parenDepth = 0
        var squareDepth = 0
        var angleDepth = 0
        var braceDepth = 0

        for character in text {
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                squareDepth += 1
            case "]":
                squareDepth = max(0, squareDepth - 1)
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if character == delimiter && parenDepth == 0 && squareDepth == 0 && angleDepth == 0 && braceDepth == 0 {
                results.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        results.append(current)
        return results
    }

    private func firstTopLevelIndex(in text: String, character: Character) -> String.Index? {
        var parenDepth = 0
        var squareDepth = 0
        var angleDepth = 0
        var braceDepth = 0

        for index in text.indices {
            let value = text[index]
            switch value {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                squareDepth += 1
            case "]":
                squareDepth = max(0, squareDepth - 1)
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if value == character && parenDepth == 0 && squareDepth == 0 && angleDepth == 0 && braceDepth == 0 {
                return index
            }
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

    private func firstRegexCapture(pattern: String, in text: String) -> (String, String)? {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return nil
        }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange), match.numberOfRanges >= 3 else {
            return nil
        }
        guard
            let leftRange = Range(match.range(at: 1), in: text),
            let rightRange = Range(match.range(at: 2), in: text)
        else {
            return nil
        }
        return (
            text[leftRange].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            text[rightRange].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        )
    }

    private func firstRegex(pattern: String, in text: String) -> String? {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return nil
        }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange), match.numberOfRanges >= 2 else {
            return nil
        }
        guard let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return text[captureRange].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

}

import Foundation
import SkeletonIndexCore

public struct KotlinLanguageRules: LanguageRules, Sendable {
    public init() {}

    public var typeKeywordPattern: String {
        #"\b(class|interface|object|enum)\b"#
    }

    public var typeNamePattern: String {
        #"\b(?:class|interface|object|enum)\s+(?:class\s+)?([A-Za-z_][A-Za-z0-9_]*)"#
    }

    public var extensionPattern: ExtensionPattern? {
        nil
    }

    public var propertyPattern: String {
        #"^\s*(?:public|private|internal|protected|open|override|abstract|final|lateinit|static|\s)*(?:val|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^={]+)"#
    }

    public var returnTypeToken: String {
        ":"
    }

    /// `//` and nestable `/* */` comments, single-line `"…"` and multi-line raw `"""…"""` strings
    /// with `${ … }` templates, and `'…'` character literals.
    public var lexicalSyntax: LexicalSyntax {
        LexicalSyntax(
            lineComments: true,
            blockComments: true,
            nestedBlockComments: true,
            doubleQuotedStringsSpanLines: false,
            tripleQuotedStrings: true,
            singleQuote: .literal,
            templateLiterals: false,
            dollarBraceInterpolation: true,
            rawStrings: false
        )
    }

    /// A `companion object` is reported as an `object` block, like any nested type. An unnamed
    /// companion takes Kotlin's implicit name `Companion`.
    public func parseTypeHeader(_ header: String) -> TypeHeader? {
        if TextUtilities.firstRegex(pattern: #"\b(companion)\s+object\b"#, in: header) != nil {
            let name = TextUtilities.firstRegex(
                pattern: #"\bcompanion\s+object\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                in: header
            )
            return TypeHeader(keyword: "object", name: name ?? "Companion")
        }
        return TypeHeader.match(in: header, keywordPattern: typeKeywordPattern, namePattern: typeNamePattern)
    }

    public func parseInheritance(from header: String) -> [String] {
        guard let colon = TextUtilities.firstTopLevelIndex(in: header, character: ":") else {
            return []
        }
        let inheritanceText = String(header[header.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if inheritanceText.isEmpty {
            return []
        }
        return TextUtilities.splitTopLevel(inheritanceText, by: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { text in
                if let parenIndex = text.firstIndex(of: "(") {
                    return String(text[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return text
            }
            .filter { !$0.isEmpty }
    }

    /// Matches `fun name(`, `fun <T> name(`, and extension functions such as
    /// `fun <T> List<T>.name(`, capturing the function name rather than the receiver type.
    private static let functionNamePattern =
        #"\bfun\s+(?:<(?:[^<>]|<[^<>]*>)*>\s*)?"#
        + #"(?:[A-Za-z_][A-Za-z0-9_]*(?:<(?:[^<>]|<[^<>]*>)*>)?\??\.)*"#
        + #"([A-Za-z_][A-Za-z0-9_]*|`[^`]+`)\s*\("#

    public func parseMethodStart(from trimmedLine: String) -> MethodStart? {
        let isConstructor = trimmedLine.contains("constructor(")
        let isFunction = trimmedLine.contains("fun ")

        guard isConstructor || isFunction else {
            return nil
        }

        if isConstructor {
            return MethodStart(name: "constructor", isInitializer: true)
        }

        guard let name = TextUtilities.firstRegex(pattern: Self.functionNamePattern, in: trimmedLine) else {
            return nil
        }
        return MethodStart(name: name, isInitializer: false)
    }

    public func cleanReturnType(_ raw: String) -> String {
        var result = raw
        if let whereRange = result.range(of: " where ") {
            result = String(result[..<whereRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}

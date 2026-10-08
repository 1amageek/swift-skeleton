import Foundation
import SkeletonIndexCore

public struct RustLanguageRules: LanguageRules, Sendable {
    public init() {}

    /// Generic parameter or argument list with at most one level of nesting, e.g. `<T: Into<U>>`.
    private static let genericList = #"<(?:[^<>]|<[^<>]*>)*>"#
    /// Type path with optional generic arguments, e.g. `fmt::Display` or `From<Vec<T>>`.
    private static let typePath = #"(?:[A-Za-z_][A-Za-z0-9_]*::)*[A-Za-z_][A-Za-z0-9_]*"# + "(?:" + genericList + ")?"
    /// `impl`, optionally followed by its generic parameter list (`impl<T>`).
    private static let implKeyword = "impl(?:" + #"\s*"# + genericList + ")?"

    public var typeKeywordPattern: String {
        #"\b(struct|enum|trait|union)\b"#
    }

    public var typeNamePattern: String {
        #"\b(?:struct|enum|trait|union)\s+([A-Za-z_][A-Za-z0-9_]*)"#
    }

    /// `impl Type` and `impl Trait for Type` (with optional generics) both name `Type`.
    public var extensionPattern: ExtensionPattern? {
        ExtensionPattern(
            keyword: Self.implKeyword,
            typeNamePattern: "(?:" + Self.typePath + #"\s+for\s+)?("# + Self.typePath + ")"
        )
    }

    public var propertyPattern: String {
        #"^\s*(?:pub(?:\([^)]*\))?\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^,}]+)"#
    }

    public var returnTypeToken: String {
        "->"
    }

    /// `//` and nestable `/* */` comments, `"…"` strings that may span lines, raw strings
    /// (`r#"…"#`), and character literals that are distinguished from lifetimes (`'a`).
    public var lexicalSyntax: LexicalSyntax {
        LexicalSyntax(
            lineComments: true,
            blockComments: true,
            nestedBlockComments: true,
            doubleQuotedStringsSpanLines: true,
            tripleQuotedStrings: false,
            singleQuote: .characterLiteralOrLifetime,
            templateLiterals: false,
            dollarBraceInterpolation: false,
            rawStrings: true
        )
    }

    /// `impl Trait for Type` yields `[Trait]`; `trait Name: A + B` yields `[A, B]`. A `where`
    /// clause is not part of the inheritance list.
    public func parseInheritance(from header: String) -> [String] {
        let implTraitPattern = #"\b"# + Self.implKeyword + #"\s+("# + Self.typePath + #")\s+for\s+"#
        if let trait = TextUtilities.firstRegex(pattern: implTraitPattern, in: header) {
            return [trait]
        }

        var headerPart = header
        if let whereRange = header.range(of: #"\bwhere\b"#, options: .regularExpression) {
            headerPart = String(header[..<whereRange.lowerBound])
        }
        guard let colon = Self.firstSupertraitColon(in: headerPart) else {
            return []
        }
        let inheritanceText = String(headerPart[headerPart.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if inheritanceText.isEmpty {
            return []
        }
        return TextUtilities.splitTopLevel(inheritanceText, by: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// First `:` outside of generic lists and parentheses that is not part of a `::` path.
    private static func firstSupertraitColon(in text: String) -> String.Index? {
        var angleDepth = 0
        var parenthesisDepth = 0
        var previous: Character = " "
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            switch character {
            case "<":
                angleDepth += 1
            case ">" where previous != "-":
                angleDepth = max(0, angleDepth - 1)
            case "(":
                parenthesisDepth += 1
            case ")":
                parenthesisDepth = max(0, parenthesisDepth - 1)
            case ":" where angleDepth == 0 && parenthesisDepth == 0:
                let next: Character = nextIndex < text.endIndex ? text[nextIndex] : " "
                if previous != ":" && next != ":" {
                    return index
                }
            default:
                break
            }
            previous = character
            index = nextIndex
        }
        return nil
    }

    /// Rust has no initializers: `fn new` is an ordinary associated function.
    public func parseMethodStart(from trimmedLine: String) -> MethodStart? {
        guard trimmedLine.contains("fn ") else {
            return nil
        }
        guard let name = TextUtilities.firstRegex(pattern: #"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: trimmedLine) else {
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

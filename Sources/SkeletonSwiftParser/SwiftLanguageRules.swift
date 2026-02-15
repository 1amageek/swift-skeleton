import Foundation
import SkeletonIndexCore

public struct SwiftLanguageRules: LanguageRules, Sendable {
    public init() {}

    public var typeKeywordPattern: String {
        #"\b(class|struct|enum|protocol|actor)\b"#
    }

    public var typeNamePattern: String {
        #"\b(?:class|struct|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_]*)"#
    }

    public var extensionPattern: ExtensionPattern? {
        ExtensionPattern(
            keyword: "extension",
            typeNamePattern: #"([A-Za-z_][A-Za-z0-9_<>.]*)"#
        )
    }

    public var propertyPattern: String {
        #"^\s*(?:public|private|internal|fileprivate|open|static|class|final|lazy|weak|unowned|\s)*(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^={]+)"#
    }

    public var returnTypeToken: String {
        "->"
    }

    public func parseInheritance(from header: String) -> [String] {
        guard let headerPart = header.split(separator: "{", maxSplits: 1).first.map(String.init) else {
            return []
        }
        guard let colon = TextUtilities.firstTopLevelIndex(in: headerPart, character: ":") else {
            return []
        }
        let inheritanceText = String(headerPart[headerPart.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if inheritanceText.isEmpty {
            return []
        }
        return TextUtilities.splitTopLevel(inheritanceText, by: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func parseMethodStart(from trimmedLine: String) -> MethodStart? {
        let isInitializer = trimmedLine.contains("init(")
        let isFunction = trimmedLine.contains("func ")
        guard isInitializer || isFunction else {
            return nil
        }

        if isInitializer {
            return MethodStart(name: "init", isInitializer: true)
        }

        guard let name = TextUtilities.firstRegex(pattern: #"func\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: trimmedLine) else {
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

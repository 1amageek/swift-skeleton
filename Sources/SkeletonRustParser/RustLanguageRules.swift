import Foundation
import SkeletonIndexCore

public struct RustLanguageRules: LanguageRules, Sendable {
    public init() {}

    public var typeKeywordPattern: String {
        #"\b(struct|enum|trait|union)\b"#
    }

    public var typeNamePattern: String {
        #"\b(?:struct|enum|trait|union)\s+([A-Za-z_][A-Za-z0-9_]*)"#
    }

    public var extensionPattern: ExtensionPattern? {
        ExtensionPattern(
            keyword: "impl",
            typeNamePattern: #"(?:[A-Za-z_][A-Za-z0-9_<>:, ]*\s+for\s+)?([A-Za-z_][A-Za-z0-9_<>:, ]*)"#
        )
    }

    public var propertyPattern: String {
        #"^\s*(?:pub(?:\([^)]*\))?\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^,}]+)"#
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
        return inheritanceText.components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func parseMethodStart(from trimmedLine: String) -> MethodStart? {
        let isFunction = trimmedLine.contains("fn ")
        guard isFunction else {
            return nil
        }

        if trimmedLine.contains("fn new(") {
            return MethodStart(name: "new", isInitializer: true)
        }

        guard let name = TextUtilities.firstRegex(pattern: #"fn\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: trimmedLine) else {
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

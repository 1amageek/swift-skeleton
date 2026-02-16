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
            .map { text in
                if let parenIndex = text.firstIndex(of: "(") {
                    return String(text[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return text
            }
            .filter { !$0.isEmpty }
    }

    public func parseMethodStart(from trimmedLine: String) -> MethodStart? {
        let isConstructor = trimmedLine.contains("constructor(")
        let isFunction = trimmedLine.contains("fun ")

        guard isConstructor || isFunction else {
            return nil
        }

        if isConstructor {
            return MethodStart(name: "constructor", isInitializer: true)
        }

        guard let name = TextUtilities.firstRegex(pattern: #"fun\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: trimmedLine) else {
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

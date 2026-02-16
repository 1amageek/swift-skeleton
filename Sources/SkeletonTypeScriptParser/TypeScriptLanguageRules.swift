import Foundation
import SkeletonIndexCore

public struct TypeScriptLanguageRules: LanguageRules, Sendable {
    public init() {}

    public var typeKeywordPattern: String {
        #"\b(class|interface|enum|type)\b"#
    }

    public var typeNamePattern: String {
        #"\b(?:class|interface|enum|type)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#
    }

    public var extensionPattern: ExtensionPattern? {
        nil
    }

    public var propertyPattern: String {
        #"^\s*(?:public|private|protected|readonly|static|abstract|\s)*([A-Za-z_$][A-Za-z0-9_$]*)\??\s*:\s*([^;={]+)"#
    }

    public var returnTypeToken: String {
        ":"
    }

    public func parseInheritance(from header: String) -> [String] {
        guard let headerPart = header.split(separator: "{", maxSplits: 1).first.map(String.init) else {
            return []
        }
        var results: [String] = []
        for keyword in ["extends", "implements"] {
            guard let range = headerPart.range(of: " \(keyword) ") else { continue }
            let afterKeyword = String(headerPart[range.upperBound...])
            let untilNext: String
            if let nextKeyword = afterKeyword.range(of: " implements ") {
                untilNext = String(afterKeyword[..<nextKeyword.lowerBound])
            } else {
                untilNext = afterKeyword
            }
            let parts = TextUtilities.splitTopLevel(untilNext, by: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            results.append(contentsOf: parts)
        }
        return results
    }

    public func parseMethodStart(from trimmedLine: String) -> MethodStart? {
        if trimmedLine.hasPrefix("constructor(") || trimmedLine.contains(" constructor(") {
            return MethodStart(name: "constructor", isInitializer: true)
        }

        let pattern = #"^(?:public|private|protected|static|async|abstract|\s)*([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^>]*>)?\s*\("#
        guard let name = TextUtilities.firstRegex(pattern: pattern, in: trimmedLine) else {
            return nil
        }
        let keywords: Set<String> = ["if", "for", "while", "switch", "catch", "return", "throw", "new", "delete", "typeof", "instanceof"]
        if keywords.contains(name) { return nil }
        return MethodStart(name: name, isInitializer: false)
    }

    public func cleanReturnType(_ raw: String) -> String {
        raw
    }
}

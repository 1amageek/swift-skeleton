public protocol LanguageRules: Sendable {
    var typeKeywordPattern: String { get }
    var typeNamePattern: String { get }
    var extensionPattern: ExtensionPattern? { get }
    var propertyPattern: String { get }
    var returnTypeToken: String { get }
    func parseInheritance(from header: String) -> [String]
    func parseMethodStart(from trimmedLine: String) -> MethodStart?
    func cleanReturnType(_ raw: String) -> String
    /// Comment and literal syntax skipped by structural scans.
    var lexicalSyntax: LexicalSyntax { get }
    /// Parses the keyword and name of a type declaration header (code before the body brace).
    func parseTypeHeader(_ header: String) -> TypeHeader?
}

extension LanguageRules {
    public var lexicalSyntax: LexicalSyntax {
        .standard
    }

    public func parseTypeHeader(_ header: String) -> TypeHeader? {
        TypeHeader.match(in: header, keywordPattern: typeKeywordPattern, namePattern: typeNamePattern)
    }
}

public struct MethodStart: Sendable {
    public let name: String
    public let isInitializer: Bool

    public init(name: String, isInitializer: Bool) {
        self.name = name
        self.isInitializer = isInitializer
    }
}

public struct ExtensionPattern: Sendable {
    public let keyword: String
    public let typeNamePattern: String

    public init(keyword: String, typeNamePattern: String) {
        self.keyword = keyword
        self.typeNamePattern = typeNamePattern
    }
}

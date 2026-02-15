public protocol LanguageRules: Sendable {
    var typeKeywordPattern: String { get }
    var typeNamePattern: String { get }
    var extensionPattern: ExtensionPattern? { get }
    var propertyPattern: String { get }
    var returnTypeToken: String { get }
    func parseInheritance(from header: String) -> [String]
    func parseMethodStart(from trimmedLine: String) -> MethodStart?
    func cleanReturnType(_ raw: String) -> String
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

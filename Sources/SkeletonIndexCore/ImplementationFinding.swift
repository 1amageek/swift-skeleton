public struct ImplementationFinding: Sendable, Equatable, Codable {
    public enum Scope: String, Sendable, Equatable, Codable {
        case type
        case method
    }

    public enum Certainty: String, Sendable, Equatable, Codable {
        case definite
        case suspicious
    }

    public enum Domain: String, Sendable, Equatable, Codable, CaseIterable {
        case body
        case flow
        case error
        case wire
        case dead
    }

    public enum Reason: String, Sendable, Equatable, Codable {
        case trap
        case empty
        case constant = "const"
        case noOperation = "noop"
        case flow
        case error
        case wire
        case dead
    }

    public let scope: Scope
    public let typeName: String
    public let methodName: String?
    public let range: SourceRange
    public let certainty: Certainty
    public let domain: Domain
    public let reason: Reason

    public init(
        scope: Scope,
        typeName: String,
        methodName: String?,
        range: SourceRange,
        certainty: Certainty,
        domain: Domain,
        reason: Reason
    ) {
        self.scope = scope
        self.typeName = typeName
        self.methodName = methodName
        self.range = range
        self.certainty = certainty
        self.domain = domain
        self.reason = reason
    }

    public var marker: String {
        let indicator = certainty == .definite ? "!" : "?"
        return "[impl\(indicator):\(reason.rawValue)]"
    }
}

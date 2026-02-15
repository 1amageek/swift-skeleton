public struct PropertySignature: Sendable, Equatable {
    public let name: String
    public let typeRef: String

    public init(name: String, typeRef: String) {
        self.name = name
        self.typeRef = typeRef
    }
}

public struct MethodSyntaxEvidence: Sendable, Equatable {
    public enum ExpressionKind: String, Sendable, Equatable {
        case literal
        case identifier
        case call
        case constructed
        case unknown
    }

    public struct ReturnEvidence: Sendable, Equatable {
        public let kind: ExpressionKind
        public let identifiers: [String]
        public let signature: String

        public init(kind: ExpressionKind, identifiers: [String], signature: String) {
            self.kind = kind
            self.identifiers = identifiers
            self.signature = signature
        }
    }

    public struct CatchEvidence: Sendable, Equatable {
        public let executableStatementCount: Int
        public let callTargets: [String]
        public let assignmentTargets: [String]
        public let returns: [ReturnEvidence]
        public let throwsError: Bool
        public let trapCalls: [String]

        public init(
            executableStatementCount: Int,
            callTargets: [String],
            assignmentTargets: [String],
            returns: [ReturnEvidence],
            throwsError: Bool,
            trapCalls: [String]
        ) {
            self.executableStatementCount = executableStatementCount
            self.callTargets = callTargets
            self.assignmentTargets = assignmentTargets
            self.returns = returns
            self.throwsError = throwsError
            self.trapCalls = trapCalls
        }

        public var hasObservableEffect: Bool {
            !callTargets.isEmpty || !assignmentTargets.isEmpty || throwsError || !trapCalls.isEmpty
        }
    }

    public let typeName: String
    public let methodName: String
    public let range: SourceRange
    public let bodyState: ImplementationFingerprint.BodyState
    public let syntaxState: ImplementationFingerprint.SyntaxState
    public let parameterNames: [String]
    public let referencedIdentifiers: [String]
    public let returns: [ReturnEvidence]
    public let callTargets: [String]
    public let assignmentTargets: [String]
    public let controlFlowPaths: Int
    public let throwsError: Bool
    public let trapCalls: [String]
    public let catches: [CatchEvidence]
    public let asyncOperations: [String]
    public let executableStatementCount: Int

    public init(
        typeName: String,
        methodName: String,
        range: SourceRange,
        bodyState: ImplementationFingerprint.BodyState,
        syntaxState: ImplementationFingerprint.SyntaxState,
        parameterNames: [String],
        referencedIdentifiers: [String],
        returns: [ReturnEvidence],
        callTargets: [String],
        assignmentTargets: [String],
        controlFlowPaths: Int,
        throwsError: Bool,
        trapCalls: [String],
        catches: [CatchEvidence],
        asyncOperations: [String],
        executableStatementCount: Int
    ) {
        self.typeName = typeName
        self.methodName = methodName
        self.range = range
        self.bodyState = bodyState
        self.syntaxState = syntaxState
        self.parameterNames = parameterNames
        self.referencedIdentifiers = referencedIdentifiers
        self.returns = returns
        self.callTargets = callTargets
        self.assignmentTargets = assignmentTargets
        self.controlFlowPaths = controlFlowPaths
        self.throwsError = throwsError
        self.trapCalls = trapCalls
        self.catches = catches
        self.asyncOperations = asyncOperations
        self.executableStatementCount = executableStatementCount
    }
}

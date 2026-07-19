public struct ImplementationFingerprint: Sendable, Equatable, Codable {
    public enum BodyState: String, Sendable, Equatable, Codable {
        case absent
        case empty
        case concrete
    }

    public enum SyntaxState: String, Sendable, Equatable, Codable {
        case complete
        case incomplete
    }

    public enum ReturnOrigin: String, Sendable, Equatable, Codable {
        case literal
        case parameter
        case state
        case call
        case constructed
        case unknown
    }

    public enum TerminalBehavior: String, Sendable, Equatable, Codable {
        case returns
        case throwsError
        case traps
        case fallsThrough
    }

    public enum ProductionReachability: String, Sendable, Equatable, Codable {
        case external
        case referenced
        case unreferenced
        case nonProduction
        case unknown
    }

    public enum ImplementationBinding: String, Sendable, Equatable, Codable {
        case production
        case fakeLike
        case testOnly
        case unknown
    }

    public let bodyState: BodyState
    public let syntaxState: SyntaxState
    public let parameterReads: [String]
    public let returnOrigins: [ReturnOrigin]
    public let stateReads: [String]
    public let stateWrites: [String]
    public let callTargets: [String]
    public let controlFlowPaths: Int
    public let terminalBehaviors: [TerminalBehavior]
    public let caughtErrors: [String]
    public let asyncOperations: [String]
    public let externalEffects: [String]
    public let productionReachability: ProductionReachability
    public let implementationBinding: ImplementationBinding

    public init(
        bodyState: BodyState,
        syntaxState: SyntaxState,
        parameterReads: [String],
        returnOrigins: [ReturnOrigin],
        stateReads: [String],
        stateWrites: [String],
        callTargets: [String],
        controlFlowPaths: Int,
        terminalBehaviors: [TerminalBehavior],
        caughtErrors: [String],
        asyncOperations: [String],
        externalEffects: [String],
        productionReachability: ProductionReachability = .unknown,
        implementationBinding: ImplementationBinding = .unknown
    ) {
        self.bodyState = bodyState
        self.syntaxState = syntaxState
        self.parameterReads = parameterReads
        self.returnOrigins = returnOrigins
        self.stateReads = stateReads
        self.stateWrites = stateWrites
        self.callTargets = callTargets
        self.controlFlowPaths = controlFlowPaths
        self.terminalBehaviors = terminalBehaviors
        self.caughtErrors = caughtErrors
        self.asyncOperations = asyncOperations
        self.externalEffects = externalEffects
        self.productionReachability = productionReachability
        self.implementationBinding = implementationBinding
    }

    public func resolving(
        reachability: ProductionReachability,
        binding: ImplementationBinding
    ) -> ImplementationFingerprint {
        ImplementationFingerprint(
            bodyState: bodyState,
            syntaxState: syntaxState,
            parameterReads: parameterReads,
            returnOrigins: returnOrigins,
            stateReads: stateReads,
            stateWrites: stateWrites,
            callTargets: callTargets,
            controlFlowPaths: controlFlowPaths,
            terminalBehaviors: terminalBehaviors,
            caughtErrors: caughtErrors,
            asyncOperations: asyncOperations,
            externalEffects: externalEffects,
            productionReachability: reachability,
            implementationBinding: binding
        )
    }
}

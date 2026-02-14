import Foundation

public enum SkeletonError: Error, Sendable {
    case unsupportedLanguage(String)
    case invalidProjectRoot(String)
    case projectNotFound(String)
    case fileReadFailed(String)
    case invalidRequest(String)
    case invalidResponse(String)
}

public enum SkeletonTypeKeyword: String, Sendable, Codable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
}

public enum SkeletonBlockKind: Sendable, Equatable {
    case type(SkeletonTypeKeyword)
    case `extension`
}

public struct SourceRange: Sendable, Equatable, Codable {
    public let startLine: Int?
    public let endLine: Int?

    public init(startLine: Int?, endLine: Int?) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct PropertySignature: Sendable, Equatable {
    public let name: String
    public let typeRef: String

    public init(name: String, typeRef: String) {
        self.name = name
        self.typeRef = typeRef
    }
}

public struct MethodSignature: Sendable, Equatable {
    public let name: String
    public let parameterTypeRefs: [String]
    public let returnTypeRef: String?
    public let range: SourceRange
    public let isInitializer: Bool

    public init(
        name: String,
        parameterTypeRefs: [String],
        returnTypeRef: String?,
        range: SourceRange,
        isInitializer: Bool
    ) {
        self.name = name
        self.parameterTypeRefs = parameterTypeRefs
        self.returnTypeRef = returnTypeRef
        self.range = range
        self.isInitializer = isInitializer
    }
}

public struct SkeletonBlock: Sendable, Equatable {
    public let kind: SkeletonBlockKind
    public let typeName: String
    public let inheritance: [String]
    public let range: SourceRange
    public let properties: [PropertySignature]
    public let methods: [MethodSignature]
    public let hasErrorNode: Bool

    public init(
        kind: SkeletonBlockKind,
        typeName: String,
        inheritance: [String],
        range: SourceRange,
        properties: [PropertySignature],
        methods: [MethodSignature],
        hasErrorNode: Bool
    ) {
        self.kind = kind
        self.typeName = typeName
        self.inheritance = inheritance
        self.range = range
        self.properties = properties
        self.methods = methods
        self.hasErrorNode = hasErrorNode
    }
}

public struct ParsedFile: Sendable, Equatable {
    public let path: String
    public let blocks: [SkeletonBlock]
    public let hasParseError: Bool

    public init(path: String, blocks: [SkeletonBlock], hasParseError: Bool) {
        self.path = path
        self.blocks = blocks
        self.hasParseError = hasParseError
    }
}

public struct IncompleteBlock: Sendable, Codable, Equatable {
    public let file: String
    public let startLine: Int?
    public let endLine: Int?

    public init(file: String, startLine: Int?, endLine: Int?) {
        self.file = file
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct IndexDiagnostics: Sendable, Codable, Equatable {
    public let parseErrorFiles: [String]
    public let incompleteBlocks: [IncompleteBlock]

    public init(parseErrorFiles: [String], incompleteBlocks: [IncompleteBlock]) {
        self.parseErrorFiles = parseErrorFiles
        self.incompleteBlocks = incompleteBlocks
    }
}

public struct IndexStatus: Sendable, Codable, Equatable {
    public let filesIndexed: Int
    public let parseErrorFiles: Int
    public let lastUpdateTS: String
    public let isWatching: Bool

    public init(filesIndexed: Int, parseErrorFiles: Int, lastUpdateTS: String, isWatching: Bool) {
        self.filesIndexed = filesIndexed
        self.parseErrorFiles = parseErrorFiles
        self.lastUpdateTS = lastUpdateTS
        self.isWatching = isWatching
    }
}

public struct OpenResult: Sendable, Codable, Equatable {
    public let projectID: String
    public let status: IndexStatus

    public init(projectID: String, status: IndexStatus) {
        self.projectID = projectID
        self.status = status
    }
}

public struct SkeletonTextResult: Sendable, Codable, Equatable {
    public let text: String
    public let hasErrors: Bool

    public init(text: String, hasErrors: Bool) {
        self.text = text
        self.hasErrors = hasErrors
    }
}

public struct QueryHit: Sendable, Codable, Equatable {
    public let header: String
    public let file: String
    public let startLine: Int?
    public let endLine: Int?

    public init(header: String, file: String, startLine: Int?, endLine: Int?) {
        self.header = header
        self.file = file
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct ProjectIndex: Sendable {
    public let projectRoot: String
    public var files: [String: ParsedFile]
    public var lastUpdateTS: String
    public var isWatching: Bool

    public init(projectRoot: String, files: [String: ParsedFile], lastUpdateTS: String, isWatching: Bool) {
        self.projectRoot = projectRoot
        self.files = files
        self.lastUpdateTS = lastUpdateTS
        self.isWatching = isWatching
    }
}

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

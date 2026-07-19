import Foundation

public struct SkeletonIndexCore: Sendable {
    private let parsers: [any SkeletonParser]
    private let formatter: SkeletonFormatter
    private let implementationAnalyzer: any ImplementationAnalyzing
    private let implementationContextResolver: any ImplementationContextResolving

    public init(
        parsers: [any SkeletonParser],
        formatter: SkeletonFormatter = .init(),
        implementationAnalyzer: any ImplementationAnalyzing = DefaultImplementationAnalyzer(),
        implementationContextResolver: any ImplementationContextResolving = DefaultImplementationContextResolver()
    ) {
        self.parsers = parsers
        self.formatter = formatter
        self.implementationAnalyzer = implementationAnalyzer
        self.implementationContextResolver = implementationContextResolver
    }

    public var supportedLanguages: Set<String> {
        Set(parsers.map(\.languageName))
    }

    public func build(projectRoot: String) throws -> ProjectIndex {
        try build(projectRoot: projectRoot, languages: [])
    }

    public func build(projectRoot: String, languages: [String]) throws -> ProjectIndex {
        let rootURL = URL(fileURLWithPath: projectRoot).standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw SkeletonError.invalidProjectRoot(projectRoot)
        }

        let activeParsers = try parsers(for: languages)
        var files: [String: ParsedFile] = [:]
        var sources: [String: String] = [:]
        for relativePath in sourceFilePaths(rootURL: rootURL, parsers: activeParsers).sorted() {
            let absoluteURL = rootURL.appendingPathComponent(relativePath)
            let source: String
            do {
                source = try String(contentsOf: absoluteURL, encoding: .utf8)
            } catch {
                throw SkeletonError.fileReadFailed(relativePath)
            }
            guard let parser = parser(for: relativePath, in: activeParsers) else {
                continue
            }
            let parsedFile = parser.parse(path: relativePath, source: source)
            let analysis = implementationAnalyzer.analyze(
                path: relativePath,
                blocks: parsedFile.blocks,
                source: source,
                language: parser.languageName
            )
            files[relativePath] = parsedFile.replacing(implementationAnalysis: analysis)
            sources[relativePath] = source
        }

        files = implementationContextResolver.resolve(files: files, sources: sources)

        return ProjectIndex(
            projectRoot: rootURL.path,
            files: files,
            lastUpdateTS: timestamp(),
            isWatching: false
        )
    }

    public func status(index: ProjectIndex) -> IndexStatus {
        let parseErrorCount = index.files.values.filter(\.hasParseError).count
        return IndexStatus(
            filesIndexed: index.files.count,
            parseErrorFiles: parseErrorCount,
            lastUpdateTS: index.lastUpdateTS,
            isWatching: index.isWatching
        )
    }

    public func getSkeleton(index: ProjectIndex, path: String? = nil) -> SkeletonTextResult {
        if let path {
            return formatter.render(index: index, path: normalizePath(path, projectRoot: index.projectRoot))
        }
        return formatter.render(index: index)
    }

    public func update(
        index: inout ProjectIndex,
        changedPaths: [String],
        removedPaths: [String]
    ) throws -> IndexStatus {
        for removedPath in removedPaths {
            let normalizedPath = normalizePath(removedPath, projectRoot: index.projectRoot)
            index.files.removeValue(forKey: normalizedPath)
        }

        for changedPath in changedPaths {
            let normalizedPath = normalizePath(changedPath, projectRoot: index.projectRoot)
            let absolutePath = URL(fileURLWithPath: index.projectRoot).appendingPathComponent(normalizedPath).path
            if !FileManager.default.fileExists(atPath: absolutePath) {
                index.files.removeValue(forKey: normalizedPath)
                continue
            }
            let source: String
            do {
                source = try String(contentsOfFile: absolutePath, encoding: .utf8)
            } catch {
                throw SkeletonError.fileReadFailed(normalizedPath)
            }
            guard let parser = parser(for: normalizedPath, in: parsers) else {
                continue
            }
            let parsedFile = parser.parse(path: normalizedPath, source: source)
            let analysis = implementationAnalyzer.analyze(
                path: normalizedPath,
                blocks: parsedFile.blocks,
                source: source,
                language: parser.languageName
            )
            index.files[normalizedPath] = parsedFile.replacing(implementationAnalysis: analysis)
        }

        var sources: [String: String] = [:]
        for path in index.files.keys.sorted() {
            let absolutePath = URL(fileURLWithPath: index.projectRoot).appendingPathComponent(path).path
            do {
                sources[path] = try String(contentsOfFile: absolutePath, encoding: .utf8)
            } catch {
                throw SkeletonError.fileReadFailed(path)
            }
        }
        index.files = implementationContextResolver.resolve(files: index.files, sources: sources)

        index.lastUpdateTS = timestamp()
        return status(index: index)
    }

    public func query(index: ProjectIndex, q: String, limit: Int = 20) -> [QueryHit] {
        let needle = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return []
        }

        var ranked: [(score: Int, hit: QueryHit)] = []

        for filePath in index.files.keys.sorted() {
            guard let parsedFile = index.files[filePath] else {
                continue
            }
            for block in parsedFile.blocks {
                let header = formatter.header(
                    for: block,
                    filePath: filePath,
                    findings: parsedFile.implementationAnalysis.findings
                )
                let blockText = renderSearchText(block: block, header: header).lowercased()
                let score = occurrences(of: needle, in: blockText)
                if score > 0 {
                    ranked.append((
                        score: score,
                        hit: QueryHit(
                            header: header,
                            file: filePath,
                            startLine: block.range.startLine,
                            endLine: block.range.endLine
                        )
                    ))
                }
            }
        }

        return ranked
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.hit.file != $1.hit.file {
                    return $0.hit.file < $1.hit.file
                }
                return ($0.hit.startLine ?? 0) < ($1.hit.startLine ?? 0)
            }
            .prefix(max(0, limit))
            .map(\.hit)
    }

    public func diagnostics(index: ProjectIndex) -> IndexDiagnostics {
        var parseErrorFiles: [String] = []
        var incompleteBlocks: [IncompleteBlock] = []

        for filePath in index.files.keys.sorted() {
            guard let parsedFile = index.files[filePath] else {
                continue
            }
            if parsedFile.hasParseError {
                parseErrorFiles.append(filePath)
            }
            for block in parsedFile.blocks where block.hasErrorNode {
                incompleteBlocks.append(
                    IncompleteBlock(
                        file: filePath,
                        startLine: block.range.startLine,
                        endLine: block.range.endLine
                    )
                )
            }
        }

        return IndexDiagnostics(
            parseErrorFiles: parseErrorFiles,
            incompleteBlocks: incompleteBlocks
        )
    }

    private func parsers(for languages: [String]) throws -> [any SkeletonParser] {
        let normalizedLanguages = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !normalizedLanguages.isEmpty else {
            return parsers
        }

        let supported = supportedLanguages
        let unsupported = normalizedLanguages.filter { !supported.contains($0) }
        if !unsupported.isEmpty {
            throw SkeletonError.unsupportedLanguage(unsupported.joined(separator: ","))
        }

        return parsers.filter { normalizedLanguages.contains($0.languageName.lowercased()) }
    }

    private func parser(for path: String, in parsers: [any SkeletonParser]) -> (any SkeletonParser)? {
        let ext = URL(fileURLWithPath: path).pathExtension
        return parsers.first { $0.supportedExtensions.contains(ext) }
    }

    private static let excludedPaths: [String] = [
        "/.build/",
        "/.swiftpm/",
        "/node_modules/",
        "/vendor/",
        "/target/",
        "/__pycache__/",
        "/.venv/",
        "/venv/",
        "/zig-cache/",
        "/zig-out/",
        "/build/",
        "/out/",
    ]

    private func sourceFilePaths(rootURL: URL, parsers: [any SkeletonParser]) -> [String] {
        let allExtensions = parsers.reduce(into: Set<String>()) { $0.formUnion($1.supportedExtensions) }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []
        for case let fileURL as URL in enumerator {
            guard allExtensions.contains(fileURL.pathExtension) else {
                continue
            }
            if Self.excludedPaths.contains(where: { fileURL.path.contains($0) }) {
                continue
            }
            let relativePath = normalizePath(fileURL.path, projectRoot: rootURL.path)
            files.append(relativePath)
        }
        return files
    }

    private func renderSearchText(block: SkeletonBlock, header: String) -> String {
        var lines: [String] = [header]
        if !block.properties.isEmpty {
            lines.append(
                block.properties
                    .map { "\($0.name):\($0.typeRef)" }
                    .joined(separator: " ")
            )
        }
        if !block.methods.isEmpty {
            lines.append(
                block.methods
                    .map { "\($0.name)(\($0.parameterTypeRefs.joined(separator: ","))) \($0.returnTypeRef ?? "")" }
                    .joined(separator: " ")
            )
        }
        return lines.joined(separator: " ")
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else {
            return 0
        }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let foundRange = haystack.range(of: needle, options: [], range: searchRange) {
            count += 1
            searchRange = foundRange.upperBound..<haystack.endIndex
        }
        return count
    }

    private func normalizePath(_ path: String, projectRoot: String) -> String {
        let rootURL = URL(fileURLWithPath: projectRoot).standardizedFileURL
        let pathURL = URL(fileURLWithPath: path).standardizedFileURL

        if pathURL.path.hasPrefix(rootURL.path + "/") {
            return String(pathURL.path.dropFirst(rootURL.path.count + 1))
        }
        return path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

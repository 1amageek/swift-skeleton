import Foundation

public struct SkeletonIndexCore: Sendable {
  private let parsers: [any SkeletonParser]
  private let formatter: SkeletonFormatter
  private let implementationAnalyzer: any ImplementationAnalyzing
  private let implementationContextResolver: any ImplementationContextResolving
  private let projectStructureResolvers: [any ProjectStructureResolving]

  public init(
    parsers: [any SkeletonParser],
    projectStructureResolvers: [any ProjectStructureResolving] = [],
    formatter: SkeletonFormatter = .init(),
    implementationAnalyzer: any ImplementationAnalyzing = DefaultImplementationAnalyzer(),
    implementationContextResolver: any ImplementationContextResolving =
      DefaultImplementationContextResolver()
  ) {
    self.parsers = parsers
    self.projectStructureResolvers = projectStructureResolvers
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
    try build(projectRoot: projectRoot, languages: languages, targetName: nil)
  }

  public func build(projectRoot: String, languages: [String], targetName: String?) throws
    -> ProjectIndex
  {
    let requestedRootURL = URL(fileURLWithPath: projectRoot).standardizedFileURL
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: requestedRootURL.path, isDirectory: &isDirectory)
    guard exists, isDirectory.boolValue else {
      throw SkeletonError.invalidProjectRoot(projectRoot)
    }

    let activeParsers = try parsers(for: languages)
    guard let targetName else {
      let parsed = try parseSourceRoots(
        [requestedRootURL],
        outputRoot: requestedRootURL,
        parsers: activeParsers
      )
      let files = implementationContextResolver.resolve(
        files: parsed.files, sources: parsed.sources)
      return ProjectIndex(
        projectRoot: requestedRootURL.path,
        files: files,
        lastUpdateTS: timestamp(),
        isWatching: false
      )
    }

    let structure = try resolveProjectStructure(scopeRoot: requestedRootURL.path)
    guard let focusUnit = structure.unit(named: targetName) else {
      let available = structure.units.map(\.name).sorted().joined(separator: ",")
      throw SkeletonError.targetNotFound("\(targetName); available=\(available)")
    }
    let focusRoots = focusUnit.sourceRoots.map { URL(fileURLWithPath: $0).standardizedFileURL }
    guard !focusRoots.isEmpty else {
      throw SkeletonError.targetSourceUnavailable(targetName)
    }

    let outputRoot = URL(fileURLWithPath: structure.projectRoot).standardizedFileURL
    let focusParsed = try parseSourceRoots(
      focusRoots, outputRoot: outputRoot, parsers: activeParsers)
    guard !focusParsed.files.isEmpty else {
      throw SkeletonError.targetSourceUnavailable(targetName)
    }
    let importedModules = Set(focusParsed.files.values.flatMap(\.imports).map(\.moduleName))
    let dependencyUnits = focusUnit.dependencies.compactMap { dependency -> ProjectUnit? in
      guard let localUnitID = dependency.localUnitID,
        let unit = structure.unit(id: localUnitID),
        importedModules.contains(unit.moduleName) || importedModules.contains(unit.name),
        supportsAccessProjection(unit: unit, parsers: activeParsers)
      else {
        return nil
      }
      return unit
    }.sorted { $0.name < $1.name }

    let dependencyRoots =
      dependencyUnits
      .flatMap(\.sourceRoots)
      .map { URL(fileURLWithPath: $0).standardizedFileURL }
    let dependencyParsed = try parseSourceRoots(
      dependencyRoots,
      outputRoot: outputRoot,
      parsers: activeParsers
    )

    var files = focusParsed.files
    files.merge(dependencyParsed.files) { focus, _ in focus }
    var sources = focusParsed.sources
    sources.merge(dependencyParsed.sources) { focus, _ in focus }
    files = implementationContextResolver.resolve(files: files, sources: sources)

    var fileUnitIDs: [String: String] = [:]
    assignUnit(focusUnit, to: &fileUnitIDs, files: files, outputRoot: outputRoot)
    for unit in dependencyUnits {
      assignUnit(unit, to: &fileUnitIDs, files: files, outputRoot: outputRoot)
    }

    return ProjectIndex(
      projectRoot: outputRoot.path,
      files: files,
      lastUpdateTS: timestamp(),
      isWatching: false,
      projectStructure: structure,
      focusUnitID: focusUnit.id,
      dependencyUnitIDs: dependencyUnits.map(\.id),
      fileUnitIDs: fileUnitIDs
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
    getSkeleton(index: index, path: path, options: .default)
  }

  public func getSkeleton(
    index: ProjectIndex,
    path: String? = nil,
    options: SkeletonRenderOptions
  ) -> SkeletonTextResult {
    if let path {
      return formatter.render(
        index: index,
        path: normalizePath(path, projectRoot: index.projectRoot),
        options: options
      )
    }
    return formatter.render(index: index, options: options)
  }

  public func validateRender(index: ProjectIndex, accessBoundary: AccessBoundary?) throws {
    let requiresAccessMetadata =
      accessBoundary?.filtersDeclarations == true || index.focusUnitID != nil
    guard requiresAccessMetadata else {
      return
    }

    let unsupportedLanguages = Set(
      index.files.values.compactMap { file -> String? in
        let hasUnknownBlock = file.blocks.contains { block in
          block.access.effective == .unknown
            || block.declarations.contains { $0.access.effective == .unknown }
        }
        let hasUnknownDeclaration = file.declarations.contains {
          $0.access.effective == .unknown
        }
        guard hasUnknownBlock || hasUnknownDeclaration else {
          return nil
        }
        return file.languageName.isEmpty ? "unknown" : file.languageName
      }
    )
    guard unsupportedLanguages.isEmpty else {
      throw SkeletonError.accessFilterUnsupported(
        unsupportedLanguages.sorted().joined(separator: ","))
    }
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
      let absolutePath = URL(fileURLWithPath: index.projectRoot).appendingPathComponent(
        normalizedPath
      ).path
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
        language: parser.languageName,
        syntaxEvidence: parsedFile.methodSyntaxEvidence
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
      for declaration in parsedFile.declarations {
        appendRankedDeclaration(
          declaration,
          filePath: filePath,
          needle: needle,
          into: &ranked
        )
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
          ranked.append(
            (
              score: score,
              hit: QueryHit(
                header: header,
                file: filePath,
                startLine: block.range.startLine,
                endLine: block.range.endLine
              )
            ))
        }
        for declaration in block.declarations {
          appendRankedDeclaration(
            declaration,
            filePath: filePath,
            needle: needle,
            into: &ranked
          )
        }
      }
    }

    return
      ranked
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

  private func appendRankedDeclaration(
    _ declaration: SourceDeclaration,
    filePath: String,
    needle: String,
    into ranked: inout [(score: Int, hit: QueryHit)]
  ) {
    let score = occurrences(of: needle, in: declaration.signature.lowercased())
    guard score > 0 else {
      return
    }
    ranked.append(
      (
        score: score,
        hit: QueryHit(
          header:
            "\(declaration.signature) [\(filePath):\(declaration.range.startLine.map(String.init) ?? "?")-\(declaration.range.endLine.map(String.init) ?? "?")]",
          file: filePath,
          startLine: declaration.range.startLine,
          endLine: declaration.range.endLine
        )
      ))
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
    let normalizedLanguages =
      languages
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

  private func supportsAccessProjection(
    unit: ProjectUnit,
    parsers: [any SkeletonParser]
  ) -> Bool {
    let sourceURLs = sourceFileURLs(
      rootURLs: unit.sourceRoots.map { URL(fileURLWithPath: $0).standardizedFileURL },
      parsers: parsers
    )
    let relevantParsers = sourceURLs.compactMap { parser(for: $0.path, in: parsers) }
    return !relevantParsers.isEmpty && relevantParsers.allSatisfy(\.supportsAccessControl)
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

  private func parseSourceRoots(
    _ rootURLs: [URL],
    outputRoot: URL,
    parsers: [any SkeletonParser]
  ) throws -> (files: [String: ParsedFile], sources: [String: String]) {
    var files: [String: ParsedFile] = [:]
    var sources: [String: String] = [:]
    for absoluteURL in sourceFileURLs(rootURLs: rootURLs, parsers: parsers) {
      let relativePath = normalizePath(absoluteURL.path, projectRoot: outputRoot.path)
      let source: String
      do {
        source = try String(contentsOf: absoluteURL, encoding: .utf8)
      } catch {
        throw SkeletonError.fileReadFailed(relativePath)
      }
      guard let parser = parser(for: relativePath, in: parsers) else {
        continue
      }
      let parsedFile = parser.parse(path: relativePath, source: source)
        .replacing(languageName: parser.languageName)
      let analysis = implementationAnalyzer.analyze(
        path: relativePath,
        blocks: parsedFile.blocks,
        source: source,
        language: parser.languageName,
        syntaxEvidence: parsedFile.methodSyntaxEvidence
      )
      files[relativePath] = parsedFile.replacing(implementationAnalysis: analysis)
      sources[relativePath] = source
    }
    return (files, sources)
  }

  private func sourceFileURLs(rootURLs: [URL], parsers: [any SkeletonParser]) -> [URL] {
    let allExtensions = parsers.reduce(into: Set<String>()) { $0.formUnion($1.supportedExtensions) }
    var filesByPath: [String: URL] = [:]
    for rootURL in rootURLs {
      guard
        let enumerator = FileManager.default.enumerator(
          at: rootURL,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )
      else {
        continue
      }
      for case let fileURL as URL in enumerator {
        guard allExtensions.contains(fileURL.pathExtension) else {
          continue
        }
        if Self.excludedPaths.contains(where: { fileURL.path.contains($0) }) {
          continue
        }
        let standardized = fileURL.standardizedFileURL
        filesByPath[standardized.path] = standardized
      }
    }
    return filesByPath.values.sorted { $0.path < $1.path }
  }

  private func resolveProjectStructure(scopeRoot: String) throws -> ProjectStructure {
    for resolver in projectStructureResolvers {
      if let structure = try resolver.resolve(scopeRoot: scopeRoot) {
        return structure
      }
    }
    throw SkeletonError.projectStructureUnavailable(scopeRoot)
  }

  private func assignUnit(
    _ unit: ProjectUnit,
    to fileUnitIDs: inout [String: String],
    files: [String: ParsedFile],
    outputRoot: URL
  ) {
    let relativeRoots = unit.sourceRoots.map { normalizePath($0, projectRoot: outputRoot.path) }
    for filePath in files.keys {
      if relativeRoots.contains(where: { filePath == $0 || filePath.hasPrefix($0 + "/") }) {
        fileUnitIDs[filePath] = unit.id
      }
    }
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
          .map {
            "\($0.name)(\($0.parameterTypeRefs.joined(separator: ","))) \($0.returnTypeRef ?? "")"
          }
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
    return
      path
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}

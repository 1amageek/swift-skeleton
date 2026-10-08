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

    let normalizedLanguages = try validatedLanguages(languages)
    let activeParsers = parsers(for: normalizedLanguages)
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
        isWatching: false,
        languages: normalizedLanguages,
        scopeRoots: [requestedRootURL.path]
      )
    }

    let structure = try resolveProjectStructure(scopeRoot: requestedRootURL.path)
    guard let focusUnit = structure.unit(named: targetName) else {
      let available = structure.units.map(\.name).sorted().joined(separator: ",")
      throw SkeletonError.targetNotFound("\(targetName); available=\(available)")
    }
    return try buildTargetIndex(
      structure: structure,
      focusUnit: focusUnit,
      languages: normalizedLanguages,
      parsers: activeParsers
    )
  }

  private func buildTargetIndex(
    structure: ProjectStructure,
    focusUnit: ProjectUnit,
    languages: [String],
    parsers activeParsers: [any SkeletonParser]
  ) throws -> ProjectIndex {
    let focusRoots = focusUnit.sourceRoots.map { URL(fileURLWithPath: $0).standardizedFileURL }
    guard !focusRoots.isEmpty else {
      throw SkeletonError.targetSourceUnavailable(focusUnit.name)
    }

    let outputRoot = URL(fileURLWithPath: structure.projectRoot).standardizedFileURL
    let focusParsed = try parseSourceRoots(
      focusRoots, outputRoot: outputRoot, parsers: activeParsers)
    guard !focusParsed.files.isEmpty else {
      throw SkeletonError.targetSourceUnavailable(focusUnit.name)
    }
    let importedModules = Set(focusParsed.files.values.flatMap(\.imports).map(\.moduleName))
    let dependencyUnits = try selectDependencyUnits(
      focusUnit: focusUnit,
      structure: structure,
      importedModules: importedModules,
      parsers: activeParsers
    )

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
      fileUnitIDs: fileUnitIDs,
      languages: languages,
      scopeRoots: (focusRoots + dependencyRoots).map(\.path)
    )
  }

  private func selectDependencyUnits(
    focusUnit: ProjectUnit,
    structure: ProjectStructure,
    importedModules: Set<String>,
    parsers activeParsers: [any SkeletonParser]
  ) throws -> [ProjectUnit] {
    var units: [ProjectUnit] = []
    for dependency in focusUnit.dependencies {
      guard let localUnitID = dependency.localUnitID,
        let unit = structure.unit(id: localUnitID),
        importedModules.contains(unit.moduleName) || importedModules.contains(unit.name),
        try supportsAccessProjection(unit: unit, parsers: activeParsers)
      else {
        continue
      }
      units.append(unit)
    }
    return units.sorted { $0.name < $1.name }
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
    let activeParsers = parsers(for: index.languages)
    let rootURL = URL(fileURLWithPath: index.projectRoot).standardizedFileURL
    let scopeRootURLs = (index.scopeRoots.isEmpty ? [index.projectRoot] : index.scopeRoots)
      .map { URL(fileURLWithPath: $0).standardizedFileURL }

    for removedPath in removedPaths {
      let normalizedPath = normalizePath(
        absoluteURL(for: removedPath, projectRoot: rootURL).path,
        projectRoot: rootURL.path
      )
      index.files.removeValue(forKey: normalizedPath)
      index.fileUnitIDs.removeValue(forKey: normalizedPath)
    }

    for changedPath in changedPaths {
      let fileURL = absoluteURL(for: changedPath, projectRoot: rootURL)
      let normalizedPath = normalizePath(fileURL.path, projectRoot: rootURL.path)
      // A path that a fresh build of the same scope would not index is dropped, not parsed.
      guard isIndexable(fileURL, scopeRoots: scopeRootURLs, parsers: activeParsers),
        let parser = parser(for: normalizedPath, in: activeParsers),
        FileManager.default.fileExists(atPath: fileURL.path)
      else {
        index.files.removeValue(forKey: normalizedPath)
        index.fileUnitIDs.removeValue(forKey: normalizedPath)
        continue
      }
      let source = try readSource(at: fileURL, displayPath: normalizedPath)
      index.files[normalizedPath] = parseFile(path: normalizedPath, source: source, parser: parser)
      if let unitID = unitID(forFile: normalizedPath, index: index, outputRoot: rootURL) {
        index.fileUnitIDs[normalizedPath] = unitID
      }
    }

    if let rebuilt = try rebuildIfTargetDependenciesChanged(index: index, outputRoot: rootURL) {
      index = rebuilt
      return status(index: index)
    }

    var sources: [String: String] = [:]
    for path in index.files.keys.sorted() {
      sources[path] = try readSource(
        at: rootURL.appendingPathComponent(path), displayPath: path)
    }
    index.files = implementationContextResolver.resolve(files: index.files, sources: sources)

    index.lastUpdateTS = timestamp()
    return status(index: index)
  }

  /// Target views select dependency units from the focus imports, so an import change
  /// re-runs target selection against the structure resolved at open time.
  private func rebuildIfTargetDependenciesChanged(
    index: ProjectIndex,
    outputRoot: URL
  ) throws -> ProjectIndex? {
    guard let structure = index.projectStructure,
      let focusUnitID = index.focusUnitID,
      let focusUnit = structure.unit(id: focusUnitID)
    else {
      return nil
    }
    let activeParsers = parsers(for: index.languages)
    let importedModules = Set(
      index.files
        .filter { unit(focusUnit, contains: $0.key, outputRoot: outputRoot) }
        .values
        .flatMap(\.imports)
        .map(\.moduleName)
    )
    let selectedUnitIDs = try selectDependencyUnits(
      focusUnit: focusUnit,
      structure: structure,
      importedModules: importedModules,
      parsers: activeParsers
    ).map(\.id)
    guard selectedUnitIDs != index.dependencyUnitIDs else {
      return nil
    }
    return try buildTargetIndex(
      structure: structure,
      focusUnit: focusUnit,
      languages: index.languages,
      parsers: activeParsers
    )
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

  private func validatedLanguages(_ languages: [String]) throws -> [String] {
    var normalizedLanguages: [String] = []
    for language in languages {
      let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if !normalized.isEmpty && !normalizedLanguages.contains(normalized) {
        normalizedLanguages.append(normalized)
      }
    }

    let supported = Set(supportedLanguages.map { $0.lowercased() })
    let unsupported = normalizedLanguages.filter { !supported.contains($0) }
    if !unsupported.isEmpty {
      throw SkeletonError.unsupportedLanguage(unsupported.joined(separator: ","))
    }
    return normalizedLanguages
  }

  private func parsers(for normalizedLanguages: [String]) -> [any SkeletonParser] {
    guard !normalizedLanguages.isEmpty else {
      return parsers
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
  ) throws -> Bool {
    let sourceURLs = try sourceFileURLs(
      rootURLs: unit.sourceRoots.map { URL(fileURLWithPath: $0).standardizedFileURL },
      parsers: parsers
    )
    let relevantParsers = sourceURLs.compactMap { parser(for: $0.path, in: parsers) }
    return !relevantParsers.isEmpty && relevantParsers.allSatisfy(\.supportsAccessControl)
  }

  /// Directory names excluded below a scanned root. Ancestors of the root are never matched,
  /// so a project located under e.g. `/build/` is still indexed.
  private static let excludedDirectoryNames: Set<String> = [
    ".build",
    ".swiftpm",
    "node_modules",
    "vendor",
    "target",
    "__pycache__",
    ".venv",
    "venv",
    "zig-cache",
    "zig-out",
    "build",
    "out",
  ]

  private func parseSourceRoots(
    _ rootURLs: [URL],
    outputRoot: URL,
    parsers: [any SkeletonParser]
  ) throws -> (files: [String: ParsedFile], sources: [String: String]) {
    var files: [String: ParsedFile] = [:]
    var sources: [String: String] = [:]
    for absoluteURL in try sourceFileURLs(rootURLs: rootURLs, parsers: parsers) {
      let relativePath = normalizePath(absoluteURL.path, projectRoot: outputRoot.path)
      guard let parser = parser(for: relativePath, in: parsers) else {
        continue
      }
      let source = try readSource(at: absoluteURL, displayPath: relativePath)
      files[relativePath] = parseFile(path: relativePath, source: source, parser: parser)
      sources[relativePath] = source
    }
    return (files, sources)
  }

  private func parseFile(path: String, source: String, parser: any SkeletonParser) -> ParsedFile {
    let parsedFile = parser.parse(path: path, source: source)
      .replacing(languageName: parser.languageName)
    let analysis = implementationAnalyzer.analyze(
      path: path,
      blocks: parsedFile.blocks,
      source: source,
      language: parser.languageName,
      syntaxEvidence: parsedFile.methodSyntaxEvidence
    )
    return parsedFile.replacing(implementationAnalysis: analysis)
  }

  private func readSource(at url: URL, displayPath: String) throws -> String {
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw SkeletonError.fileReadFailed(displayPath)
    }
  }

  private func sourceFileURLs(rootURLs: [URL], parsers: [any SkeletonParser]) throws -> [URL] {
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
        let isDirectory: Bool
        do {
          isDirectory = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        } catch {
          throw SkeletonError.fileReadFailed(fileURL.path)
        }
        if isDirectory {
          if Self.excludedDirectoryNames.contains(fileURL.lastPathComponent) {
            enumerator.skipDescendants()
          }
          continue
        }
        guard allExtensions.contains(fileURL.pathExtension) else {
          continue
        }
        let standardized = fileURL.standardizedFileURL
        filesByPath[standardized.path] = standardized
      }
    }
    return filesByPath.values.sorted { $0.path < $1.path }
  }

  /// Mirrors `sourceFileURLs` for a single file so incremental updates index exactly
  /// the files a fresh build of the same scope would.
  private func isIndexable(
    _ fileURL: URL,
    scopeRoots: [URL],
    parsers: [any SkeletonParser]
  ) -> Bool {
    guard parser(for: fileURL.path, in: parsers) != nil else {
      return false
    }
    for rootURL in scopeRoots {
      let rootPath = rootURL.path
      guard fileURL.path.hasPrefix(rootPath + "/") else {
        continue
      }
      let components = fileURL.path.dropFirst(rootPath.count + 1).split(separator: "/")
      let isHiddenOrExcluded = components.enumerated().contains { offset, component in
        component.hasPrefix(".")
          || (offset < components.count - 1
            && Self.excludedDirectoryNames.contains(String(component)))
      }
      if !isHiddenOrExcluded {
        return true
      }
    }
    return false
  }

  private func absoluteURL(for path: String, projectRoot rootURL: URL) -> URL {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    if normalized.hasPrefix("/") {
      return URL(fileURLWithPath: normalized).standardizedFileURL
    }
    return rootURL.appendingPathComponent(normalized).standardizedFileURL
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
    for filePath in files.keys where self.unit(unit, contains: filePath, outputRoot: outputRoot) {
      fileUnitIDs[filePath] = unit.id
    }
  }

  /// Uses the same precedence as `buildTargetIndex`: dependency units are assigned after the focus unit.
  private func unitID(forFile filePath: String, index: ProjectIndex, outputRoot: URL) -> String? {
    guard let structure = index.projectStructure, let focusUnitID = index.focusUnitID else {
      return nil
    }
    var matchedUnitID: String?
    for unitID in [focusUnitID] + index.dependencyUnitIDs {
      guard let unit = structure.unit(id: unitID) else {
        continue
      }
      if self.unit(unit, contains: filePath, outputRoot: outputRoot) {
        matchedUnitID = unit.id
      }
    }
    return matchedUnitID
  }

  private func unit(_ unit: ProjectUnit, contains filePath: String, outputRoot: URL) -> Bool {
    unit.sourceRoots
      .map { normalizePath($0, projectRoot: outputRoot.path) }
      .contains { filePath == $0 || filePath.hasPrefix($0 + "/") }
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

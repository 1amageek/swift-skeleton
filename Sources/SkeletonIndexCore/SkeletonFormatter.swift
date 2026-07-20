import Foundation

public struct SkeletonFormatter: Sendable {
  public init() {}

  public func render(
    index: ProjectIndex,
    path: String? = nil,
    options: SkeletonRenderOptions = .default
  ) -> SkeletonTextResult {
    if path == nil,
      let structure = index.projectStructure,
      let focusUnitID = index.focusUnitID,
      let focusUnit = structure.unit(id: focusUnitID)
    {
      return renderTargetView(
        index: index,
        structure: structure,
        focusUnit: focusUnit,
        options: options
      )
    }

    let selectedPaths: [String]
    if let path {
      selectedPaths = index.files.keys.filter { $0 == path }.sorted()
    } else {
      selectedPaths = index.files.keys.sorted()
    }

    var lines: [String] = []
    var hasErrors = false

    for filePath in selectedPaths {
      guard let parsedFile = index.files[filePath] else {
        continue
      }
      let fileLines = render(
        path: filePath,
        parsedFile: parsedFile,
        boundary: options.accessBoundary,
        allowedSPIGroups: [],
        options: options
      )
      hasErrors = hasErrors || fileLines.hasErrors
      lines.append(fileLines.text)
    }

    return SkeletonTextResult(
      text: lines.filter { !$0.isEmpty }.joined(separator: "\n"),
      hasErrors: hasErrors
    )
  }

  private func renderTargetView(
    index: ProjectIndex,
    structure: ProjectStructure,
    focusUnit: ProjectUnit,
    options: SkeletonRenderOptions
  ) -> SkeletonTextResult {
    let focusImports = index.files
      .filter { index.fileUnitIDs[$0.key] == focusUnit.id }
      .values
      .flatMap(\.imports)
    var sections: [String] = []
    var hasErrors = false

    let focusSection = renderUnit(
      focusUnit,
      index: index,
      imports: focusImports,
      boundary: options.accessBoundary,
      allowedSPIGroups: [],
      options: options
    )
    sections.append(focusSection.text)
    hasErrors = hasErrors || focusSection.hasErrors

    for dependencyID in index.dependencyUnitIDs {
      guard let dependency = structure.unit(id: dependencyID) else {
        continue
      }
      let matchingImports = focusImports.filter {
        $0.moduleName == dependency.moduleName || $0.moduleName == dependency.name
      }
      let contextualBoundary: AccessBoundary
      if focusUnit.kind == .test && matchingImports.contains(where: \.isTestable) {
        contextualBoundary = .internal
      } else {
        contextualBoundary = .package
      }
      let section = renderUnit(
        dependency,
        index: index,
        imports: [],
        boundary: options.accessBoundary ?? contextualBoundary,
        allowedSPIGroups: Set(matchingImports.flatMap(\.spiGroups)),
        options: options
      )
      sections.append(section.text)
      hasErrors = hasErrors || section.hasErrors
    }

    return SkeletonTextResult(
      text: sections.filter { !$0.isEmpty }.joined(separator: "\n\n"),
      hasErrors: hasErrors
    )
  }

  private func renderUnit(
    _ unit: ProjectUnit,
    index: ProjectIndex,
    imports: [SourceImport],
    boundary: AccessBoundary?,
    allowedSPIGroups: Set<String>,
    options: SkeletonRenderOptions
  ) -> SkeletonTextResult {
    var lines = ["\(unit.displayKind) \(unit.name)"]
    let moduleNames = Set(imports.map(\.moduleName)).sorted()
    if !moduleNames.isEmpty {
      lines.append("  imports: \(moduleNames.joined(separator: ", "))")
    }

    var hasErrors = false
    let paths = index.fileUnitIDs
      .filter { $0.value == unit.id }
      .map(\.key)
      .sorted()
    for path in paths {
      guard let parsedFile = index.files[path] else {
        continue
      }
      let rendered = render(
        path: path,
        parsedFile: parsedFile,
        boundary: boundary,
        allowedSPIGroups: allowedSPIGroups,
        options: options
      )
      if !rendered.text.isEmpty {
        lines.append(rendered.text)
      }
      hasErrors = hasErrors || rendered.hasErrors
    }
    return SkeletonTextResult(text: lines.joined(separator: "\n"), hasErrors: hasErrors)
  }

  public func header(for block: SkeletonBlock, filePath: String) -> String {
    header(for: block, filePath: filePath, findings: [])
  }

  public func header(
    for block: SkeletonBlock,
    filePath: String,
    findings: [ImplementationFinding]
  ) -> String {
    let inheritance =
      block.inheritance.isEmpty ? "" : ": \(block.inheritance.joined(separator: ", "))"
    let rangeText = "\(lineNumber(block.range.startLine))-\(lineNumber(block.range.endLine))"
    let base: String

    switch block.kind {
    case .type(let keyword):
      base = "\(keyword) \(block.typeName)\(inheritance) [\(filePath):\(rangeText)]"
    case .extension:
      base = "extension \(block.typeName)\(inheritance) [\(filePath):\(rangeText)]"
    }
    let parseMarker = block.hasErrorNode ? " (!)" : ""
    let implementationMarker = blockImplementationMarker(block: block, findings: findings)
    return base + parseMarker + implementationMarker
  }

  private func render(
    path: String,
    parsedFile: ParsedFile,
    boundary: AccessBoundary?,
    allowedSPIGroups: Set<String>,
    options: SkeletonRenderOptions
  ) -> SkeletonTextResult {
    var lines: [String] = []
    var hasErrors = parsedFile.hasParseError

    if parsedFile.hasParseError {
      lines.append("# parse_error \(path)")
    }

    let declarations = parsedFile.declarations.filter {
      isVisible($0.access, boundary: boundary, allowedSPIGroups: allowedSPIGroups)
    }
    var declarationIndex = 0

    for block in parsedFile.blocks {
      let blockStart = block.range.startLine ?? Int.max
      while declarationIndex < declarations.count,
        (declarations[declarationIndex].range.startLine ?? Int.max) < blockStart
      {
        lines.append(declarationLine(declarations[declarationIndex], filePath: path))
        declarationIndex += 1
      }

      guard includesKind(block, kinds: options.kinds) else {
        continue
      }
      guard isVisible(block.access, boundary: boundary, allowedSPIGroups: allowedSPIGroups) else {
        continue
      }
      if block.hasErrorNode {
        hasErrors = true
      }
      let blockFindings = findings(for: block, in: parsedFile.implementationAnalysis.findings)
      lines.append(header(for: block, filePath: path, findings: blockFindings))

      let properties = block.properties.filter {
        isVisible($0.access, boundary: boundary, allowedSPIGroups: allowedSPIGroups)
      }
      let methods = block.methods.filter {
        isVisible($0.access, boundary: boundary, allowedSPIGroups: allowedSPIGroups)
      }

      if !options.headersOnly && !properties.isEmpty {
        let props =
          properties
          .map { "\($0.name):\($0.typeRef)" }
          .joined(separator: ", ")
        lines.append("  props: \(props)")
      }

      if !options.headersOnly && !methods.isEmpty {
        lines.append("  methods:")
        for method in methods {
          let params = method.parameterTypeRefs.joined(separator: ", ")
          let methodRange =
            "\(lineNumber(method.range.startLine))-\(lineNumber(method.range.endLine))"
          let marker =
            primaryMethodFinding(
              method: method,
              block: block,
              findings: blockFindings
            ).map { " \($0.marker)" } ?? ""
          if method.isInitializer {
            lines.append("    init(\(params)) [\(methodRange)]\(marker)")
          } else if let returnTypeRef = method.returnTypeRef {
            lines.append(
              "    \(method.name)(\(params)) -> \(returnTypeRef) [\(methodRange)]\(marker)")
          } else {
            lines.append("    \(method.name)(\(params)) [\(methodRange)]\(marker)")
          }
        }
      }

      let declarations = block.declarations.filter {
        isVisible($0.access, boundary: boundary, allowedSPIGroups: allowedSPIGroups)
      }
      if !options.headersOnly && !declarations.isEmpty {
        lines.append("  declarations:")
        for declaration in declarations {
          lines.append("    \(declarationLine(declaration, filePath: nil))")
        }
      }
    }

    while declarationIndex < declarations.count {
      lines.append(declarationLine(declarations[declarationIndex], filePath: path))
      declarationIndex += 1
    }

    return SkeletonTextResult(
      text: lines.joined(separator: "\n"),
      hasErrors: hasErrors
    )
  }

  private func declarationLine(_ declaration: SourceDeclaration, filePath: String?) -> String {
    let start = lineNumber(declaration.range.startLine)
    let end = lineNumber(declaration.range.endLine)
    if let filePath {
      return "\(declaration.signature) [\(filePath):\(start)-\(end)]"
    }
    return "\(declaration.signature) [\(start)-\(end)]"
  }

  private func includesKind(_ block: SkeletonBlock, kinds: Set<String>) -> Bool {
    guard !kinds.isEmpty else {
      return true
    }
    switch block.kind {
    case .type(let keyword):
      return kinds.contains(keyword)
    case .extension:
      return kinds.contains("extension")
    }
  }

  private func isVisible(
    _ access: DeclarationAccess,
    boundary: AccessBoundary?,
    allowedSPIGroups: Set<String>
  ) -> Bool {
    guard let boundary, boundary.filtersDeclarations else {
      return true
    }
    if !access.spiGroups.isEmpty && allowedSPIGroups.isDisjoint(with: access.spiGroups) {
      return false
    }
    return access.effective.isVisible(at: boundary)
  }

  private func lineNumber(_ value: Int?) -> String {
    guard let value else {
      return "?"
    }
    return String(value)
  }

  private func findings(
    for block: SkeletonBlock,
    in findings: [ImplementationFinding]
  ) -> [ImplementationFinding] {
    findings.filter { finding in
      guard finding.typeName == block.typeName else {
        return false
      }
      guard let blockStart = block.range.startLine,
        let findingStart = finding.range.startLine
      else {
        return true
      }
      let blockEnd = block.range.endLine ?? Int.max
      let findingEnd = finding.range.endLine ?? findingStart
      return findingStart >= blockStart && findingEnd <= blockEnd
    }
  }

  private func blockImplementationMarker(
    block: SkeletonBlock,
    findings: [ImplementationFinding]
  ) -> String {
    let blockFindings = self.findings(for: block, in: findings)
    let domains = ImplementationFinding.Domain.allCases.filter { domain in
      blockFindings.contains { $0.domain == domain }
    }
    guard !domains.isEmpty else {
      return ""
    }
    return " [impl:\(domains.map(\.rawValue).joined(separator: ","))]"
  }

  private func primaryMethodFinding(
    method: MethodSignature,
    block: SkeletonBlock,
    findings: [ImplementationFinding]
  ) -> ImplementationFinding? {
    findings
      .filter {
        $0.scope == .method && $0.typeName == block.typeName && $0.methodName == method.name
          && $0.range == method.range
      }
      .sorted { findingPriority($0) < findingPriority($1) }
      .first
  }

  private func findingPriority(_ finding: ImplementationFinding) -> Int {
    let certaintyOffset = finding.certainty == .definite ? 0 : 100
    let reasonPriority: [ImplementationFinding.Reason: Int] = [
      .trap: 0,
      .empty: 1,
      .wire: 2,
      .error: 3,
      .constant: 4,
      .noOperation: 5,
      .flow: 6,
      .dead: 7,
    ]
    return certaintyOffset + (reasonPriority[finding.reason] ?? 99)
  }
}

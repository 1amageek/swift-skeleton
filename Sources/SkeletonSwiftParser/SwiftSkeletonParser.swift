import Foundation
import SkeletonIndexCore
import SkeletonTreeSitterSupport
import SwiftTreeSitter
import TreeSitterSwiftGrammar

public struct SwiftSkeletonParser: SkeletonParser, Sendable {
  public var languageName: String { "swift" }
  public var supportedExtensions: Set<String> { ["swift"] }
  public var supportsAccessControl: Bool { true }

  private static let rules = SwiftLanguageRules()
  private static let extractor = DeclarationExtractor(rules: rules)

  public init() {}

  public func parse(path: String, source: String) -> ParsedFile {
    let parser = Parser()
    do {
      guard let languagePointer = tree_sitter_swift() else {
        return ParsedFile(path: path, blocks: [], hasParseError: true, languageName: languageName)
      }
      let language = Language(languagePointer)
      try parser.setLanguage(language)
    } catch {
      return ParsedFile(path: path, blocks: [], hasParseError: true, languageName: languageName)
    }

    guard let tree = parser.parse(source), let root = tree.rootNode else {
      return ParsedFile(path: path, blocks: [], hasParseError: true, languageName: languageName)
    }

    let nodes = collectDeclarationNodes(from: root, source: source)
    let blocks = nodes.compactMap { Self.extractor.extract(from: $0) }
    let metadata = SwiftSourceMetadataExtractor().extract(
      root: root, source: source, blocks: blocks)

    let evidence = TreeSitterImplementationEvidenceExtractor().extract(
      root: root,
      source: source,
      blocks: metadata.blocks,
      language: languageName
    )
    return ParsedFile(
      path: path,
      blocks: metadata.blocks,
      hasParseError: root.hasError,
      methodSyntaxEvidence: evidence,
      languageName: languageName,
      imports: metadata.imports,
      declarations: metadata.declarations
    )
  }

  // MARK: - Tree-sitter AST → DeclarationNode

  private static let declarationTypes: Set<String> = [
    "class_declaration",
    "struct_declaration",
    "enum_declaration",
    "protocol_declaration",
    "extension_declaration",
    "actor_declaration",
  ]

  private func collectDeclarationNodes(from node: Node, source: String) -> [DeclarationNode] {
    var results: [DeclarationNode] = []
    walkDeclarations(from: node, source: source, into: &results)
    return results
  }

  private func walkDeclarations(
    from node: Node, source: String, into results: inout [DeclarationNode]
  ) {
    if let nodeType = node.nodeType, Self.declarationTypes.contains(nodeType) {
      let snippet = nodeText(node: node, source: source)
      let hasMissingClosingBrace = node.hasError && !snippet.contains("}")
      let startLine = Int(node.pointRange.lowerBound.row) + 1
      let endLine = hasMissingClosingBrace ? nil : Int(node.pointRange.upperBound.row) + 1

      results.append(
        DeclarationNode(
          snippet: snippet,
          startLine: startLine,
          endLine: endLine,
          hasError: node.hasError
        ))
    }

    for childIndex in 0..<node.namedChildCount {
      guard let child = node.namedChild(at: childIndex) else {
        continue
      }
      walkDeclarations(from: child, source: source, into: &results)
    }
  }

  private func nodeText(node: Node, source: String) -> String {
    let lowerUnits = max(0, Int(node.byteRange.lowerBound / 2))
    let upperUnits = max(lowerUnits, Int(node.byteRange.upperBound / 2))
    let clampedLower = min(lowerUnits, source.utf16.count)
    let clampedUpper = min(upperUnits, source.utf16.count)
    let start = String.Index(utf16Offset: clampedLower, in: source)
    let end = String.Index(utf16Offset: clampedUpper, in: source)
    return String(source[start..<end])
  }
}

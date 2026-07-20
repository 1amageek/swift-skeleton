import Foundation
import SkeletonIndexCore
import SwiftTreeSitter

struct SwiftSourceMetadataExtractor: Sendable {
  struct Result: Sendable {
    let blocks: [SkeletonBlock]
    let imports: [SourceImport]
    let declarations: [SourceDeclaration]
  }

  func extract(root: Node, source: String, blocks: [SkeletonBlock]) -> Result {
    var imports: [SourceImport] = []
    collectImports(from: root, source: source, into: &imports)
    let declarations = collectStandaloneDeclarations(from: root, source: source)

    let blocksByStart = Dictionary(grouping: blocks.indices) { blocks[$0].range.startLine }
    var metadataByStart: [Int: BlockMetadata] = [:]
    collectBlockMetadata(
      from: root,
      source: source,
      parentAccess: nil,
      blocks: blocks,
      blocksByStart: blocksByStart,
      into: &metadataByStart
    )

    var updated = blocks.map { block in
      guard let startLine = block.range.startLine,
        let metadata = metadataByStart[startLine]
      else {
        return block
      }
      let properties = block.properties.map { property in
        let access =
          property.range.startLine.flatMap { metadata.memberAccessByStart[$0] } ?? .unknown
        return PropertySignature(
          name: property.name,
          typeRef: property.typeRef,
          range: property.range,
          access: access
        )
      }
      let methods = block.methods.map { method in
        let access = method.range.startLine.flatMap { metadata.memberAccessByStart[$0] } ?? .unknown
        return MethodSignature(
          name: method.name,
          parameterTypeRefs: method.parameterTypeRefs,
          returnTypeRef: method.returnTypeRef,
          range: method.range,
          isInitializer: method.isInitializer,
          access: access
        )
      }
      return SkeletonBlock(
        kind: block.kind,
        typeName: block.typeName,
        inheritance: block.inheritance,
        range: block.range,
        properties: properties,
        methods: methods,
        hasErrorNode: block.hasErrorNode,
        access: metadata.access,
        declarations: metadata.declarations
      )
    }

    let nominalAccessCandidates = Dictionary(
      grouping: updated.compactMap { block -> SkeletonBlock? in
        guard case .type = block.kind else {
          return nil
        }
        return block
      },
      by: \.typeName
    )
    let nominalAccess = nominalAccessCandidates.compactMapValues { blocks in
      blocks.count == 1 ? blocks[0].access : nil
    }
    updated = updated.map { block in
      guard case .extension = block.kind else {
        return block
      }
      let visibleMemberScopes =
        block.properties.map(\.access.effective) + block.methods.map(\.access.effective)
      var effective = visibleMemberScopes.reduce(AccessScope.module, mostVisible)
      if !block.inheritance.isEmpty, let typeAccess = nominalAccess[block.typeName] {
        effective = mostVisible(effective, typeAccess.effective)
      }
      let access = DeclarationAccess(
        declared: block.access.declared,
        effective: effective,
        spiGroups: block.access.spiGroups,
        allowsExternalSubclassing: block.access.allowsExternalSubclassing
      )
      return SkeletonBlock(
        kind: block.kind,
        typeName: block.typeName,
        inheritance: block.inheritance,
        range: block.range,
        properties: block.properties,
        methods: block.methods,
        hasErrorNode: block.hasErrorNode,
        access: access,
        declarations: block.declarations
      )
    }

    return Result(
      blocks: updated,
      imports: imports.sorted {
        if $0.moduleName != $1.moduleName {
          return $0.moduleName < $1.moduleName
        }
        return ($0.range.startLine ?? 0) < ($1.range.startLine ?? 0)
      },
      declarations: declarations
    )
  }

  private struct BlockMetadata {
    let access: DeclarationAccess
    let memberAccessByStart: [Int: DeclarationAccess]
    let declarations: [SourceDeclaration]
  }

  private func collectImports(from node: Node, source: String, into imports: inout [SourceImport]) {
    if node.nodeType == "import_declaration",
      let importValue = sourceImport(from: node, source: source)
    {
      imports.append(importValue)
      return
    }
    for index in 0..<node.namedChildCount {
      guard let child = node.namedChild(at: index) else {
        continue
      }
      collectImports(from: child, source: source, into: &imports)
    }
  }

  private func sourceImport(from node: Node, source: String) -> SourceImport? {
    var identifierNode: Node?
    var modifiersNode: Node?
    for index in 0..<node.namedChildCount {
      guard let child = node.namedChild(at: index) else {
        continue
      }
      if child.nodeType == "identifier" {
        identifierNode = child
      } else if child.nodeType == "modifiers" {
        modifiersNode = child
      }
    }
    guard let identifierNode else {
      return nil
    }
    let identifier = nodeText(identifierNode, source: source)
    guard let moduleName = identifier.split(separator: ".").first.map(String.init),
      !moduleName.isEmpty
    else {
      return nil
    }
    let modifiers = modifiersNode.map { nodeText($0, source: source) } ?? ""
    return SourceImport(
      moduleName: moduleName,
      access: accessScope(in: modifiers),
      isTestable: modifiers.contains("@testable"),
      isReexported: modifiers.contains("@_exported"),
      spiGroups: spiGroups(in: modifiers),
      range: sourceRange(for: node)
    )
  }

  private func collectBlockMetadata(
    from node: Node,
    source: String,
    parentAccess: AccessScope?,
    blocks: [SkeletonBlock],
    blocksByStart: [Int?: [Array<SkeletonBlock>.Index]],
    into metadata: inout [Int: BlockMetadata]
  ) {
    let startLine = Int(node.pointRange.lowerBound.row) + 1
    let matchingBlock =
      blockDeclarationNodeTypes.contains(node.nodeType ?? "")
      ? blocksByStart[startLine]?.first.map { blocks[$0] }
      : nil
    let isDeclaration = matchingBlock != nil
    let access: DeclarationAccess?

    if let matchingBlock {
      let defaultScope: AccessScope = .module
      access = declarationAccess(
        for: node,
        source: source,
        defaultScope: defaultScope,
        parentAccess: parentAccess
      )
      let memberDefault: AccessScope
      if node.nodeType == "protocol_declaration" {
        memberDefault = access?.effective ?? .module
      } else if case .extension = matchingBlock.kind,
        let declared = explicitAccessScope(for: node, source: source)
      {
        memberDefault = declared
      } else {
        memberDefault = .module
      }
      var memberAccessByStart: [Int: DeclarationAccess] = [:]
      var declarations: [SourceDeclaration] = []
      if let body = declarationBody(of: node) {
        collectDirectMemberAccess(
          from: body,
          source: source,
          defaultScope: memberDefault,
          parentAccess: access?.effective,
          into: &memberAccessByStart
        )
        declarations = collectMemberDeclarations(
          from: body,
          source: source,
          defaultScope: memberDefault,
          parentAccess: access?.effective
        )
      }
      metadata[startLine] = BlockMetadata(
        access: access ?? .unknown,
        memberAccessByStart: memberAccessByStart,
        declarations: declarations
      )
    } else {
      access = nil
    }

    for index in 0..<node.namedChildCount {
      guard let child = node.namedChild(at: index) else {
        continue
      }
      collectBlockMetadata(
        from: child,
        source: source,
        parentAccess: isDeclaration ? access?.effective : parentAccess,
        blocks: blocks,
        blocksByStart: blocksByStart,
        into: &metadata
      )
    }
  }

  private func collectStandaloneDeclarations(from root: Node, source: String) -> [SourceDeclaration]
  {
    var declarations: [SourceDeclaration] = []
    for index in 0..<root.namedChildCount {
      guard let child = root.namedChild(at: index),
        let kind = declarationKind(for: child.nodeType),
        !blockDeclarationNodeTypes.contains(child.nodeType ?? "")
      else {
        continue
      }
      let defaultScope: AccessScope = child.nodeType == "operator_declaration" ? .exported : .module
      declarations.append(
        SourceDeclaration(
          kind: kind,
          signature: signatureText(for: child, source: source),
          range: sourceRange(for: child),
          access: declarationAccess(
            for: child,
            source: source,
            defaultScope: defaultScope,
            parentAccess: nil
          )
        )
      )
    }
    return declarations
  }

  private func collectMemberDeclarations(
    from body: Node,
    source: String,
    defaultScope: AccessScope,
    parentAccess: AccessScope?
  ) -> [SourceDeclaration] {
    var declarations: [SourceDeclaration] = []
    for index in 0..<body.namedChildCount {
      guard let child = body.namedChild(at: index),
        let kind = declarationKind(for: child.nodeType),
        !["function_declaration", "property_declaration"].contains(child.nodeType ?? "")
      else {
        continue
      }
      let declarationDefaultScope =
        child.nodeType == "enum_entry"
        ? parentAccess ?? defaultScope
        : defaultScope
      declarations.append(
        SourceDeclaration(
          kind: kind,
          signature: signatureText(for: child, source: source),
          range: sourceRange(for: child),
          access: declarationAccess(
            for: child,
            source: source,
            defaultScope: declarationDefaultScope,
            parentAccess: parentAccess
          )
        )
      )
    }
    return declarations
  }

  private func declarationKind(for nodeType: String?) -> SourceDeclarationKind? {
    switch nodeType {
    case "function_declaration":
      .function
    case "property_declaration":
      .variable
    case "typealias_declaration":
      .typealiasDeclaration
    case "associatedtype_declaration":
      .associatedType
    case "enum_entry":
      .enumCase
    case "subscript_declaration":
      .subscriptDeclaration
    case "operator_declaration":
      .operatorDeclaration
    case "macro_declaration":
      .macro
    default:
      nil
    }
  }

  private func signatureText(for node: Node, source: String) -> String {
    var upperBound = node.byteRange.upperBound
    let excludedNodeTypes: Set<String> = [
      "function_body",
      "computed_property",
      "willset_didset_block",
    ]
    for index in 0..<node.namedChildCount {
      guard let child = node.namedChild(at: index),
        let childType = child.nodeType
      else {
        continue
      }
      if excludedNodeTypes.contains(childType) || childType.hasSuffix("_body") {
        upperBound = min(upperBound, child.byteRange.lowerBound)
      }
    }
    if let value = node.child(byFieldName: "value"), node.nodeType == "property_declaration" {
      upperBound = min(upperBound, value.byteRange.lowerBound)
    }
    var text = nodeText(
      lowerBound: node.byteRange.lowerBound,
      upperBound: upperBound,
      source: source
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasSuffix("=") {
      text.removeLast()
    }
    var signature =
      text
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
    let compactPairs = [
      ("( ", "("), (" )", ")"), ("[ ", "["), (" ]", "]"), ("< ", "<"), (" >", ">"),
    ]
    for (source, replacement) in compactPairs {
      signature = signature.replacingOccurrences(of: source, with: replacement)
    }
    return signature
  }

  private var blockDeclarationNodeTypes: Set<String> {
    [
      "class_declaration",
      "struct_declaration",
      "enum_declaration",
      "protocol_declaration",
      "extension_declaration",
      "actor_declaration",
    ]
  }

  private func declarationBody(of node: Node) -> Node? {
    if let body = node.child(byFieldName: "body") {
      return body
    }
    for index in 0..<node.namedChildCount {
      guard let child = node.namedChild(at: index),
        let nodeType = child.nodeType,
        nodeType.hasSuffix("_body")
      else {
        continue
      }
      return child
    }
    return nil
  }

  private func collectDirectMemberAccess(
    from body: Node,
    source: String,
    defaultScope: AccessScope,
    parentAccess: AccessScope?,
    into result: inout [Int: DeclarationAccess]
  ) {
    let memberTypes: Set<String> = [
      "property_declaration",
      "function_declaration",
      "protocol_function_declaration",
      "init_declaration",
      "subscript_declaration",
      "protocol_property_declaration",
    ]
    for index in 0..<body.namedChildCount {
      guard let child = body.namedChild(at: index),
        let nodeType = child.nodeType,
        memberTypes.contains(nodeType)
      else {
        continue
      }
      let line = Int(child.pointRange.lowerBound.row) + 1
      result[line] = declarationAccess(
        for: child,
        source: source,
        defaultScope: defaultScope,
        parentAccess: parentAccess
      )
    }
  }

  private func declarationAccess(
    for node: Node,
    source: String,
    defaultScope: AccessScope,
    parentAccess: AccessScope?
  ) -> DeclarationAccess {
    let modifiers = directModifiersText(for: node, source: source)
    let declared = accessScope(in: modifiers) ?? defaultScope
    let effective = parentAccess.map { leastVisible(declared, $0) } ?? declared
    let setter = setterAccessScope(in: modifiers).map { setterScope in
      parentAccess.map { leastVisible(setterScope, $0) } ?? setterScope
    }
    return DeclarationAccess(
      declared: declared,
      effective: effective,
      setter: setter,
      spiGroups: spiGroups(in: modifiers),
      allowsExternalSubclassing:
        modifiers
        .split(whereSeparator: \Character.isWhitespace)
        .contains("open")
    )
  }

  private func explicitAccessScope(for node: Node, source: String) -> AccessScope? {
    accessScope(in: directModifiersText(for: node, source: source))
  }

  private func directModifiersText(for node: Node, source: String) -> String {
    for index in 0..<node.namedChildCount {
      guard let child = node.namedChild(at: index), child.nodeType == "modifiers" else {
        continue
      }
      return nodeText(child, source: source)
    }
    return ""
  }

  private func accessScope(in modifiers: String) -> AccessScope? {
    let words =
      modifiers
      .replacingOccurrences(of: "(", with: " ")
      .replacingOccurrences(of: ")", with: " ")
      .split(whereSeparator: \Character.isWhitespace)
      .map(String.init)
    if words.contains("open") || words.contains("public") {
      return .exported
    }
    if words.contains("package") {
      return .package
    }
    if words.contains("internal") {
      return .module
    }
    if words.contains("fileprivate") {
      return .file
    }
    if words.contains("private") {
      return .lexical
    }
    return nil
  }

  private func setterAccessScope(in modifiers: String) -> AccessScope? {
    let candidates: [(String, AccessScope)] = [
      ("private(set)", .lexical),
      ("fileprivate(set)", .file),
      ("internal(set)", .module),
      ("package(set)", .package),
    ]
    return candidates.first { modifiers.contains($0.0) }?.1
  }

  private func spiGroups(in modifiers: String) -> [String] {
    var groups: [String] = []
    var remainder = modifiers[...]
    while let marker = remainder.range(of: "@_spi") {
      remainder = remainder[marker.upperBound...]
      guard let open = remainder.firstIndex(of: "("),
        let close = remainder[remainder.index(after: open)...].firstIndex(of: ")")
      else {
        break
      }
      let group = remainder[remainder.index(after: open)..<close]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !group.isEmpty {
        groups.append(group)
      }
      remainder = remainder[remainder.index(after: close)...]
    }
    return groups
  }

  private func sourceRange(for node: Node) -> SourceRange {
    SourceRange(
      startLine: Int(node.pointRange.lowerBound.row) + 1,
      endLine: Int(node.pointRange.upperBound.row) + 1
    )
  }

  private func nodeText(_ node: Node, source: String) -> String {
    nodeText(
      lowerBound: node.byteRange.lowerBound,
      upperBound: node.byteRange.upperBound,
      source: source
    )
  }

  private func nodeText(
    lowerBound: UInt32,
    upperBound: UInt32,
    source: String
  ) -> String {
    let lowerUnits = max(0, Int(lowerBound / 2))
    let upperUnits = max(lowerUnits, Int(upperBound / 2))
    let clampedLower = min(lowerUnits, source.utf16.count)
    let clampedUpper = min(upperUnits, source.utf16.count)
    let start = String.Index(utf16Offset: clampedLower, in: source)
    let end = String.Index(utf16Offset: clampedUpper, in: source)
    return String(source[start..<end])
  }

  private func leastVisible(_ lhs: AccessScope, _ rhs: AccessScope) -> AccessScope {
    visibilityRank(lhs) <= visibilityRank(rhs) ? lhs : rhs
  }

  private func mostVisible(_ lhs: AccessScope, _ rhs: AccessScope) -> AccessScope {
    visibilityRank(lhs) >= visibilityRank(rhs) ? lhs : rhs
  }

  private func visibilityRank(_ scope: AccessScope) -> Int {
    switch scope {
    case .exported:
      4
    case .package:
      3
    case .module:
      2
    case .file:
      1
    case .lexical:
      0
    case .subclass, .unknown:
      -1
    }
  }
}

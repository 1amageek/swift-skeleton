import Foundation

public struct DeclarationExtractor: Sendable {
  private let rules: any LanguageRules

  public init(rules: any LanguageRules) {
    self.rules = rules
  }

  public func extract(from node: DeclarationNode) -> SkeletonBlock? {
    // Line views are materialized once per declaration snippet. Structural scans read `code`;
    // rendered names and type references are sliced from `text` at the same Character offsets.
    let lines = SourceLexer.lexLines(
      TextUtilities.sourceLines(node.snippet),
      syntax: rules.lexicalSyntax
    )
    guard let declaration = declarationHeader(from: headerCode(from: lines)) else {
      return nil
    }

    let range = SourceRange(
      startLine: node.startLine,
      endLine: node.endLine
    )

    let members = parseMembers(in: lines, declarationStartLine: node.startLine)

    return SkeletonBlock(
      kind: declaration.kind,
      typeName: declaration.typeName,
      inheritance: declaration.inheritance,
      range: range,
      properties: members.properties,
      methods: members.methods,
      hasErrorNode: node.hasError
    )
  }

  // MARK: - Declaration Header

  private func declarationHeader(from header: String) -> (
    kind: SkeletonBlockKind, typeName: String, inheritance: [String]
  )? {
    if let extensionPattern = rules.extensionPattern {
      let fullPattern =
        #"\b"# + extensionPattern.keyword + #"\s+"# + extensionPattern.typeNamePattern
      if let typeName = TextUtilities.firstRegex(pattern: fullPattern, in: header) {
        return (
          kind: .extension, typeName: typeName, inheritance: rules.parseInheritance(from: header)
        )
      }
    }

    guard let typeHeader = rules.parseTypeHeader(header) else {
      return nil
    }
    return (
      kind: .type(typeHeader.keyword),
      typeName: typeHeader.name,
      inheritance: rules.parseInheritance(from: header)
    )
  }

  /// Code before the body brace, joined into one line. A `{` nested in parentheses or brackets
  /// (for example a decorator argument such as `@Component({ … })`) does not end the header.
  private func headerCode(from lines: [SourceLexer.Line]) -> String {
    var header = ""
    var parenthesisDepth = 0
    var bracketDepth = 0
    for (lineIndex, line) in lines.enumerated() {
      if lineIndex > 0 {
        header.append(" ")
      }
      for character in line.code {
        switch character {
        case "(":
          parenthesisDepth += 1
        case ")":
          parenthesisDepth = max(0, parenthesisDepth - 1)
        case "[":
          bracketDepth += 1
        case "]":
          bracketDepth = max(0, bracketDepth - 1)
        case "{" where parenthesisDepth == 0 && bracketDepth == 0:
          return header
        default:
          break
        }
        header.append(character)
      }
    }
    return header
  }

  // MARK: - Members

  private func parseMembers(in lines: [SourceLexer.Line], declarationStartLine: Int) -> (
    properties: [PropertySignature], methods: [MethodSignature]
  ) {
    var properties: [PropertySignature] = []
    var methods: [MethodSignature] = []
    var braceDepth = 0
    var parenthesisDepth = 0
    // Lines up to this index belong to the signature of the last method (multi-line parameter
    // lists, `where` clauses) and never start a member.
    var signatureEndIndex = -1

    for lineIndex in lines.indices {
      let line = lines[lineIndex]
      if braceDepth == 1 && parenthesisDepth == 0 && lineIndex > signatureEndIndex {
        if let capture = propertyCapture(in: line) {
          let propertyLine = declarationStartLine + lineIndex
          properties.append(
            PropertySignature(
              name: capture.name,
              typeRef: capture.typeRef,
              range: SourceRange(startLine: propertyLine, endLine: propertyLine)
            )
          )
        }

        if let method = parseMethod(
          at: lineIndex,
          lines: lines,
          declarationStartLine: declarationStartLine
        ) {
          methods.append(method.signature)
          signatureEndIndex = method.signatureEndIndex
        }
      }
      for character in line.code {
        switch character {
        case "{":
          braceDepth += 1
        case "}":
          braceDepth -= 1
        case "(":
          parenthesisDepth += 1
        case ")":
          parenthesisDepth = max(0, parenthesisDepth - 1)
        default:
          break
        }
      }
    }

    return (properties, methods)
  }

  private func propertyCapture(in line: SourceLexer.Line) -> (name: String, typeRef: String)? {
    guard let ranges = TextUtilities.firstRegexRanges(pattern: rules.propertyPattern, in: line.code),
      ranges.captures.count >= 2,
      let nameRange = ranges.captures[0],
      let typeRange = ranges.captures[1],
      let name = Self.textSlice(of: line, codeRange: nameRange),
      let typeRef = Self.textSlice(of: line, codeRange: typeRange)
    else {
      return nil
    }
    return (name: name, typeRef: typeRef)
  }

  /// Maps a range in `line.code` to the same Character offsets in `line.text`.
  private static func textSlice(of line: SourceLexer.Line, codeRange: Range<String.Index>)
    -> String?
  {
    let lowerOffset = line.code.distance(from: line.code.startIndex, to: codeRange.lowerBound)
    let length = line.code.distance(from: codeRange.lowerBound, to: codeRange.upperBound)
    guard
      let lower = line.text.index(
        line.text.startIndex, offsetBy: lowerOffset, limitedBy: line.text.endIndex),
      let upper = line.text.index(lower, offsetBy: length, limitedBy: line.text.endIndex)
    else {
      return nil
    }
    let slice = line.text[lower..<upper].trimmingCharacters(in: .whitespacesAndNewlines)
    return slice.isEmpty ? nil : slice
  }

  // MARK: - Method Parsing

  private func parseMethod(
    at lineIndex: Int,
    lines: [SourceLexer.Line],
    declarationStartLine: Int
  ) -> (signature: MethodSignature, signatureEndIndex: Int)? {
    let trimmed = lines[lineIndex].code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let methodStart = rules.parseMethodStart(from: trimmed) else {
      return nil
    }

    let extent = methodExtent(lines: lines, startIndex: lineIndex)
    let signature = SignatureText(
      lines: lines[lineIndex...extent.signatureEndIndex],
      methodName: methodStart.name
    )
    let params = signature.parameterTypeRefs()
    let returnType = methodStart.isInitializer ? nil : parseReturnType(signature)
    let startLine = declarationStartLine + lineIndex
    let endLine = extent.endIndex.map { declarationStartLine + $0 }

    return (
      signature: MethodSignature(
        name: methodStart.name,
        parameterTypeRefs: params,
        returnTypeRef: returnType,
        range: SourceRange(startLine: startLine, endLine: endLine),
        isInitializer: methodStart.isInitializer
      ),
      signatureEndIndex: extent.signatureEndIndex
    )
  }

  /// Finds the line that ends the signature (the body brace, `;`, or an expression-body `=`) and
  /// the line that ends the whole method. `endIndex` is nil when the body is never closed.
  private func methodExtent(lines: [SourceLexer.Line], startIndex: Int) -> (
    signatureEndIndex: Int, endIndex: Int?
  ) {
    var parenthesisDepth = 0
    var signatureComplete = false
    var inWhereClause = false
    var bodyFound = false
    var bodyDepth = 0
    var signatureEndIndex = startIndex

    for index in startIndex..<lines.count {
      let code = Array(lines[index].code)
      for position in code.indices {
        let character = code[position]
        if bodyFound {
          if character == "{" {
            bodyDepth += 1
          } else if character == "}" {
            bodyDepth -= 1
            if bodyDepth == 0 {
              return (signatureEndIndex, index)
            }
          }
          continue
        }
        switch character {
        case "(":
          parenthesisDepth += 1
        case ")":
          parenthesisDepth = max(0, parenthesisDepth - 1)
          if parenthesisDepth == 0 {
            signatureComplete = true
          }
        case "{" where signatureComplete && parenthesisDepth == 0:
          bodyFound = true
          bodyDepth = 1
          signatureEndIndex = index
        case ";" where signatureComplete && parenthesisDepth == 0:
          return (index, index)
        case "=" where signatureComplete && parenthesisDepth == 0
          && Self.isAssignment(code, at: position):
          return (index, index)
        default:
          break
        }
      }

      if bodyFound {
        continue
      }
      signatureEndIndex = index
      // An open parenthesis after the parameter list (for example a multi-line tuple return
      // type) keeps the signature going.
      if !signatureComplete || parenthesisDepth > 0 {
        continue
      }
      if TextUtilities.firstRegex(pattern: #"\b(where)\b"#, in: lines[index].code) != nil {
        inWhereClause = true
      }
      if index + 1 >= lines.count {
        return (index, index)
      }
      if inWhereClause {
        continue
      }
      let next = lines[index + 1].code.trimmingCharacters(in: .whitespacesAndNewlines)
      let continuesSignature =
        next.hasPrefix("{") || next.hasPrefix("->") || next.hasPrefix(":")
        || next.hasPrefix("throws")
        || TextUtilities.firstRegex(pattern: #"^(where)\b"#, in: next) != nil
      if continuesSignature {
        continue
      }
      return (index, index)
    }
    return (signatureEndIndex, nil)
  }

  /// `=` that is not part of `==`, `!=`, `<=`, `>=`, or `=>`.
  fileprivate static func isAssignment(_ code: [Character], at index: Int) -> Bool {
    let previous = index > code.startIndex ? code[index - 1] : " "
    let next = index + 1 < code.endIndex ? code[index + 1] : " "
    return previous != "=" && previous != "!" && previous != "<" && previous != ">"
      && next != "=" && next != ">"
  }

  // MARK: - Return Type

  private func parseReturnType(_ signature: SignatureText) -> String? {
    guard let open = signature.parameterListOpen,
      let close = signature.matchingClose(from: open)
    else {
      return nil
    }
    let afterClose = close + 1
    let bodyStart =
      signature.firstTopLevelIndex(from: afterClose) { code, index in
        code[index] == "{" || code[index] == ";"
          || (code[index] == "=" && Self.isAssignment(code, at: index))
      } ?? signature.code.endIndex
    guard
      let tokenRange = signature.firstOccurrence(of: rules.returnTypeToken, in: afterClose..<bodyStart)
    else {
      return nil
    }
    let raw = signature.text(in: tokenRange.upperBound..<bodyStart)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let returnText = normalizeTypeWhitespace(rules.cleanReturnType(raw))
    return returnText.isEmpty ? nil : returnText
  }

  private func normalizeTypeWhitespace(_ typeRef: String) -> String {
    var normalized =
      typeRef
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
    let compactPairs = [
      ("( ", "("), (" )", ")"), ("[ ", "["), (" ]", "]"), ("< ", "<"), (" >", ">"),
    ]
    for (source, replacement) in compactPairs {
      normalized = normalized.replacingOccurrences(of: source, with: replacement)
    }
    return normalized
  }
}

/// A method signature spanning one or more lines, joined with single spaces, in the same two
/// views as `SourceLexer.Line`. Structure is scanned in `code`; rendered text is read from `text`.
private struct SignatureText {
  let code: [Character]
  let textCharacters: [Character]
  /// Index of the `(` that opens the parameter list: the first `(` after the method name, so
  /// parenthesized attributes or annotations before the name (`@_spi(X) func f(`,
  /// `@JvmName("x") fun f(`) are skipped. Nil when the name or the parenthesis is not found.
  let parameterListOpen: Int?

  init(lines: ArraySlice<SourceLexer.Line>, methodName: String) {
    var code: [Character] = []
    var text: [Character] = []
    for (offset, line) in lines.enumerated() {
      if offset > 0 {
        code.append(" ")
        text.append(" ")
      }
      let lineCode = Array(line.code)
      let lineText = Array(line.text)
      code.append(contentsOf: lineCode)
      // `SourceLexer` guarantees equal Character counts. If that invariant were ever broken, the
      // masked code is used so offsets stay aligned; literal text is then shown as blanks rather
      // than as misaligned characters.
      text.append(contentsOf: lineText.count == lineCode.count ? lineText : lineCode)
    }
    self.code = code
    self.textCharacters = text
    self.parameterListOpen = Self.wordEnd(of: Array(methodName), in: code).flatMap { nameEnd in
      code[nameEnd...].firstIndex(of: "(")
    }
  }

  /// End index of the first whole-word occurrence of `word` in `code`.
  private static func wordEnd(of word: [Character], in code: [Character]) -> Int? {
    guard !word.isEmpty, code.count >= word.count else {
      return nil
    }
    for start in 0...(code.count - word.count)
    where code[start..<(start + word.count)].elementsEqual(word) {
      let end = start + word.count
      let boundaryBefore = start == 0 || !isIdentifierCharacter(code[start - 1])
      let boundaryAfter = end == code.count || !isIdentifierCharacter(code[end])
      if boundaryBefore && boundaryAfter {
        return end
      }
    }
    return nil
  }

  private static func isIdentifierCharacter(_ character: Character) -> Bool {
    character == "_" || character == "$" || character.isLetter || character.isNumber
  }

  func text(in range: Range<Int>) -> String {
    String(textCharacters[range])
  }

  func matchingClose(from open: Int) -> Int? {
    var depth = 0
    for index in open..<code.count {
      if code[index] == "(" {
        depth += 1
      } else if code[index] == ")" {
        depth -= 1
        if depth == 0 {
          return index
        }
      }
    }
    return nil
  }

  func firstOccurrence(of token: String, in range: Range<Int>) -> Range<Int>? {
    let tokenCharacters = Array(token)
    guard !tokenCharacters.isEmpty, range.count >= tokenCharacters.count else {
      return nil
    }
    for start in range.lowerBound...(range.upperBound - tokenCharacters.count)
    where code[start..<(start + tokenCharacters.count)].elementsEqual(tokenCharacters) {
      return start..<(start + tokenCharacters.count)
    }
    return nil
  }

  /// First index at or after `start` (and before `end`) where `predicate` holds outside of
  /// parentheses, brackets, braces, and angle brackets. `>` of `->` and `=>` is not a closer.
  func firstTopLevelIndex(
    from start: Int,
    to end: Int? = nil,
    where predicate: ([Character], Int) -> Bool
  ) -> Int? {
    var depth = 0
    var angleDepth = 0
    let upperBound = end ?? code.count
    var index = start
    while index < upperBound {
      if depth == 0 && angleDepth == 0 && predicate(code, index) {
        return index
      }
      switch code[index] {
      case "(", "[", "{":
        depth += 1
      case ")", "]", "}":
        depth = max(0, depth - 1)
      case "<":
        angleDepth += 1
      case ">":
        let previous = index > 0 ? code[index - 1] : " "
        if previous != "-" && previous != "=" {
          angleDepth = max(0, angleDepth - 1)
        }
      default:
        break
      }
      index += 1
    }
    return nil
  }

  /// Parameter type references of the first parameter list. A parameter without a type
  /// annotation is `?`. A trailing comma does not add a parameter.
  func parameterTypeRefs() -> [String] {
    guard let open = parameterListOpen, let close = matchingClose(from: open) else {
      return []
    }
    var chunks: [Range<Int>] = []
    var chunkStart = open + 1
    while let comma = firstTopLevelIndex(from: chunkStart, to: close, where: { $0[$1] == "," }) {
      chunks.append(chunkStart..<comma)
      chunkStart = comma + 1
    }
    chunks.append(chunkStart..<close)

    if chunks.count == 1 && isBlank(chunks[0]) {
      return []
    }
    if chunks.count > 1, let last = chunks.last, isBlank(last) {
      chunks.removeLast()
    }

    return chunks.map { chunk in
      guard
        let colon = firstTopLevelIndex(
          from: chunk.lowerBound, to: chunk.upperBound, where: { code, index in
            code[index] == ":" && !isPathSeparator(code, at: index)
          })
      else {
        return "?"
      }
      let typeEnd =
        firstTopLevelIndex(from: colon + 1, to: chunk.upperBound) { code, index in
          code[index] == "=" && DeclarationExtractor.isAssignment(code, at: index)
        } ?? chunk.upperBound
      let typeRef = text(in: (colon + 1)..<typeEnd)
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
      return typeRef.isEmpty ? "?" : typeRef
    }
  }

  private func isBlank(_ range: Range<Int>) -> Bool {
    code[range].allSatisfy(\.isWhitespace)
  }

  private func isPathSeparator(_ code: [Character], at index: Int) -> Bool {
    (index > 0 && code[index - 1] == ":") || (index + 1 < code.count && code[index + 1] == ":")
  }
}

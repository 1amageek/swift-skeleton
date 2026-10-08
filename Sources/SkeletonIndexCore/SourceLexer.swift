/// Separates code from string literals and comments, line by line, so that structural scans
/// (brace depth, parenthesis depth, member detection) only see code characters.
///
/// The lexer is stateful: block comments, multi-line strings, template literals, and raw strings
/// carry over to the following lines. Single-line literals that are still open at the end of a
/// line are closed there, which bounds the damage of an unterminated literal to one line.
///
/// Each lexed line keeps the Character count of its source line in both views, so a range found
/// in `code` addresses the same characters in `text`. Masked characters become a space, except
/// whitespace and control characters, which are kept as-is so that grapheme segmentation (and
/// therefore the Character count) does not change.
public struct SourceLexer: Sendable {
  /// One source line in two views with identical Character counts.
  public struct Line: Sendable, Equatable {
    /// Code characters only. Literal and comment characters are masked.
    public let code: String
    /// Code and literal characters. Comment characters are masked.
    public let text: String

    public init(code: String, text: String) {
      self.code = code
      self.text = text
    }
  }

  private enum StringKind: Sendable, Equatable {
    case doubleQuoted
    case singleQuoted
    case tripleQuoted
    case template
    case raw(hashes: Int)

    var processesEscapes: Bool {
      switch self {
      case .doubleQuoted, .singleQuoted, .template:
        return true
      case .tripleQuoted, .raw:
        return false
      }
    }
  }

  private enum Context: Sendable, Equatable {
    case blockComment(depth: Int)
    case string(StringKind)
    case interpolation(braceDepth: Int)
  }

  private enum Category {
    case code
    case literal
    case comment
  }

  public let syntax: LexicalSyntax
  private var contexts: [Context] = []

  public init(syntax: LexicalSyntax) {
    self.syntax = syntax
  }

  /// Lexes consecutive source lines that belong to one source text.
  public static func lexLines(_ lines: [String], syntax: LexicalSyntax) -> [Line] {
    var lexer = SourceLexer(syntax: syntax)
    return lines.map { lexer.lex($0) }
  }

  /// Net `{` minus `}` count over the code of `source`. A positive value means the source has
  /// braces that are opened but never closed.
  public static func braceBalance(of source: String, syntax: LexicalSyntax) -> Int {
    var lexer = SourceLexer(syntax: syntax)
    var balance = 0
    for line in TextUtilities.sourceLines(source) {
      for character in lexer.lex(line).code {
        if character == "{" {
          balance += 1
        } else if character == "}" {
          balance -= 1
        }
      }
    }
    return balance
  }

  /// Lexes the next line. `line` must not contain line terminators.
  public mutating func lex(_ line: String) -> Line {
    let characters = Array(line)
    var code = ""
    var text = ""
    code.reserveCapacity(line.utf8.count)
    text.reserveCapacity(line.utf8.count)
    var index = 0

    func append(_ count: Int, _ category: Category) {
      let end = min(characters.count, index + count)
      while index < end {
        let character = characters[index]
        switch category {
        case .code:
          code.append(character)
          text.append(character)
        case .literal:
          code.append(Self.masked(character))
          text.append(character)
        case .comment:
          code.append(Self.masked(character))
          text.append(Self.masked(character))
        }
        index += 1
      }
    }

    func peek(_ offset: Int) -> Character? {
      let position = index + offset
      return position < characters.count ? characters[position] : nil
    }

    while index < characters.count {
      let character = characters[index]
      switch contexts.last {
      case .blockComment(let depth)?:
        if character == "*" && peek(1) == "/" {
          contexts.removeLast()
          if depth > 1 {
            contexts.append(.blockComment(depth: depth - 1))
          }
          append(2, .comment)
        } else if syntax.nestedBlockComments && character == "/" && peek(1) == "*" {
          contexts[contexts.count - 1] = .blockComment(depth: depth + 1)
          append(2, .comment)
        } else {
          append(1, .comment)
        }

      case .string(let kind)?:
        if kind.processesEscapes && character == "\\" {
          append(2, .literal)
        } else if allowsInterpolation(in: kind) && character == "$" && peek(1) == "{" {
          contexts.append(.interpolation(braceDepth: 1))
          append(2, .literal)
        } else if let closerLength = closerLength(of: kind, in: characters, at: index) {
          contexts.removeLast()
          append(closerLength, .literal)
        } else {
          append(1, .literal)
        }

      case .interpolation, nil:
        let category: Category = contexts.isEmpty ? .code : .literal
        if syntax.lineComments && character == "/" && peek(1) == "/" {
          append(characters.count - index, .comment)
        } else if syntax.blockComments && character == "/" && peek(1) == "*" {
          contexts.append(.blockComment(depth: 1))
          append(2, .comment)
        } else if character == "\"" {
          if syntax.tripleQuotedStrings && peek(1) == "\"" && peek(2) == "\"" {
            contexts.append(.string(.tripleQuoted))
            append(3, .literal)
          } else {
            contexts.append(.string(.doubleQuoted))
            append(1, .literal)
          }
        } else if character == "'" && syntax.singleQuote == .literal {
          contexts.append(.string(.singleQuoted))
          append(1, .literal)
        } else if character == "'" && syntax.singleQuote == .characterLiteralOrLifetime {
          if peek(1) == "\\" {
            contexts.append(.string(.singleQuoted))
            append(1, .literal)
          } else if peek(1) != nil && peek(2) == "'" {
            append(3, .literal)
          } else {
            // A lifetime or loop label such as `'a` is code.
            append(1, category)
          }
        } else if character == "`" && syntax.templateLiterals {
          contexts.append(.string(.template))
          append(1, .literal)
        } else if syntax.rawStrings, let prefix = rawStringPrefix(in: characters, at: index) {
          contexts.append(.string(.raw(hashes: prefix.hashes)))
          append(prefix.length, .literal)
        } else {
          if case .interpolation(let depth)? = contexts.last {
            if character == "{" {
              contexts[contexts.count - 1] = .interpolation(braceDepth: depth + 1)
            } else if character == "}" {
              contexts.removeLast()
              if depth > 1 {
                contexts.append(.interpolation(braceDepth: depth - 1))
              }
            }
          }
          append(1, category)
        }
      }
    }

    closeSingleLineLiterals()
    return Line(code: code, text: text)
  }

  // MARK: - Literal Rules

  private func allowsInterpolation(in kind: StringKind) -> Bool {
    switch kind {
    case .template:
      return true
    case .doubleQuoted, .tripleQuoted:
      return syntax.dollarBraceInterpolation
    case .singleQuoted, .raw:
      return false
    }
  }

  private func closerLength(of kind: StringKind, in characters: [Character], at index: Int) -> Int? {
    let character = characters[index]
    switch kind {
    case .doubleQuoted:
      return character == "\"" ? 1 : nil
    case .singleQuoted:
      return character == "'" ? 1 : nil
    case .template:
      return character == "`" ? 1 : nil
    case .tripleQuoted:
      guard index + 2 < characters.count else {
        return nil
      }
      let isCloser =
        character == "\"" && characters[index + 1] == "\"" && characters[index + 2] == "\""
      return isCloser ? 3 : nil
    case .raw(let hashes):
      guard character == "\"", index + hashes < characters.count else {
        return nil
      }
      for offset in 0..<hashes where characters[index + 1 + offset] != "#" {
        return nil
      }
      return 1 + hashes
    }
  }

  /// Recognizes `r"`, `r#…#"`, `br"`, and `br#…#"` at an identifier boundary.
  private func rawStringPrefix(in characters: [Character], at index: Int) -> (
    length: Int, hashes: Int
  )? {
    if index > 0 && Self.isIdentifierCharacter(characters[index - 1]) {
      return nil
    }
    var position = index
    if characters[position] == "b" {
      position += 1
    }
    guard position < characters.count, characters[position] == "r" else {
      return nil
    }
    position += 1
    var hashes = 0
    while position < characters.count && characters[position] == "#" {
      hashes += 1
      position += 1
    }
    guard position < characters.count, characters[position] == "\"" else {
      return nil
    }
    return (length: position - index + 1, hashes: hashes)
  }

  private mutating func closeSingleLineLiterals() {
    while case .string(let kind)? = contexts.last {
      switch kind {
      case .singleQuoted:
        contexts.removeLast()
      case .doubleQuoted where !syntax.doubleQuotedStringsSpanLines:
        contexts.removeLast()
      default:
        return
      }
    }
  }

  private static func isIdentifierCharacter(_ character: Character) -> Bool {
    character == "_" || character.isLetter || character.isNumber
  }

  private static func masked(_ character: Character) -> Character {
    if character.isWhitespace
      || character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    {
      return character
    }
    return " "
  }
}

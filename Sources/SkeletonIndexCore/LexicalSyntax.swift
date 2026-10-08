/// Describes the comment and literal syntax that `SourceLexer` must skip when it counts
/// structural characters such as braces and parentheses.
///
/// The lexer does not tokenize the language. It only needs to know which character sequences
/// start and end text that is not code, so that a `{` inside a string, character literal, or
/// comment never changes the structural depth of the surrounding declaration.
public struct LexicalSyntax: Sendable, Equatable {
  /// How a single quote (`'`) is interpreted outside of other literals.
  public enum SingleQuote: Sendable, Equatable {
    /// `'` has no literal meaning.
    case none
    /// `'` opens a single-line literal closed by an unescaped `'` (string or character literal).
    case literal
    /// `'` opens a character literal only when it has the shape `'x'` or `'\…'`;
    /// otherwise it is code, such as a Rust lifetime or loop label (`'a`).
    case characterLiteralOrLifetime
  }

  /// `//` starts a comment that runs to the end of the line.
  public var lineComments: Bool
  /// `/* … */` block comments.
  public var blockComments: Bool
  /// Block comments nest (`/* /* */ */`).
  public var nestedBlockComments: Bool
  /// Double-quoted strings may continue on the following line.
  public var doubleQuotedStringsSpanLines: Bool
  /// `"""` opens a string that ends at the next `"""`, may span lines, and has no escapes.
  public var tripleQuotedStrings: Bool
  /// Interpretation of `'`.
  public var singleQuote: SingleQuote
  /// Backtick template literals with `${ … }` interpolation that may span lines.
  public var templateLiterals: Bool
  /// `${ … }` inside double-quoted and triple-quoted strings is an interpolated expression.
  public var dollarBraceInterpolation: Bool
  /// Raw strings `r"…"`, `r#"…"#`, and `br#"…"#` without escapes.
  public var rawStrings: Bool

  public init(
    lineComments: Bool,
    blockComments: Bool,
    nestedBlockComments: Bool,
    doubleQuotedStringsSpanLines: Bool,
    tripleQuotedStrings: Bool,
    singleQuote: SingleQuote,
    templateLiterals: Bool,
    dollarBraceInterpolation: Bool,
    rawStrings: Bool
  ) {
    self.lineComments = lineComments
    self.blockComments = blockComments
    self.nestedBlockComments = nestedBlockComments
    self.doubleQuotedStringsSpanLines = doubleQuotedStringsSpanLines
    self.tripleQuotedStrings = tripleQuotedStrings
    self.singleQuote = singleQuote
    self.templateLiterals = templateLiterals
    self.dollarBraceInterpolation = dollarBraceInterpolation
    self.rawStrings = rawStrings
  }

  /// `//` and nestable `/* */` comments, single-line `"…"` strings, and multi-line `"""…"""`
  /// strings. This is the default for `LanguageRules` that do not declare their own syntax.
  public static let standard = LexicalSyntax(
    lineComments: true,
    blockComments: true,
    nestedBlockComments: true,
    doubleQuotedStringsSpanLines: false,
    tripleQuotedStrings: true,
    singleQuote: .none,
    templateLiterals: false,
    dollarBraceInterpolation: false,
    rawStrings: false
  )
}

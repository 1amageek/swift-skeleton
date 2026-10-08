/// The declaration keyword and type name parsed from a type declaration header.
public struct TypeHeader: Sendable, Equatable {
  public let keyword: String
  public let name: String

  public init(keyword: String, name: String) {
    self.keyword = keyword
    self.name = name
  }

  /// Finds the first type name match in `header` and reads the keyword from that match onward,
  /// so that text before the declaration (attributes, decorators, annotations) cannot supply the
  /// keyword.
  public static func match(
    in header: String,
    keywordPattern: String,
    namePattern: String
  ) -> TypeHeader? {
    guard let nameMatch = TextUtilities.firstRegexRanges(pattern: namePattern, in: header),
      let nameRange = nameMatch.captures.first ?? nil
    else {
      return nil
    }
    let declaration = String(header[nameMatch.match.lowerBound...])
    guard let keyword = TextUtilities.firstRegex(pattern: keywordPattern, in: declaration) else {
      return nil
    }
    let name = header[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : TypeHeader(keyword: keyword, name: name)
  }
}

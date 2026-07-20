public protocol SkeletonParser: Sendable {
  var languageName: String { get }
  var supportedExtensions: Set<String> { get }
  var supportsAccessControl: Bool { get }
  func parse(path: String, source: String) -> ParsedFile
}

extension SkeletonParser {
  public var supportsAccessControl: Bool { false }
}

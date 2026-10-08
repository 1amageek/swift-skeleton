/// A request the CLI or daemon rejects before touching the index: unknown options,
/// missing or malformed values, or unsupported filter values.
enum SkeletonCLIError: Error, CustomStringConvertible {
  case invalidArguments(String)

  var description: String {
    switch self {
    case .invalidArguments(let message):
      message
    }
  }
}

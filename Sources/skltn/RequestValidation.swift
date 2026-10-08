import SkeletonIndexCore

/// Render-option rules shared by the one-shot CLI and the JSON-RPC daemon so both
/// accept and reject the same values.
enum RequestValidation {
  static let supportedKinds: Set<String> = ["class", "struct", "enum", "protocol", "actor", "extension"]

  static func kinds(_ rawKinds: [String]) throws -> Set<String> {
    let kinds = Set(rawKinds.map { $0.lowercased() })
    let invalidKinds = kinds.subtracting(supportedKinds)
    guard invalidKinds.isEmpty else {
      throw SkeletonCLIError.invalidArguments(
        "unsupported kind: \(invalidKinds.sorted().joined(separator: ",")); expected \(supportedKinds.sorted().joined(separator: ","))"
      )
    }
    return kinds
  }

  static func accessBoundary(_ rawValue: String?) throws -> AccessBoundary? {
    guard let rawValue else {
      return nil
    }
    guard let boundary = AccessBoundary(rawValue: rawValue.lowercased()) else {
      throw SkeletonCLIError.invalidArguments(
        "unsupported access: \(rawValue); expected public,package,internal,fileprivate,private,all"
      )
    }
    return boundary
  }

  static func limit(_ rawValue: String?) throws -> Int {
    guard let rawValue else {
      return 20
    }
    guard let limit = Int(rawValue), limit >= 0 else {
      throw SkeletonCLIError.invalidArguments("invalid limit: \(rawValue); expected a non-negative integer")
    }
    return limit
  }
}

public enum AccessScope: String, Sendable, Equatable, Codable, CaseIterable {
  case exported
  case package
  case module
  case file
  case lexical
  case subclass
  case unknown

  public func isVisible(at boundary: AccessBoundary) -> Bool {
    guard let scopeRank else {
      return false
    }
    return scopeRank >= boundary.minimumRank
  }

  private var scopeRank: Int? {
    switch self {
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
      nil
    }
  }
}

public enum AccessBoundary: String, Sendable, Equatable, Codable {
  case `public`
  case package
  case `internal`
  case `fileprivate`
  case `private`
  case all

  var minimumRank: Int {
    switch self {
    case .public:
      4
    case .package:
      3
    case .internal:
      2
    case .fileprivate:
      1
    case .private, .all:
      0
    }
  }

  public var filtersDeclarations: Bool {
    self != .private && self != .all
  }
}

public struct DeclarationAccess: Sendable, Equatable, Codable {
  public let declared: AccessScope
  public let effective: AccessScope
  public let setter: AccessScope?
  public let spiGroups: [String]
  public let allowsExternalSubclassing: Bool

  public init(
    declared: AccessScope,
    effective: AccessScope,
    setter: AccessScope? = nil,
    spiGroups: [String] = [],
    allowsExternalSubclassing: Bool = false
  ) {
    self.declared = declared
    self.effective = effective
    self.setter = setter
    self.spiGroups = spiGroups
    self.allowsExternalSubclassing = allowsExternalSubclassing
  }

  public static let unknown = DeclarationAccess(declared: .unknown, effective: .unknown)
}

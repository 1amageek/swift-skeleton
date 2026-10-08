public struct SkeletonRenderOptions: Sendable, Equatable {
  public let accessBoundary: AccessBoundary?
  public let kinds: Set<String>
  public let headersOnly: Bool

  public init(
    accessBoundary: AccessBoundary? = nil,
    kinds: Set<String> = [],
    headersOnly: Bool = false
  ) {
    self.accessBoundary = accessBoundary
    // Declaration keywords are lowercase in every supported language.
    self.kinds = Set(kinds.map { $0.lowercased() })
    self.headersOnly = headersOnly
  }

  public static let `default` = SkeletonRenderOptions()
}

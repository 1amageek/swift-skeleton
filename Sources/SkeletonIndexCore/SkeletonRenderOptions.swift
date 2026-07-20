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
    self.kinds = kinds
    self.headersOnly = headersOnly
  }

  public static let `default` = SkeletonRenderOptions()
}

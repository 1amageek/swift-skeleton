import Foundation
import SkeletonSwiftPMProjectSupport
import Testing

@Test(.timeLimit(.minutes(1)))
func resolvesCurrentPackageTargets() throws {
  let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let projectRoot = testsDirectory.deletingLastPathComponent()
  let resolved = try SwiftPMProjectStructureResolver().resolve(scopeRoot: projectRoot.path)
  let structure = try #require(resolved)

  #expect(structure.packageIdentity == "swift-skeleton")
  #expect(structure.unit(named: "SkeletonIndexCore") != nil)
  #expect(structure.unit(named: "skltn") != nil)
}

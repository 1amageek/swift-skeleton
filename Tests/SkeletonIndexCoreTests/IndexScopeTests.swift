import Foundation
import SkeletonSwiftParser
import Testing

@testable import SkeletonIndexCore

// MARK: - Index scope parity between build and update

@Test("projects located below an excluded directory name are still indexed")
func excludedNamesOnlyApplyBelowTheRoot() throws {
  let container = try makeScopeDirectory()
  defer { removeScopeDirectory(container) }
  let projectRoot = container.appendingPathComponent("build/project")
  try writeScopeFile(projectRoot, "Sources/App.swift", "struct App {}")
  try writeScopeFile(projectRoot, "build/Generated.swift", "struct Generated {}")
  try writeScopeFile(projectRoot, "Sources/out/Artifact.swift", "struct Artifact {}")

  let core = makeScopeCore()
  let index = try core.build(projectRoot: projectRoot.path)

  #expect(index.files.keys.sorted() == ["Sources/App.swift"])
}

@Test("update ignores paths that a fresh build of the same scope would not index")
func updateHonorsOpenTimeScope() throws {
  let container = try makeScopeDirectory()
  defer { removeScopeDirectory(container) }
  let projectRoot = container.appendingPathComponent("project")
  try writeScopeFile(projectRoot, "Keep.swift", "struct Keep {}")

  let core = makeScopeCore()
  var index = try core.build(projectRoot: projectRoot.path, languages: ["swift"])

  try writeScopeFile(projectRoot, ".build/Hidden.swift", "struct Hidden {}")
  try writeScopeFile(projectRoot, "build/Output.swift", "struct Output {}")
  try writeScopeFile(projectRoot, "script.py", "class Script: pass")
  try writeScopeFile(container, "outside/Outside.swift", "struct Outside {}")
  try writeScopeFile(projectRoot, "Added.swift", "struct Added {}")

  let status = try core.update(
    index: &index,
    changedPaths: [
      ".build/Hidden.swift", "build/Output.swift", "script.py", "../outside/Outside.swift",
      projectRoot.appendingPathComponent("Added.swift").path,
    ],
    removedPaths: []
  )
  let fresh = try core.build(projectRoot: projectRoot.path, languages: ["swift"])

  #expect(status.filesIndexed == 2)
  #expect(index.files.keys.sorted() == ["Added.swift", "Keep.swift"])
  #expect(index.files.keys.sorted() == fresh.files.keys.sorted())
  #expect(index.files["Added.swift"]?.languageName == "swift")
}

@Test("update recomputes wiring markers instead of keeping stale ones")
func updateDropsStaleContextFindings() throws {
  let container = try makeScopeDirectory()
  defer { removeScopeDirectory(container) }
  let projectRoot = container.appendingPathComponent("project")
  try writeScopeFile(
    projectRoot, "FakeClock.swift",
    """
    struct FakeClock {
        func now() -> Int { 0 }
    }
    """)
  try writeScopeFile(
    projectRoot, "Main.swift",
    """
    func run() -> Int {
        FakeClock().now()
    }
    """)

  let core = makeScopeCore()
  var index = try core.build(projectRoot: projectRoot.path)
  #expect(scopeHeader("FakeClock", in: core.getSkeleton(index: index).text).contains("[impl:wire]"))

  try writeScopeFile(
    projectRoot, "Main.swift",
    """
    func run() -> Int {
        1 + 2
    }
    """)
  _ = try core.update(index: &index, changedPaths: ["Main.swift"], removedPaths: [])

  let updated = core.getSkeleton(index: index).text
  let fresh = core.getSkeleton(index: try core.build(projectRoot: projectRoot.path)).text
  #expect(!scopeHeader("FakeClock", in: updated).contains("[impl:wire]"))
  #expect(updated == fresh)
}

@Test("type declarations and constructor definitions are not counted as wiring")
func declarationSitesAreNotConstructionSites() {
  let resolver = DefaultImplementationContextResolver()
  let files = [
    "src/FakeClock.java": scopeParsedFile(path: "src/FakeClock.java", typeName: "FakeClock"),
    "src/InMemoryStore.py": scopeParsedFile(path: "src/InMemoryStore.py", typeName: "InMemoryStore"),
    "src/FakeRepo.kt": scopeParsedFile(path: "src/FakeRepo.kt", typeName: "FakeRepo"),
    "src/StubCache.cpp": scopeParsedFile(path: "src/StubCache.cpp", typeName: "StubCache"),
  ]
  let declarationOnly = [
    "src/FakeClock.java": """
      public class FakeClock {
          public FakeClock() throws Exception {
              this.t = 0;
          }
          public FakeClock(long t) {
              this.t = t;
          }
      }
      """,
    "src/InMemoryStore.py": """
      class InMemoryStore(object):
          def get(self, key):
              return self.data[key]
      """,
    "src/FakeRepo.kt": "class FakeRepo(val seed: Int)",
    "src/StubCache.cpp": """
      class StubCache {
      public:
          StubCache() : size(0) {}
      };
      StubCache::StubCache(int size) : size(size) {}
      """,
  ]
  let unwired = resolver.resolve(files: files, sources: declarationOnly)
  #expect(unwired.values.allSatisfy { file in
    !file.implementationAnalysis.findings.contains { $0.reason == .wire }
  })

  var constructed = declarationOnly
  constructed["src/App.java"] = "class App { Object clock = new FakeClock() { }; }"
  constructed["src/app.py"] = "store = InMemoryStore()"
  constructed["src/App.kt"] = "val repo = FakeRepo(1)"
  constructed["src/main.cpp"] = "int main() { auto cache = StubCache(); }"
  let wired = resolver.resolve(files: files, sources: constructed)
  for path in files.keys {
    #expect(
      wired[path]?.implementationAnalysis.findings.contains { $0.reason == .wire } == true,
      "expected wiring for \(path)")
  }
}

@Test("target update assigns new focus files and follows import changes")
func targetUpdateTracksUnitsAndImports() throws {
  let container = try makeScopeDirectory()
  defer { removeScopeDirectory(container) }
  let projectRoot = container.appendingPathComponent("package")
  try writeScopeFile(projectRoot, "Sources/App/App.swift", "struct App {}")
  try writeScopeFile(projectRoot, "Sources/Lib/Lib.swift", "public struct Lib {}")

  let structure = ProjectStructure(
    projectRoot: projectRoot.path,
    packageIdentity: "package",
    units: [
      ProjectUnit(
        id: "unit:App", name: "App", moduleName: "App", displayKind: "module", kind: .executable,
        sourceRoots: [projectRoot.appendingPathComponent("Sources/App").path],
        dependencies: [ProjectUnitDependency(name: "Lib", localUnitID: "unit:Lib")]),
      ProjectUnit(
        id: "unit:Lib", name: "Lib", moduleName: "Lib", displayKind: "module", kind: .regular,
        sourceRoots: [projectRoot.appendingPathComponent("Sources/Lib").path],
        dependencies: []),
    ]
  )
  let core = SkeletonIndexCore(
    parsers: [SwiftSkeletonParser()],
    projectStructureResolvers: [FixedStructureResolver(structure: structure)]
  )
  var index = try core.build(projectRoot: projectRoot.path, languages: [], targetName: "App")
  #expect(index.dependencyUnitIDs.isEmpty)

  try writeScopeFile(projectRoot, "Sources/App/Feature.swift", "import Lib\nstruct Feature {}")
  _ = try core.update(index: &index, changedPaths: ["Sources/App/Feature.swift"], removedPaths: [])

  let text = core.getSkeleton(index: index).text
  let fresh = try core.build(projectRoot: projectRoot.path, languages: [], targetName: "App")
  #expect(index.fileUnitIDs["Sources/App/Feature.swift"] == "unit:App")
  #expect(index.dependencyUnitIDs == ["unit:Lib"])
  #expect(text.contains("struct Feature"))
  #expect(text.contains("module Lib"))
  #expect(text == core.getSkeleton(index: fresh).text)
}

@Test("indexing a file with thousands of methods stays linear", .timeLimit(.minutes(1)))
func largeFileIndexingStaysLinear() throws {
  let container = try makeScopeDirectory()
  defer { removeScopeDirectory(container) }
  var source = "struct Large {\n"
  for index in 0..<4_000 {
    source += "    private func method\(index)(value: Int) -> Int {\n        return value + \(index)\n    }\n"
  }
  source += "}\n"
  try writeScopeFile(container, "Large.swift", source)

  let index = try makeScopeCore().build(projectRoot: container.path)

  #expect(index.files["Large.swift"]?.implementationAnalysis.methods.count == 4_000)
}

// MARK: - Helpers

private struct FixedStructureResolver: ProjectStructureResolving {
  let structure: ProjectStructure

  func resolve(scopeRoot: String) throws -> ProjectStructure? {
    structure
  }
}

private func makeScopeCore() -> SkeletonIndexCore {
  SkeletonIndexCore(parsers: [SwiftSkeletonParser()])
}

private func scopeParsedFile(path: String, typeName: String) -> ParsedFile {
  ParsedFile(
    path: path,
    blocks: [
      SkeletonBlock(
        kind: .type("class"),
        typeName: typeName,
        inheritance: [],
        range: SourceRange(startLine: 1, endLine: 1),
        properties: [],
        methods: [],
        hasErrorNode: false
      )
    ],
    hasParseError: false
  )
}

private func scopeHeader(_ name: String, in text: String) -> String {
  text.split(separator: "\n").map(String.init).first {
    !$0.hasPrefix(" ") && $0.contains(" \(name)")
  } ?? ""
}

private func makeScopeDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("swift-skeleton-scope-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}

private func writeScopeFile(_ root: URL, _ relativePath: String, _ content: String) throws {
  let fileURL = root.appendingPathComponent(relativePath)
  try FileManager.default.createDirectory(
    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  try content.write(to: fileURL, atomically: true, encoding: .utf8)
}

private func removeScopeDirectory(_ url: URL) {
  do {
    try FileManager.default.removeItem(at: url)
  } catch {
    // Temporary directory cleanup does not affect the asserted behavior.
  }
}

import Foundation
import SkeletonSwiftParser
import Testing

@testable import SkeletonIndexCore

@Test("Swift enum case ranges end on their own line")
func swiftEnumCaseRangesEndOnTheirLine() {
  let source = """
    public enum Event {
      case started
      case finished(Int)

      public typealias Code = Int


      public func describe() {}
    }
    """
  let parsed = SwiftSkeletonParser().parse(path: "Event.swift", source: source)
  let declarations = parsed.blocks.first?.declarations ?? []

  #expect(declarations.map(\.range) == [
    SourceRange(startLine: 2, endLine: 2),
    SourceRange(startLine: 3, endLine: 3),
    SourceRange(startLine: 5, endLine: 5),
  ])
}

@Test("block markers summarize only members visible in the view")
func blockMarkersFollowAccessFilter() {
  let source = """
    public struct Service {
      public func run() -> Int { 1 }
      func pending() {}
    }
    """
  let parser = SwiftSkeletonParser()
  let parsed = parser.parse(path: "Service.swift", source: source)
  let analysis = DefaultImplementationAnalyzer().analyze(
    path: "Service.swift",
    blocks: parsed.blocks,
    source: source,
    language: parser.languageName,
    syntaxEvidence: parsed.methodSyntaxEvidence
  )
  let index = ProjectIndex(
    projectRoot: "/project",
    files: ["Service.swift": parsed.replacing(implementationAnalysis: analysis)],
    lastUpdateTS: "",
    isWatching: false
  )
  let formatter = SkeletonFormatter()

  let all = formatter.render(index: index, options: .default).text
  let publicOnly = formatter.render(
    index: index,
    options: SkeletonRenderOptions(accessBoundary: .public, kinds: [], headersOnly: false)
  ).text
  let publicHeaders = formatter.render(
    index: index,
    options: SkeletonRenderOptions(accessBoundary: .public, kinds: [], headersOnly: true)
  ).text

  #expect(all.contains("struct Service [Service.swift:1-4] [impl:body]"))
  #expect(publicOnly.contains("struct Service [Service.swift:1-4]\n"))
  #expect(!publicOnly.contains("[impl"))
  #expect(publicHeaders == "struct Service [Service.swift:1-4]")
}

@Test("method findings stay attached to methods declared outside the type range")
func methodFindingsUseMethodIdentity() {
  let runRange = SourceRange(startLine: 3, endLine: 3)
  let block = SkeletonBlock(
    kind: .type("struct"),
    typeName: "Service",
    inheritance: [],
    range: SourceRange(startLine: 1, endLine: 1),
    properties: [],
    methods: [
      MethodSignature(
        name: "Run", parameterTypeRefs: ["int"], returnTypeRef: "int", range: runRange,
        isInitializer: false)
    ],
    hasErrorNode: false
  )
  let finding = ImplementationFinding(
    scope: .method, typeName: "Service", methodName: "Run", range: runRange,
    certainty: .definite, domain: .body, reason: .trap)
  let file = ParsedFile(
    path: "service.go",
    blocks: [block],
    hasParseError: false,
    implementationAnalysis: FileImplementationAnalysis(language: "go", methods: [], findings: [finding])
  )
  let index = ProjectIndex(
    projectRoot: "/project", files: ["service.go": file], lastUpdateTS: "", isWatching: false)

  let text = SkeletonFormatter().render(index: index, options: .default).text

  #expect(text == """
    struct Service [service.go:1-1] [impl:body]
      methods:
        Run(int) -> int [3-3] [impl!:trap]
    """)
}

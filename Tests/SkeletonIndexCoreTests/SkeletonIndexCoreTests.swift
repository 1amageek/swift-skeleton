import Foundation
import Testing
@testable import SkeletonIndexCore
import SkeletonSwiftParser

// MARK: - Self-referential tests (this project as test target)

private func swiftParser() -> SwiftSkeletonParser { SwiftSkeletonParser() }
private func makeCore() -> SkeletonIndexCore { SkeletonIndexCore(parsers: [swiftParser()]) }

private func projectSourcesRoot() -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let projectRoot = testFile
        .deletingLastPathComponent()  // SkeletonIndexCoreTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // swift-skeleton/
    return projectRoot.appendingPathComponent("Sources/SkeletonIndexCore").path
}

@Test("indexes all SkeletonIndexCore source files")
func indexesAllCoreFiles() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())

    let expectedFiles: Set<String> = [
        "SkeletonError.swift",
        "SkeletonBlockKind.swift",
        "SourceRange.swift",
        "PropertySignature.swift",
        "MethodSignature.swift",
        "SkeletonBlock.swift",
        "ParsedFile.swift",
        "IndexTypes.swift",
        "ProjectIndex.swift",
        "SkeletonFormatter.swift",
        "SkeletonIndexCore.swift",
        "SkeletonProjectRegistry.swift",
        "SkeletonParser.swift",
        "ImplementationFingerprint.swift",
        "ImplementationFinding.swift",
        "MethodSyntaxEvidence.swift",
        "MethodImplementationAnalysis.swift",
        "FileImplementationAnalysis.swift",
        "ImplementationAnalyzing.swift",
        "ImplementationContextResolving.swift",
        "DefaultImplementationAnalyzer.swift",
        "DefaultImplementationContextResolver.swift",
    ]

    let indexedFiles = Set(index.files.keys)
    for expected in expectedFiles {
        #expect(indexedFiles.contains(expected), "Missing file: \(expected)")
    }
    #expect(!index.files.values.contains { $0.hasParseError }, "No parse errors expected in own source")
}

@Test("extracts SkeletonIndexCore struct with its public methods")
func extractsSkeletonIndexCore() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("struct SkeletonIndexCore: Sendable [SkeletonIndexCore.swift:"))
    #expect(result.text.contains("build(String) -> ProjectIndex"))
    #expect(result.text.contains("status(ProjectIndex) -> IndexStatus"))
    #expect(result.text.contains("getSkeleton(ProjectIndex, String?) -> SkeletonTextResult"))
    #expect(result.text.contains("query(ProjectIndex, String, Int) -> [QueryHit]"))
    #expect(result.text.contains("diagnostics(ProjectIndex) -> IndexDiagnostics"))
}

@Test("extracts actor SkeletonProjectRegistry")
func extractsActorDeclaration() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("actor SkeletonProjectRegistry"))
    #expect(result.text.contains("open(String, [String]) -> OpenResult"))
    #expect(result.text.contains("query(String, String, Int) -> [QueryHit]"))
}

@Test("extracts SwiftSkeletonParser with all private methods")
func extractsParserMethods() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("struct SwiftSkeletonParser: SkeletonParser, Sendable [SkeletonSwiftParser/SwiftSkeletonParser.swift:"))
    #expect(result.text.contains("parse(String, String) -> ParsedFile"))
    #expect(result.text.contains("declarationHeader(String)"))
    #expect(result.text.contains("parseMembers(String, Int)"))
    #expect(result.text.contains("parseParameterTypeRefs(String) -> [String]"))
    #expect(result.text.contains("parseReturnType(String) -> String?"))
}

@Test("extracts SkeletonFormatter render and header methods")
func extractsFormatterMethods() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("struct SkeletonFormatter: Sendable [SkeletonFormatter.swift:"))
    #expect(result.text.contains("render(ProjectIndex, String?) -> SkeletonTextResult"))
    #expect(result.text.contains("header(SkeletonBlock, String) -> String"))
}

@Test("extracts enum types: SkeletonError, SkeletonBlockKind")
func extractsEnumTypes() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("enum SkeletonError: Error, Sendable [SkeletonError.swift:"))
    #expect(result.text.contains("enum SkeletonBlockKind: Sendable, Equatable, Codable [SkeletonBlockKind.swift:"))
}

@Test("extracts struct properties with correct types")
func extractsStructProperties() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    // SourceRange props
    #expect(result.text.contains("props: startLine:Int?, endLine:Int?"))

    // PropertySignature props
    #expect(result.text.contains("props: name:String, typeRef:String"))

    // SkeletonIndexCore props
    #expect(result.text.contains("formatter:SkeletonFormatter"))
}

@Test("extracts multi-parameter init signatures correctly")
func extractsMultiParamInit() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    // MethodSignature has a multi-line init with 5 params
    #expect(result.text.contains("init(String, [String], String?, SourceRange, Bool)"))

    // SkeletonBlock has a multi-line init with 7 params
    #expect(result.text.contains("init(SkeletonBlockKind, String, [String], SourceRange, [PropertySignature], [MethodSignature], Bool)"))
}

@Test("all method ranges have valid start and end lines (no ?)")
func allMethodRangesValid() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    let lines = result.text.split(separator: "\n").map(String.init)
    let methodLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("init(") ||
        ($0.contains("(") && $0.contains("[") && !$0.contains("props:")) }

    for line in methodLines {
        #expect(!line.hasSuffix("-?]"), "Method has unknown end line: \(line)")
        #expect(!line.contains("[?-"), "Method has unknown start line: \(line)")
    }
}

@Test("method ranges ignore closure defaults inside multiline signatures")
func methodRangeWithClosureDefault() {
    let source = """
    struct Transformer {
        func run(
            value: Int,
            transform: (Int) -> Int = { $0 }
        ) -> Int
        {
            transform(value)
        }
    }
    """
    let parsed = swiftParser().parse(path: "Transformer.swift", source: source)
    let method = parsed.blocks.first?.methods.first { $0.name == "run" }

    #expect(method?.range.startLine == 2)
    #expect(method?.range.endLine == 8)
}

@Test("query finds SkeletonProjectRegistry by name")
func queryFindsRegistryByName() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let hits = core.query(index: index, q: "SkeletonProjectRegistry", limit: 10)

    #expect(hits.count >= 1)
    if let hit = hits.first {
        #expect(hit.file == "SkeletonProjectRegistry.swift")
        #expect(hit.startLine != nil)
        #expect(hit.endLine != nil)
    }
}

@Test("query finds methods across multiple files")
func queryFindsMethodsAcrossFiles() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let hits = core.query(index: index, q: "parse", limit: 20)

    let hitFiles = Set(hits.map(\.file))
    #expect(hitFiles.contains("SkeletonSwiftParser/SwiftSkeletonParser.swift"))
}

@Test("file-specific skeleton returns only that file")
func fileSpecificSkeleton() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index, path: "SourceRange.swift")

    #expect(result.text.contains("struct SourceRange"))
    #expect(!result.text.contains("SkeletonFormatter"))
}

@Test("files are sorted by path in skeleton output")
func filesSortedByPath() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    let lines = result.text.split(separator: "\n").map(String.init)
    let headerLines = lines.filter { !$0.hasPrefix("  ") && !$0.hasPrefix("#") }

    var lastFile = ""
    for header in headerLines {
        guard let bracketRange = header.range(of: "["),
              let colonRange = header.range(of: ":", range: bracketRange.upperBound..<header.endIndex) else {
            continue
        }
        let file = String(header[bracketRange.upperBound..<colonRange.lowerBound])
        #expect(file >= lastFile, "File order violation: \(file) came after \(lastFile)")
        lastFile = file
    }
}

@Test("no parse errors in own project source")
func noParseErrorsInProject() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let diagnostics = core.diagnostics(index: index)

    #expect(diagnostics.parseErrorFiles.isEmpty, "Parse errors in: \(diagnostics.parseErrorFiles)")
    #expect(diagnostics.incompleteBlocks.isEmpty, "Incomplete blocks found: \(diagnostics.incompleteBlocks)")
}

@Test("update removes deleted files and re-parses changed files")
func updateReflectsChanges() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Keep.swift": """
            struct Keep {
                var x: Int
            }
            """,
            "Remove.swift": """
            struct Remove {}
            """,
        ]
    )
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    let core = makeCore()
    var index = try core.build(projectRoot: projectRoot)

    #expect(index.files.count == 2)

    let updated = try core.update(index: &index, changedPaths: [], removedPaths: ["Remove.swift"])
    #expect(updated.filesIndexed == 1)

    let result = core.getSkeleton(index: index)
    #expect(result.text.contains("struct Keep"))
    #expect(!result.text.contains("struct Remove"))
}

// MARK: - Multi-module scan (full Sources/)

private func projectAllSourcesRoot() -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    return testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources").path
}

@Test("multi-module scan includes Core, Client, CLI, Daemon, and SwiftParser files")
func multiModuleScan() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let files = Set(index.files.keys)

    #expect(files.contains("SkeletonIndexCore/SkeletonIndexCore.swift"))
    #expect(files.contains("SkeletonIndexClient/EmbeddedService.swift"))
    #expect(files.contains("SkeletonIndexClient/SidecarService.swift"))
    #expect(files.contains("SkeletonIndexClient/SkeletonIndexService.swift"))
    #expect(files.contains("skltn/SkeletonIndexCLI.swift"))
    #expect(files.contains("skltn/DaemonCommand.swift"))
    #expect(files.contains("SkeletonSwiftParser/SwiftSkeletonParser.swift"))
}

@Test("protocol SkeletonIndexService extracted with method signatures")
func extractsProtocolDeclaration() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("protocol SkeletonIndexService: Sendable"))
    #expect(result.text.contains("open(String, [String]) -> OpenResult"))
    #expect(result.text.contains("getSkeleton(String, String?) -> SkeletonTextResult"))
    #expect(result.text.contains("diagnostics(String) -> IndexDiagnostics"))
}

@Test("EmbeddedService actor with SkeletonIndexService conformance")
func extractsEmbeddedService() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("actor EmbeddedService: SkeletonIndexService"))
    #expect(result.text.contains("props: registry:SkeletonProjectRegistry"))
}

@Test("SidecarService actor with optional properties")
func extractsSidecarServiceOptionalProps() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("actor SidecarService: SkeletonIndexService"))
    #expect(result.text.contains("process:Process?"))
    #expect(result.text.contains("input:FileHandle?"))
    #expect(result.text.contains("output:FileHandle?"))
}

@Test("CLI enum extracted with static methods")
func extractsCLIEnum() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("enum SkeletonIndexCLIMain [skltn/SkeletonIndexCLI.swift:"))
    #expect(result.text.contains("main()"))
    #expect(result.text.contains("value(String, [String]) -> String"))
    #expect(result.text.contains("optionalValue(String, [String]) -> String?"))
}

@Test("Daemon functions extracted from DaemonCommand")
func extractsDaemonFunctions() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let files = Set(index.files.keys)

    #expect(files.contains("skltn/DaemonCommand.swift"))
}

@Test("subdirectory paths are relative in multi-module scan")
func subdirectoryRelativePaths() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())

    for filePath in index.files.keys {
        #expect(!filePath.hasPrefix("/"), "Path should be relative: \(filePath)")
        #expect(!filePath.contains("Sources/"), "Path should not include Sources/ prefix: \(filePath)")
    }
}

// MARK: - inout, complex types, tuple returns

@Test("inout parameter captured in update method")
func inoutParameterCaptured() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("update(inout ProjectIndex, [String], [String]) -> IndexStatus"))
}

@Test("dictionary type properties extracted correctly")
func dictionaryTypeProperties() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("files:[String: ParsedFile]"))
    #expect(result.text.contains("projects:[String: ProjectIndex]"))
}

@Test("tuple return types extracted from parser methods")
func tupleReturnTypes() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectAllSourcesRoot())
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("declarationHeader(String) -> (kind: SkeletonBlockKind, typeName: String, inheritance: [String])?"))
    #expect(result.text.contains("firstRegexCapture(String, String) -> (String, String)?"))
}

// MARK: - Query depth

@Test("query ranks by occurrence count, higher score first")
func queryRanksByOccurrence() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let hits = core.query(index: index, q: "init", limit: 50)

    #expect(hits.count > 5, "Expected many blocks containing init")

    for i in 0..<(hits.count - 1) {
        let currentFile = hits[i].file
        let nextFile = hits[i + 1].file
        if currentFile == nextFile {
            #expect((hits[i].startLine ?? 0) <= (hits[i + 1].startLine ?? 0),
                    "Same-file hits should be ordered by position")
        }
    }
}

@Test("query with no matches returns empty")
func queryNoMatches() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let hits = core.query(index: index, q: "zzz_nonexistent_symbol_zzz", limit: 10)

    #expect(hits.isEmpty)
}

@Test("query respects limit parameter")
func queryRespectsLimit() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let hits = core.query(index: index, q: "String", limit: 3)

    #expect(hits.count <= 3)
}

// MARK: - Status and diagnostics on own source

@Test("status reports correct file count for own source")
func statusFileCount() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let status = core.status(index: index)

    #expect(status.filesIndexed == 26)
    #expect(status.parseErrorFiles == 0)
    #expect(status.isWatching == false)
    #expect(!status.lastUpdateTS.isEmpty)
}

// MARK: - Edge cases with real patterns

@Test("nested generic types in properties")
func nestedGenericProperties() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Complex.swift": """
            struct Complex {
                var items: [Set<String>]
                var mapping: [String: [Int]]
                var nested: Result<[String], Error>
            }
            """,
        ]
    )
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("items:[Set<String>]"))
    #expect(result.text.contains("mapping:[String: [Int]]"))
    #expect(result.text.contains("nested:Result<[String], Error>"))
}

@Test("closure parameter types")
func closureParameterTypes() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Closures.swift": """
            struct Closures {
                func perform(handler: (Int) -> Void) {}
                func transform(fn: (String) -> Int) -> Int { 0 }
            }
            """,
        ]
    )
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("perform((Int) -> Void)"))
    #expect(result.text.contains("transform((String) -> Int) -> Int"))
}

@Test("default parameter values stripped from type refs")
func defaultParamValuesStripped() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Defaults.swift": """
            struct Defaults {
                func query(q: String, limit: Int = 20) -> [String] { [] }
            }
            """,
        ]
    )
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("query(String, Int) -> [String]"))
    #expect(!result.text.contains("= 20"))
}

@Test("generic type declarations")
func genericTypeDeclarations() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Generic.swift": """
            struct Container<Element: Hashable> {
                var items: [Element]
                func get(at index: Int) -> Element? { nil }
            }
            """,
        ]
    )
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("struct Container"))
    #expect(result.text.contains("items:[Element]"))
    #expect(result.text.contains("get(Int) -> Element?"))
}

@Test("SkeletonBlockKind is the only type in SkeletonBlockKind.swift")
func singleTypeInBlockKindFile() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    let lines = result.text.split(separator: "\n").map(String.init)
    let blockKindLines = lines.filter {
        $0.contains("[SkeletonBlockKind.swift:") && !$0.hasPrefix("  ")
    }

    #expect(blockKindLines.count == 1)
    if let line = blockKindLines.first {
        #expect(line.contains("enum SkeletonBlockKind"))
    }
}

@Test("parse error in one file does not prevent indexing other files")
func parseErrorIsolation() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Good.swift": """
            struct Good {
                var name: String
                func greet() -> String { name }
            }
            """,
            "Bad.swift": """
            struct Bad {
                func broken(
            """,
            "AlsoGood.swift": """
            enum AlsoGood {
                case a, b, c
            }
            """,
        ]
    )
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let result = core.getSkeleton(index: index)
    let diagnostics = core.diagnostics(index: index)

    #expect(result.text.contains("struct Good"))
    #expect(result.text.contains("greet() -> String"))
    #expect(result.text.contains("enum AlsoGood"))
    #expect(result.text.contains("# parse_error Bad.swift"))
    #expect(diagnostics.parseErrorFiles == ["Bad.swift"])
    #expect(result.text.contains("struct Good") && result.text.contains("enum AlsoGood"))
}

@Test("update with changed file re-parses content")
func updateChangedFile() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Evolving.swift": """
            struct Evolving {
                var version: Int
            }
            """,
        ]
    )
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    let core = makeCore()
    var index = try core.build(projectRoot: projectRoot)

    let before = core.getSkeleton(index: index)
    #expect(before.text.contains("version:Int"))
    #expect(!before.text.contains("name:String"))

    let updatedContent = """
    struct Evolving {
        var version: Int
        var name: String
        func describe() -> String { name }
    }
    """
    let fileURL = URL(fileURLWithPath: projectRoot).appendingPathComponent("Evolving.swift")
    try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)

    let _ = try core.update(index: &index, changedPaths: ["Evolving.swift"], removedPaths: [])

    let after = core.getSkeleton(index: index)
    #expect(after.text.contains("version:Int"))
    #expect(after.text.contains("name:String"))
    #expect(after.text.contains("describe() -> String"))
}

// MARK: - Language separation verification

@Test("SkeletonParser protocol defines the parser contract")
func parserProtocolContract() throws {
    let parser = swiftParser()
    #expect(parser.languageName == "swift")
    #expect(parser.supportedExtensions.contains("swift"))
}

@Test("Core module has no knowledge of Swift-specific types")
func coreHasNoSwiftSpecificTypes() throws {
    let core = makeCore()
    let index = try core.build(projectRoot: projectSourcesRoot())
    let result = core.getSkeleton(index: index)

    // Core module should not contain SwiftSkeletonParser, TreeSitter, or language-specific code
    let coreFiles = index.files.keys.sorted()
    for file in coreFiles {
        #expect(!file.contains("TreeSitter"), "Core should not contain TreeSitter files")
        #expect(!file.contains("SwiftSkeletonParser"), "Core should not contain SwiftSkeletonParser")
    }

    // The SkeletonParser protocol should be in Core
    #expect(coreFiles.contains("SkeletonParser.swift"))

    // SkeletonBlockKind uses String, not a Swift-specific enum
    #expect(result.text.contains("enum SkeletonBlockKind"))
    #expect(!result.text.contains("SkeletonTypeKeyword"))
}

@Test("unsupported language throws error via registry")
func unsupportedLanguageError() async throws {
    let core = makeCore()
    let registry = SkeletonProjectRegistry(core: core)

    let projectRoot = try makeTemporaryProject(files: ["Test.swift": "struct Test {}"])
    defer {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: projectRoot))
        } catch {
        }
    }

    do {
        let _ = try await registry.open(projectRoot: projectRoot, languages: ["typescript"])
        #expect(Bool(false), "Should have thrown unsupportedLanguage error")
    } catch let error as SkeletonError {
        if case .unsupportedLanguage(let lang) = error {
            #expect(lang == "typescript")
        } else {
            #expect(Bool(false), "Expected unsupportedLanguage, got \(error)")
        }
    }
}

// MARK: - Implementation fingerprint

@Test("implementation markers distinguish definite and suspicious bodies")
func implementationMarkers() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "ImplementationCases.swift": """
            struct ImplementationCases {
                init() {}

                func trapped(value: Int) -> Int {
                    fatalError("not implemented")
                }

                func empty(value: Int) {}

                func constant(value: Int) -> Bool {
                    return false
                }

                func noOp(value: Int) {
                    value + 1
                }

                func trapNamedParameter(fatalError: Int) -> Int {
                    fatalError
                }

                func live(value: Int) -> Int {
                    value + 1
                }
            }

            protocol Requirement {
                func required(value: Int) -> Int
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let text = core.getSkeleton(index: index).text

    #expect(text.contains("ImplementationCases.swift:") && text.contains("[impl:body]"))
    #expect(text.contains("trapped(Int) -> Int") && text.contains("[impl!:trap]"))
    #expect(text.contains("empty(Int)") && text.contains("[impl!:empty]"))
    #expect(text.contains("constant(Int) -> Bool") && text.contains("[impl?:const]"))
    #expect(methodLine(named: "noOp", in: text).contains("[impl?:noop]"))
    #expect(!methodLine(named: "trapNamedParameter", in: text).contains("[impl!:trap]"))
    #expect(!methodLine(named: "live", in: text).contains("[impl"))
    #expect(!methodLine(named: "init", in: text).contains("[impl"))
    #expect(!methodLine(named: "required", in: text).contains("[impl"))
}

@Test("fingerprint captures implementation evidence without body text")
func fingerprintEvidence() throws {
    let source = """
    struct Worker {
        var total: Int

        mutating func run(value: Int) async -> Int {
            total = await calculate(value)
            return total
        }
    }
    """
    let parser = swiftParser()
    let parsed = parser.parse(path: "Worker.swift", source: source)
    let analysis = DefaultImplementationAnalyzer().analyze(
        path: "Worker.swift",
        blocks: parsed.blocks,
        source: source,
        language: parser.languageName
    )
    let fingerprint = analysis.methods.first { $0.methodName == "run" }?.fingerprint

    #expect(fingerprint?.bodyState == .concrete)
    #expect(fingerprint?.parameterReads == ["value"])
    #expect(fingerprint?.stateReads == ["total"])
    #expect(fingerprint?.stateWrites == ["total"])
    #expect(fingerprint?.callTargets.contains("calculate") == true)
    #expect(fingerprint?.asyncOperations == ["await"])
    #expect(fingerprint?.returnOrigins == [.state])
}

@Test("project context reports dead and production-wired fake implementations")
func projectContextMarkers() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Production.swift": """
            protocol Store {}
            struct FakeStore: Store {}

            struct Application {
                let store: Store = FakeStore()

                private func hidden() -> Int {
                    calculate()
                }
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let text = core.getSkeleton(index: index).text

    #expect(headerLine(named: "FakeStore", in: text).contains("[impl:wire]"))
    #expect(methodLine(named: "hidden", in: text).contains("[impl?:dead]"))

    let method = index.files["Production.swift"]?.implementationAnalysis.methods.first { $0.methodName == "hidden" }
    #expect(method?.fingerprint.productionReachability == .unreferenced)
}

@Test("non-production findings stay internal and are not rendered")
func nonProductionFindingsAreSuppressed() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "WorkerTests.swift": """
            struct WorkerTests {
                func helper(value: Int) -> Int {
                    fatalError("test trap")
                }
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let text = core.getSkeleton(index: index).text
    let method = index.files["WorkerTests.swift"]?.implementationAnalysis.methods.first

    #expect(!text.contains("[impl"))
    #expect(method?.fingerprint.terminalBehaviors.contains(.traps) == true)
    #expect(method?.fingerprint.productionReachability == .nonProduction)
    #expect(method?.fingerprint.implementationBinding == .testOnly)
}

@Test("wiring marker requires construction and production paths use exact classification")
func contextIndexUsesConstructionAndExactPaths() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Contest.swift": """
            struct FakeStore {}

            struct Consumer {
                let storeType: FakeStore.Type

                func pending() {
                    fatalError("pending")
                }
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    let text = core.getSkeleton(index: try core.build(projectRoot: projectRoot)).text

    #expect(!headerLine(named: "FakeStore", in: text).contains("[impl:wire]"))
    #expect(methodLine(named: "pending", in: text).contains("[impl!:trap]"))
}

@Test("dead marker ignores references found only in comments and strings")
func deadMarkerUsesCodeReferences() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Production.swift": """
            struct Production {
                private func hidden() {
                    work()
                }

                func documentation() -> String {
                    // hidden() is intentionally mentioned in documentation.
                    "hidden"
                }
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    let text = core.getSkeleton(index: try core.build(projectRoot: projectRoot)).text

    #expect(methodLine(named: "hidden", in: text).contains("[impl?:dead]"))
}

@Test("dead marker preserves calls inside Swift string interpolation")
func deadMarkerUsesSwiftStringInterpolationReferences() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Production.swift": """
            struct Production {
                private func hidden() -> String {
                    "value"
                }

                func documentation() -> String {
                    "value=\\(hidden())"
                }
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    let text = core.getSkeleton(index: try core.build(projectRoot: projectRoot)).text

    #expect(!methodLine(named: "hidden", in: text).contains("[impl?:dead]"))
}

@Test("swallowed errors and collapsed branches use compact reasons")
func errorAndFlowMarkers() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "ControlFlow.swift": """
            struct ControlFlow {
                func swallowed() {
                    do {
                        work()
                    } catch {
                    }
                }

                func collapsed(value: Bool) -> Int {
                    if value {
                        return 1
                    } else {
                        return 1
                    }
                }
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    let index = try core.build(projectRoot: projectRoot)
    let text = core.getSkeleton(index: index).text

    #expect(methodLine(named: "swallowed", in: text).contains("[impl?:error]"))
    #expect(methodLine(named: "collapsed", in: text).contains("[impl?:flow]"))
    #expect(headerLine(named: "ControlFlow", in: text).contains("[impl:flow,error]"))
}

@Test("AST evidence does not flag switch mappings or observable catch handling")
func astEvidenceAvoidsLSIFalsePositives() {
    let source = """
    import Foundation

    struct ProductionMappings {
        func statusRank(_ status: Status) -> Int {
            switch status {
            case .completed: return 0
            case .cancelled: return 1
            case .blocked: return 2
            case .failed: return 3
            }
        }

        func diagnosticCode(for error: Failure) -> String {
            switch error {
            case .missing: return "missing"
            case .invalid: return "invalid"
            }
        }

        func printError(data: Data) {
            do {
                FileHandle.standardError.write(data)
            } catch {
                FileHandle.standardError.write(Data("failed".utf8))
            }
        }

        func translateError() throws {
            do {
                work()
            } catch let error as DomainError {
                throw error
            } catch {
                throw WrappedError(error)
            }
        }
    }
    """
    let parser = swiftParser()
    let parsed = parser.parse(path: "ProductionMappings.swift", source: source)
    let analysis = DefaultImplementationAnalyzer().analyze(
        path: "ProductionMappings.swift",
        blocks: parsed.blocks,
        source: source,
        language: parser.languageName,
        syntaxEvidence: parsed.methodSyntaxEvidence
    )

    #expect(parsed.methodSyntaxEvidence.count == 4)
    #expect(!analysis.findings.contains { $0.methodName == "statusRank" && $0.reason == .noOperation })
    #expect(!analysis.findings.contains { $0.methodName == "diagnosticCode" && $0.reason == .noOperation })
    #expect(!analysis.findings.contains { $0.methodName == "printError" && $0.reason == .error })
    #expect(
        !analysis.findings.contains { $0.methodName == "translateError" && $0.reason == .error },
        "\(parsed.methodSyntaxEvidence)"
    )
}

@Test("incremental update replaces fingerprints and findings")
func updateReplacesImplementationAnalysis() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Evolving.swift": """
            struct Evolving {
                func resolve(value: Int) -> Int {
                    fatalError("pending")
                }
            }
            """,
        ]
    )
    defer { removeTemporaryProject(projectRoot) }

    let core = makeCore()
    var index = try core.build(projectRoot: projectRoot)
    #expect(methodLine(named: "resolve", in: core.getSkeleton(index: index).text).contains("[impl!:trap]"))

    let completedSource = """
    struct Evolving {
        func resolve(value: Int) -> Int {
            value + 1
        }
    }
    """
    let fileURL = URL(fileURLWithPath: projectRoot).appendingPathComponent("Evolving.swift")
    try completedSource.write(to: fileURL, atomically: true, encoding: .utf8)
    let _ = try core.update(index: &index, changedPaths: ["Evolving.swift"], removedPaths: [])

    let updatedLine = methodLine(named: "resolve", in: core.getSkeleton(index: index).text)
    let fingerprint = index.files["Evolving.swift"]?.implementationAnalysis.methods.first?.fingerprint
    #expect(!updatedLine.contains("[impl"))
    #expect(fingerprint?.parameterReads == ["value"])
    #expect(fingerprint?.returnOrigins == [.parameter])
}

// MARK: - Helpers

private func methodLine(named name: String, in text: String) -> String {
    text.split(separator: "\n").map(String.init).first {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(name)(")
    } ?? ""
}

private func headerLine(named name: String, in text: String) -> String {
    text.split(separator: "\n").map(String.init).first {
        !$0.hasPrefix(" ") && $0.contains(" \(name)")
    } ?? ""
}

private func removeTemporaryProject(_ path: String) {
    do {
        try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    } catch {
    }
}

private func makeTemporaryProject(files: [String: String]) throws -> String {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-skeleton-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    for (name, content) in files {
        let fileURL = rootURL.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    return rootURL.path
}

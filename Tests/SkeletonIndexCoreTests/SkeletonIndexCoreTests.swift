import Foundation
import Testing
@testable import SkeletonIndexCore

@Test("files are sorted, declaration order is preserved, and untyped properties are omitted")
func skeletonOutputOrderingAndPropsContract() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Zeta.swift": """
            struct Zeta {
                var typed: String
                var untyped = 0
                func foo(_ x: Int, y: Int) -> String {
                    return ""
                }
            }
            """,
            "Alpha.swift": """
            class Alpha: P {
                let id: Int
                init(value: Int) {
                    self.id = value
                }
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

    let core = SkeletonIndexCore()
    let index = try core.build(projectRoot: projectRoot)
    let result = core.getSkeleton(index: index)

    let alphaHeader = "class Alpha: P [Alpha.swift:1-6]"
    let zetaHeader = "struct Zeta [Zeta.swift:1-7]"

    #expect(result.text.contains(alphaHeader))
    #expect(result.text.contains("  props: id:Int"))
    #expect(result.text.contains(zetaHeader))
    #expect(result.text.contains("  props: typed:String"))
    #expect(!result.text.contains("untyped"))

    if let alphaRange = result.text.range(of: alphaHeader), let zetaRange = result.text.range(of: zetaHeader) {
        #expect(alphaRange.lowerBound < zetaRange.lowerBound)
    }
}

@Test("methods include unknown parameter types as ? and keep known ranges")
func unknownParameterTypeContract() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Unknown.swift": """
            struct Unknown {
                func mixed(_ value, count: Int, options: [String: Int] = [:]) {
                }
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

    let core = SkeletonIndexCore()
    let index = try core.build(projectRoot: projectRoot)
    let result = core.getSkeleton(index: index)

    #expect(result.text.contains("mixed(?, Int, [String: Int]) [2-3]"))
}

@Test("diagnostics include parse_error and incomplete block markers")
func diagnosticsForParseError() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Broken.swift": """
            class Broken {
                func x() {
                    let value =
                }
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

    let core = SkeletonIndexCore()
    let index = try core.build(projectRoot: projectRoot)
    let text = core.getSkeleton(index: index)
    let diagnostics = core.diagnostics(index: index)

    #expect(text.text.contains("# parse_error Broken.swift"))
    #expect(text.text.contains("class Broken [Broken.swift:1-5] (!)") || text.text.contains("class Broken [Broken.swift:1-6] (!)"))
    #expect(diagnostics.parseErrorFiles == ["Broken.swift"])
    #expect(diagnostics.incompleteBlocks.count >= 1)
    #expect(diagnostics.incompleteBlocks.first?.file == "Broken.swift")
    #expect(diagnostics.incompleteBlocks.first?.startLine == 1)
}

@Test("query returns file and range hits")
func queryContract() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Sample.swift": """
            struct QueryBox {
                func hitMe(value: Int) -> Int {
                    value
                }
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

    let core = SkeletonIndexCore()
    let index = try core.build(projectRoot: projectRoot)
    let hits = core.query(index: index, q: "hitMe", limit: 20)

    #expect(hits.count >= 1)
    if let first = hits.first {
        #expect(first.file == "Sample.swift")
        #expect(first.startLine == 1)
        #expect(first.endLine == 5)
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

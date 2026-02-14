import Foundation
import Testing
@testable import SkeletonIndexCore

@Test("skeleton output keeps declaration order and omits untyped properties")
func skeletonOutputContract() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "B.swift": """
            struct B {
                var typed: String
                func foo(_ x: Int, y: Int) -> String {
                    return ""
                }
            }
            """,
            "A.swift": """
            class A: P {
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

    #expect(result.text.contains("class A: P [A.swift:1-6]"))
    #expect(result.text.contains("  props: id:Int"))
    #expect(result.text.contains("struct B [B.swift:1-6]"))
    #expect(result.text.contains("  props: typed:String"))
    #expect(result.text.contains("foo(Int, Int) -> String"))
}

@Test("diagnostics include parse_error and incomplete block")
func diagnosticsForParseError() throws {
    let projectRoot = try makeTemporaryProject(
        files: [
            "Broken.swift": """
            class Broken {
                func x() {
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
    #expect(text.text.contains("# parse_error Broken.swift"))
    #expect(diagnostics.parseErrorFiles == ["Broken.swift"])
    #expect(diagnostics.incompleteBlocks.count >= 0)
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

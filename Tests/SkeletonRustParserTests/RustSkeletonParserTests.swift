import Testing
import Foundation
import SkeletonRustParser
import SkeletonIndexCore

@Suite struct RustSkeletonParserTests {
    let parser = RustSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesRustFile() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsTrait() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let drawable = result.blocks.first { $0.typeName == "Drawable" }
        #expect(drawable != nil)
        #expect(drawable?.kind == .type("trait"))
    }

    @Test func extractsStruct() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let circle = result.blocks.first { $0.typeName == "Circle" && $0.kind == .type("struct") }
        #expect(circle != nil)
        #expect(circle?.properties.contains { $0.name == "radius" } == true)
    }

    @Test func extractsImpl() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let impls = result.blocks.filter { $0.kind == .extension }
        #expect(!impls.isEmpty)
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" && $0.kind == .type("enum") }
        #expect(shape != nil)
    }

    @Test func implTraitForType() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let implBlocks = result.blocks.filter { $0.kind == .extension }
        let traitImpl = implBlocks.first { block in
            block.methods.contains { $0.name == "draw" }
        }
        #expect(traitImpl != nil)
        #expect(traitImpl?.typeName == "Circle")
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "rust")
        #expect(parser.supportedExtensions.contains("rs"))
    }
}

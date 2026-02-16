import Testing
import Foundation
import SkeletonZigParser
import SkeletonIndexCore

@Suite struct ZigSkeletonParserTests {
    let parser = ZigSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesZigFile() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsStruct() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal != nil)
        #expect(animal?.kind == .type("struct"))
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape != nil)
        #expect(shape?.kind == .type("enum"))
    }

    @Test func extractsProperties() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let point = result.blocks.first { $0.typeName == "Point" }
        #expect(point != nil)
        #expect(point?.properties.contains { $0.name == "x" } == true)
        #expect(point?.properties.contains { $0.name == "y" } == true)
    }

    @Test func extractsMethods() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal != nil)
        let methodNames = animal?.methods.map(\.name) ?? []
        #expect(methodNames.contains("init"))
        #expect(methodNames.contains("greet"))
    }

    @Test func extractsUnion() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let value = result.blocks.first { $0.typeName == "Value" }
        #expect(value != nil)
        #expect(value?.kind == .type("union"))
        #expect(value?.properties.contains { $0.name == "int_val" } == true)
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "zig")
        #expect(parser.supportedExtensions.contains("zig"))
    }
}

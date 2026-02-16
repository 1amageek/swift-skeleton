import Testing
import Foundation
import SkeletonKotlinParser
import SkeletonIndexCore

@Suite struct KotlinSkeletonParserTests {
    let parser = KotlinSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesKotlinFile() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsInterface() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let drawable = result.blocks.first { $0.typeName == "Drawable" }
        #expect(drawable != nil)
        #expect(drawable?.kind == .type("interface"))
        #expect(drawable?.methods.contains { $0.name == "draw" } == true)
        #expect(drawable?.methods.contains { $0.name == "resize" } == true)
    }

    @Test func extractsClassWithInheritance() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape != nil)
        #expect(shape?.kind == .type("class"))
        #expect(shape?.inheritance.contains("Drawable") == true)
    }

    @Test func extractsProperties() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape?.properties.contains { $0.name == "area" } == true)
    }

    @Test func extractsMethods() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape?.methods.contains { $0.name == "describe" } == true)
    }

    @Test func extractsObject() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let singleton = result.blocks.first { $0.typeName == "Singleton" }
        #expect(singleton != nil)
        #expect(singleton?.kind == .type("object"))
    }

    @Test func extractsEnumClass() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let enumBlocks = result.blocks.filter { $0.typeName == "Color" }
        #expect(enumBlocks.count == 1)
        #expect(enumBlocks.first?.kind == .type("enum"))
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "kotlin")
        #expect(parser.supportedExtensions.contains("kt"))
        #expect(parser.supportedExtensions.contains("kts"))
    }
}

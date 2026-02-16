import Testing
import Foundation
import SkeletonTypeScriptParser
import SkeletonIndexCore

@Suite struct TypeScriptSkeletonParserTests {
    let parser = TypeScriptSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesTypeScriptFile() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsInterface() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let printable = result.blocks.first { $0.typeName == "Printable" }
        #expect(printable != nil)
        #expect(printable?.kind == .type("interface"))
    }

    @Test func extractsClassWithInheritance() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let dog = result.blocks.first { $0.typeName == "Dog" }
        #expect(dog != nil)
        #expect(dog?.kind == .type("class"))
        #expect(dog?.inheritance.contains("Animal") == true)
        #expect(dog?.inheritance.contains("Serializable") == true)
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let direction = result.blocks.first { $0.typeName == "Direction" }
        #expect(direction != nil)
        #expect(direction?.kind == .type("enum"))
    }

    @Test func extractsTypeAlias() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let point = result.blocks.first { $0.typeName == "Point" }
        #expect(point != nil)
        #expect(point?.kind == .type("type"))
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "typescript")
        #expect(parser.supportedExtensions.contains("ts"))
        #expect(parser.supportedExtensions.contains("tsx"))
    }
}

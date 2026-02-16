import Testing
import Foundation
import SkeletonGoParser
import SkeletonIndexCore

@Suite struct GoSkeletonParserTests {
    let parser = GoSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesGoFile() throws {
        let source = try fixtureSource("sample.go")
        let result = parser.parse(path: "sample.go", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsInterface() throws {
        let source = try fixtureSource("sample.go")
        let result = parser.parse(path: "sample.go", source: source)
        let stringer = result.blocks.first { $0.typeName == "Stringer" }
        #expect(stringer != nil)
        #expect(stringer?.kind == .type("interface"))
    }

    @Test func extractsStruct() throws {
        let source = try fixtureSource("sample.go")
        let result = parser.parse(path: "sample.go", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal != nil)
        #expect(animal?.kind == .type("struct"))
        #expect(animal?.properties.contains { $0.name == "Name" } == true)
        #expect(animal?.properties.contains { $0.name == "Age" } == true)
    }

    @Test func extractsReceiverMethods() throws {
        let source = try fixtureSource("sample.go")
        let result = parser.parse(path: "sample.go", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal?.methods.contains { $0.name == "String" } == true)
        #expect(animal?.methods.contains { $0.name == "Greet" } == true)
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "go")
        #expect(parser.supportedExtensions.contains("go"))
    }
}

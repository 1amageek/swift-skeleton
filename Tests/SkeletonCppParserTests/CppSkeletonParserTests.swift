import Testing
import Foundation
import SkeletonCppParser
import SkeletonIndexCore

@Suite struct CppSkeletonParserTests {
    let parser = CppSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesCppFile() throws {
        let source = try fixtureSource("sample.cpp")
        let result = parser.parse(path: "sample.cpp", source: source)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsClass() throws {
        let source = try fixtureSource("sample.cpp")
        let result = parser.parse(path: "sample.cpp", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal != nil)
        #expect(animal?.kind == .type("class"))
    }

    @Test func extractsClassWithInheritance() throws {
        let source = try fixtureSource("sample.cpp")
        let result = parser.parse(path: "sample.cpp", source: source)
        let dog = result.blocks.first { $0.typeName == "Dog" }
        #expect(dog != nil)
        #expect(dog?.kind == .type("class"))
    }

    @Test func extractsStruct() throws {
        let source = try fixtureSource("sample.cpp")
        let result = parser.parse(path: "sample.cpp", source: source)
        let point = result.blocks.first { $0.typeName == "Point" }
        #expect(point != nil)
        #expect(point?.kind == .type("struct"))
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("sample.cpp")
        let result = parser.parse(path: "sample.cpp", source: source)
        let color = result.blocks.first { $0.typeName == "Color" }
        #expect(color != nil)
        #expect(color?.kind == .type("enum"))
    }

    @Test func extractsUnion() throws {
        let source = try fixtureSource("sample.cpp")
        let result = parser.parse(path: "sample.cpp", source: source)
        let value = result.blocks.first { $0.typeName == "Value" }
        #expect(value != nil)
        #expect(value?.kind == .type("union"))
    }

    @Test func extractsNestedClass() throws {
        let source = try fixtureSource("sample.cpp")
        let result = parser.parse(path: "sample.cpp", source: source)
        let outer = result.blocks.first { $0.typeName == "Outer" }
        #expect(outer != nil)
        let inner = result.blocks.first { $0.typeName == "Inner" }
        #expect(inner != nil)
        #expect(inner?.kind == .type("class"))
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "cpp")
        #expect(parser.supportedExtensions.contains("cpp"))
        #expect(parser.supportedExtensions.contains("h"))
        #expect(parser.supportedExtensions.contains("hpp"))
    }
}

import Testing
import Foundation
import SkeletonPythonParser
import SkeletonIndexCore

@Suite struct PythonSkeletonParserTests {
    let parser = PythonSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesPythonFile() throws {
        let source = try fixtureSource("sample.py")
        let result = parser.parse(path: "sample.py", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsClass() throws {
        let source = try fixtureSource("sample.py")
        let result = parser.parse(path: "sample.py", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal != nil)
        #expect(animal?.kind == .type("class"))
    }

    @Test func extractsClassWithInheritance() throws {
        let source = try fixtureSource("sample.py")
        let result = parser.parse(path: "sample.py", source: source)
        let dog = result.blocks.first { $0.typeName == "Dog" }
        #expect(dog != nil)
        #expect(dog?.inheritance.contains("Animal") == true)
    }

    @Test func extractsInit() throws {
        let source = try fixtureSource("sample.py")
        let result = parser.parse(path: "sample.py", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        let initMethod = animal?.methods.first { $0.isInitializer }
        #expect(initMethod != nil)
        #expect(initMethod?.name == "__init__")
    }

    @Test func extractsMethods() throws {
        let source = try fixtureSource("sample.py")
        let result = parser.parse(path: "sample.py", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal?.methods.contains { $0.name == "greet" } == true)
        #expect(animal?.methods.contains { $0.name == "describe" } == true)
    }

    @Test func extractsProperties() throws {
        let source = try fixtureSource("sample.py")
        let result = parser.parse(path: "sample.py", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal?.properties.contains { $0.name == "name" } == true)
        #expect(animal?.properties.contains { $0.name == "age" } == true)
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "python")
        #expect(parser.supportedExtensions.contains("py"))
        #expect(parser.supportedExtensions.contains("pyi"))
    }
}

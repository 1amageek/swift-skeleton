import Testing
import Foundation
import SkeletonJavaParser
import SkeletonIndexCore

@Suite struct JavaSkeletonParserTests {
    let parser = JavaSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesJavaFile() throws {
        let source = try fixtureSource("Sample.java")
        let result = parser.parse(path: "Sample.java", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsInterface() throws {
        let source = try fixtureSource("Sample.java")
        let result = parser.parse(path: "Sample.java", source: source)
        let printable = result.blocks.first { $0.typeName == "Printable" }
        #expect(printable != nil)
        #expect(printable?.kind == .type("interface"))
    }

    @Test func extractsClassWithInheritance() throws {
        let source = try fixtureSource("Sample.java")
        let result = parser.parse(path: "Sample.java", source: source)
        let dog = result.blocks.first { $0.typeName == "Dog" }
        #expect(dog != nil)
        #expect(dog?.kind == .type("class"))
        #expect(dog?.inheritance.contains("Animal") == true)
    }

    @Test func extractsMethods() throws {
        let source = try fixtureSource("Sample.java")
        let result = parser.parse(path: "Sample.java", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal?.methods.contains { $0.name == "print" } == true)
        #expect(animal?.methods.contains { $0.name == "getName" } == true)
    }

    @Test func extractsConstructor() throws {
        let source = try fixtureSource("Sample.java")
        let result = parser.parse(path: "Sample.java", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal?.methods.contains { $0.isInitializer } == true)
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("Sample.java")
        let result = parser.parse(path: "Sample.java", source: source)
        let color = result.blocks.first { $0.typeName == "Color" }
        #expect(color != nil)
        #expect(color?.kind == .type("enum"))
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "java")
        #expect(parser.supportedExtensions.contains("java"))
    }
}

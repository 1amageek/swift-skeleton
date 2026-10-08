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

    @Test func extractsEnumBodyDeclarations() throws {
        let source = """
        public enum Planet implements Comparable<Planet>, Supplier<Map<String, Integer>> {
            MERCURY(3.3), VENUS(4.8);

            private final double mass;

            Planet(double mass) {
                this.mass = mass;
            }

            public double mass() {
                return mass;
            }
        }
        """
        let planet = try #require(parser.parse(path: "Planet.java", source: source).blocks.first { $0.typeName == "Planet" })
        #expect(planet.kind == .type("enum"))
        #expect(planet.range == SourceRange(startLine: 1, endLine: 13))
        #expect(planet.inheritance == ["Comparable<Planet>", "Supplier<Map<String, Integer>>"])
        #expect(renderProperties(planet) == ["mass:double"])
        #expect(renderMethods(planet) == ["init Planet(double) [6-8]", "mass() -> double [10-12]"])
    }

    @Test func extractsInterfaceExtendsAndConstants() throws {
        let source = """
        interface Shape extends Comparable<Shape>, Runnable {
            int MAX = 3;
            String A = "a", B = "b";
            java.io.File origin();
        }
        """
        let shape = try #require(parser.parse(path: "Shape.java", source: source).blocks.first { $0.typeName == "Shape" })
        #expect(shape.kind == .type("interface"))
        #expect(shape.inheritance == ["Comparable<Shape>", "Runnable"])
        #expect(renderProperties(shape) == ["MAX:int", "A:String", "B:String"])
        #expect(renderMethods(shape) == ["origin() -> java.io.File [4-4]"])
    }

    @Test func extractsQualifiedTypesMultiDeclaratorsAndGenericInterfaces() throws {
        let source = """
        class Holder<K, V> extends java.util.AbstractMap<K, V> implements Map<K, V>, java.io.Serializable {
            java.io.File file;
            int a, b;
            Outer.Inner make() { return null; }
            void take(java.util.List<String> items, Outer.Inner inner) {}
        }
        """
        let holder = try #require(parser.parse(path: "Holder.java", source: source).blocks.first { $0.typeName == "Holder" })
        #expect(holder.inheritance == ["java.util.AbstractMap<K, V>", "Map<K, V>", "java.io.Serializable"])
        #expect(renderProperties(holder) == ["file:java.io.File", "a:int", "b:int"])
        #expect(renderMethods(holder) == [
            "make() -> Outer.Inner [4-4]",
            "take(java.util.List<String>, Outer.Inner) -> void [5-5]",
        ])
    }

    private func renderProperties(_ block: SkeletonBlock) -> [String] {
        block.properties.map { "\($0.name):\($0.typeRef)" }
    }

    private func renderMethods(_ block: SkeletonBlock) -> [String] {
        block.methods.map { method in
            let prefix = method.isInitializer ? "init " : ""
            let returnPart = method.returnTypeRef.map { " -> \($0)" } ?? ""
            let start = method.range.startLine.map(String.init) ?? "?"
            let end = method.range.endLine.map(String.init) ?? "?"
            return "\(prefix)\(method.name)(\(method.parameterTypeRefs.joined(separator: ", ")))\(returnPart) [\(start)-\(end)]"
        }
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "java")
        #expect(parser.supportedExtensions.contains("java"))
    }
}

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

    @Test func collectsNestedConditionalAndDecoratedClasses() throws {
        let source = """
        import sys

        class Outer:
            class Inner(Base):
                value: int

                def run(self, count: int) -> bool:
                    def helper(x: int) -> int:
                        return x
                    return True

            def outer_method(self) -> None:
                class LocalInFunction:
                    def local(self) -> None:
                        pass

        if sys.version_info >= (3, 8):
            class Conditional:
                def cond(self) -> int:
                    return 1

        try:
            class InTry:
                pass
        except ImportError:
            class InExcept:
                pass

        with open("x") as f:
            class InWith:
                pass

        @decorator
        class Decorated:
            @staticmethod
            def make(cls_name: str) -> "Decorated":
                ...
        """
        let blocks = parser.parse(path: "nested.py", source: source).blocks
        #expect(blocks.map(\.typeName) == [
            "Outer", "Inner", "LocalInFunction", "Conditional", "InTry", "InExcept", "InWith", "Decorated",
        ])

        let outer = try #require(blocks.first { $0.typeName == "Outer" })
        #expect(outer.range == SourceRange(startLine: 3, endLine: 15))
        #expect(renderMethods(outer) == ["outer_method() -> None [12-15]"])

        let inner = try #require(blocks.first { $0.typeName == "Inner" })
        #expect(inner.range == SourceRange(startLine: 4, endLine: 10))
        #expect(inner.inheritance == ["Base"])
        #expect(inner.properties.map { "\($0.name):\($0.typeRef)" } == ["value:int"])
        #expect(renderMethods(inner) == ["run(int) -> bool [7-10]"])

        let local = try #require(blocks.first { $0.typeName == "LocalInFunction" })
        #expect(renderMethods(local) == ["local() -> None [14-15]"])

        let conditional = try #require(blocks.first { $0.typeName == "Conditional" })
        #expect(conditional.range == SourceRange(startLine: 18, endLine: 20))
        #expect(renderMethods(conditional) == ["cond() -> int [19-20]"])

        let decorated = try #require(blocks.first { $0.typeName == "Decorated" })
        #expect(decorated.range == SourceRange(startLine: 34, endLine: 37))
        #expect(renderMethods(decorated) == ["make(str) -> \"Decorated\" [36-37]"])
    }

    @Test func dropsOnlyExactReceiverParameter() throws {
        let source = """
        class Checker:
            def check(self, self_test: bool, clsid: str, cls_default: int = 1, selfish=2) -> None:
                pass

            @classmethod
            def build(cls, config: dict) -> "Checker":
                pass

            def typed(self: "Checker", n: int) -> None:
                pass
        """
        let checker = try #require(parser.parse(path: "checker.py", source: source).blocks.first)
        #expect(renderMethods(checker) == [
            "check(bool, str, int, ?) -> None [2-3]",
            "build(dict) -> \"Checker\" [6-7]",
            "typed(int) -> None [9-10]",
        ])
    }

    private func renderMethods(_ block: SkeletonBlock) -> [String] {
        block.methods.map { method in
            let returnPart = method.returnTypeRef.map { " -> \($0)" } ?? ""
            let start = method.range.startLine.map(String.init) ?? "?"
            let end = method.range.endLine.map(String.init) ?? "?"
            return "\(method.name)(\(method.parameterTypeRefs.joined(separator: ", ")))\(returnPart) [\(start)-\(end)]"
        }
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "python")
        #expect(parser.supportedExtensions.contains("py"))
        #expect(parser.supportedExtensions.contains("pyi"))
    }
}

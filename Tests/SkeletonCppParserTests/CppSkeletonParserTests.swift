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

    private static let memberSource = """
    class Base {};
    class Foo;
    class Foo : public Base, protected virtual Mixin<int, T>, private ns::Other {
    public:
        std::string name;
        int* ptr;
        int& ref;
        const char* cstr;
        int a, *b;
        Foo(int x) {}
        Foo(const Foo& other);
        ~Foo() {}
        Foo* self() { return this; }
        std::string label() { return name; }
        void declared(int);
        virtual int pure() = 0;
        int& at(int i);
        std::vector<int> items() const;
        void takes(int*, std::string&& s);
        struct Nested { int z; };
    };
    """

    private func memberBlock() throws -> SkeletonBlock {
        let result = parser.parse(path: "foo.hpp", source: Self.memberSource)
        let fooBlocks = result.blocks.filter { $0.typeName == "Foo" }
        #expect(fooBlocks.count == 1)
        return try #require(fooBlocks.first)
    }

    private func method(_ name: String, in block: SkeletonBlock) throws -> MethodSignature {
        let matches = block.methods.filter { $0.name == name }
        #expect(matches.count == 1, "Expected exactly one method named \(name)")
        return try #require(matches.first)
    }

    @Test func skipsForwardDeclarationWithoutBody() throws {
        let block = try memberBlock()
        #expect(block.range == SourceRange(startLine: 3, endLine: 21))
    }

    @Test func rendersBaseClassesWithoutAccessSpecifiers() throws {
        let block = try memberBlock()
        #expect(block.inheritance == ["Base", "Mixin<int, T>", "ns::Other"])
    }

    @Test func extractsQualifiedPointerAndReferenceFields() throws {
        let block = try memberBlock()
        #expect(block.properties.map(\.name) == ["name", "ptr", "ref", "cstr", "a", "b"])
        #expect(block.properties.map(\.typeRef) == [
            "std::string", "int*", "int&", "const char*", "int", "int*",
        ])
    }

    @Test func marksConstructorsAsInitializers() throws {
        let block = try memberBlock()
        let constructors = block.methods.filter(\.isInitializer)
        #expect(constructors.map(\.name) == ["Foo", "Foo"])
        #expect(constructors.map(\.parameterTypeRefs) == [["int"], ["const Foo&"]])
        #expect(constructors.allSatisfy { $0.returnTypeRef == nil })
        #expect(constructors.map(\.range) == [
            SourceRange(startLine: 10, endLine: 10),
            SourceRange(startLine: 11, endLine: 11),
        ])
    }

    @Test func doesNotMarkDestructorAsInitializer() throws {
        let block = try memberBlock()
        let destructor = try method("~Foo", in: block)
        #expect(!destructor.isInitializer)
        #expect(destructor.returnTypeRef == nil)
        #expect(destructor.parameterTypeRefs.isEmpty)
    }

    @Test func pointerReturningMethodIsNotInitializer() throws {
        let block = try memberBlock()
        let selfMethod = try method("self", in: block)
        #expect(!selfMethod.isInitializer)
        #expect(selfMethod.returnTypeRef == "Foo*")
        #expect(selfMethod.range == SourceRange(startLine: 13, endLine: 13))
    }

    @Test func keepsQualifiedAndTemplateReturnTypes() throws {
        let block = try memberBlock()
        #expect(try method("label", in: block).returnTypeRef == "std::string")
        #expect(try method("items", in: block).returnTypeRef == "std::vector<int>")
        #expect(try method("at", in: block).returnTypeRef == "int&")
    }

    @Test func extractsBodilessMemberFunctionDeclarations() throws {
        let block = try memberBlock()
        let declared = try method("declared", in: block)
        #expect(declared.parameterTypeRefs == ["int"])
        #expect(declared.returnTypeRef == "void")
        #expect(declared.range == SourceRange(startLine: 15, endLine: 15))
        #expect(!declared.isInitializer)

        let pure = try method("pure", in: block)
        #expect(pure.parameterTypeRefs.isEmpty)
        #expect(pure.returnTypeRef == "int")
        #expect(pure.range == SourceRange(startLine: 16, endLine: 16))

        let takes = try method("takes", in: block)
        #expect(takes.parameterTypeRefs == ["int*", "std::string&&"])
    }

    @Test func preservesMemberOrder() throws {
        let block = try memberBlock()
        #expect(block.methods.map(\.name) == [
            "Foo", "Foo", "~Foo", "self", "label", "declared", "pure", "at", "items", "takes",
        ])
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "cpp")
        #expect(parser.supportedExtensions.contains("cpp"))
        #expect(parser.supportedExtensions.contains("h"))
        #expect(parser.supportedExtensions.contains("hpp"))
    }
}

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

    private func block(_ name: String, in result: ParsedFile) throws -> SkeletonBlock {
        try #require(result.blocks.first { $0.typeName == name })
    }

    private func method(_ name: String, in block: SkeletonBlock) throws -> MethodSignature {
        try #require(block.methods.first { $0.name == name })
    }

    @Test func oneLineMethodReturnTypeComesFromResultNode() throws {
        let source = """
        package service
        type Service struct {}
        func (service *Service) Run(value int) int { panic("pending") }
        """
        let result = parser.parse(path: "service.go", source: source)
        let run = try method("Run", in: try block("Service", in: result))
        #expect(run.parameterTypeRefs == ["int"])
        #expect(run.returnTypeRef == "int")
        #expect(run.range == SourceRange(startLine: 3, endLine: 3))
    }

    @Test func groupedTypeDeclarationEmitsOneBlockPerSpec() throws {
        let source = """
        package p
        type (
        \tA struct{ X int }
        \tB struct {
        \t\tY, Z int
        \t}
        )
        """
        let result = parser.parse(path: "group.go", source: source)
        #expect(result.blocks.map(\.typeName) == ["A", "B"])
        let a = try block("A", in: result)
        #expect(a.kind == .type("struct"))
        #expect(a.range == SourceRange(startLine: 3, endLine: 3))
        #expect(a.properties.map(\.name) == ["X"])
        let b = try block("B", in: result)
        #expect(b.kind == .type("struct"))
        #expect(b.range == SourceRange(startLine: 4, endLine: 6))
        #expect(b.properties.map(\.name) == ["Y", "Z"])
        #expect(b.properties.map(\.typeRef) == ["int", "int"])
    }

    @Test func genericReceiverAttachesToBaseType() throws {
        let source = """
        package p
        type Stack[T any] struct { items []T }
        func (s *Stack[T]) Push(v T) {}
        func (s Stack[T]) Peek() T { return s.items[0] }
        """
        let result = parser.parse(path: "stack.go", source: source)
        let stack = try block("Stack", in: result)
        #expect(stack.properties.map(\.typeRef) == ["[]T"])
        let push = try method("Push", in: stack)
        #expect(push.parameterTypeRefs == ["T"])
        #expect(push.returnTypeRef == nil)
        #expect(push.range == SourceRange(startLine: 3, endLine: 3))
        let peek = try method("Peek", in: stack)
        #expect(peek.parameterTypeRefs == [])
        #expect(peek.returnTypeRef == "T")
    }

    @Test func parameterAndResultListsExpandGroupedNames() throws {
        let source = """
        package p
        type R struct{}
        func (r R) Pair(a, b int, f func(int) error) (int, error) { return 0, nil }
        func (r *R) Read(p []byte) (n int, err error) {
        \treturn
        }
        func (r R) Log(format string, args ...any) {}
        type Reader interface {
        \tRead(p []byte) (n int, err error)
        \tM(a, b int) error
        }
        """
        let result = parser.parse(path: "params.go", source: source)
        let r = try block("R", in: result)
        let pair = try method("Pair", in: r)
        #expect(pair.parameterTypeRefs == ["int", "int", "func(int) error"])
        #expect(pair.returnTypeRef == "(int, error)")
        let read = try method("Read", in: r)
        #expect(read.parameterTypeRefs == ["[]byte"])
        #expect(read.returnTypeRef == "(int, error)")
        #expect(read.range == SourceRange(startLine: 4, endLine: 6))
        let log = try method("Log", in: r)
        #expect(log.parameterTypeRefs == ["string", "...any"])
        #expect(log.returnTypeRef == nil)

        let reader = try block("Reader", in: result)
        let interfaceRead = try method("Read", in: reader)
        #expect(interfaceRead.parameterTypeRefs == ["[]byte"])
        #expect(interfaceRead.returnTypeRef == "(int, error)")
        #expect(interfaceRead.range == SourceRange(startLine: 9, endLine: 9))
        let m = try method("M", in: reader)
        #expect(m.parameterTypeRefs == ["int", "int"])
        #expect(m.returnTypeRef == "error")
    }

    @Test func unclosedTypeDeclarationKeepsPartialBlock() throws {
        let source = """
        package p

        type S struct {
        \tX int
        \tY string
        """
        let result = parser.parse(path: "broken.go", source: source)
        #expect(result.hasParseError)
        let s = try block("S", in: result)
        #expect(s.kind == .type("struct"))
        #expect(s.hasErrorNode)
        #expect(s.range == SourceRange(startLine: 3, endLine: nil))
        #expect(s.properties.map(\.name) == ["X", "Y"])
        #expect(s.properties.map(\.typeRef) == ["int", "string"])
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "go")
        #expect(parser.supportedExtensions.contains("go"))
    }
}

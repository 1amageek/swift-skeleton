import Testing
import Foundation
import SkeletonZigParser
import SkeletonIndexCore

@Suite struct ZigSkeletonParserTests {
    let parser = ZigSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesZigFile() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsStruct() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal != nil)
        #expect(animal?.kind == .type("struct"))
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape != nil)
        #expect(shape?.kind == .type("enum"))
    }

    @Test func extractsProperties() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let point = result.blocks.first { $0.typeName == "Point" }
        #expect(point != nil)
        #expect(point?.properties.contains { $0.name == "x" } == true)
        #expect(point?.properties.contains { $0.name == "y" } == true)
    }

    @Test func extractsMethods() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let animal = result.blocks.first { $0.typeName == "Animal" }
        #expect(animal != nil)
        let methodNames = animal?.methods.map(\.name) ?? []
        #expect(methodNames.contains("init"))
        #expect(methodNames.contains("greet"))
    }

    @Test func extractsUnion() throws {
        let source = try fixtureSource("sample.zig")
        let result = parser.parse(path: "sample.zig", source: source)
        let value = result.blocks.first { $0.typeName == "Value" }
        #expect(value != nil)
        #expect(value?.kind == .type("union"))
        #expect(value?.properties.contains { $0.name == "int_val" } == true)
    }

    private func block(_ name: String, in result: ParsedFile) throws -> SkeletonBlock {
        try #require(result.blocks.first { $0.typeName == name })
    }

    private func method(_ name: String, in block: SkeletonBlock) throws -> MethodSignature {
        try #require(block.methods.first { $0.name == name })
    }

    @Test func oneLineFunctionReturnTypeExcludesBody() throws {
        let source = """
        pub const Point = struct {
            x: i32,
            pub fn eql(a: Point, b: Point) bool { return a.x == b.x; }
            pub fn get(self: *const Point) i32 { return self.x; }
        };
        """
        let result = parser.parse(path: "point.zig", source: source)
        let point = try block("Point", in: result)
        let eql = try method("eql", in: point)
        #expect(eql.parameterTypeRefs == ["Point", "Point"])
        #expect(eql.returnTypeRef == "bool")
        #expect(eql.range == SourceRange(startLine: 3, endLine: 3))
        let get = try method("get", in: point)
        #expect(get.parameterTypeRefs == ["*const Point"])
        #expect(get.returnTypeRef == "i32")
        #expect(get.range == SourceRange(startLine: 4, endLine: 4))
    }

    @Test func structSubstringInsideFunctionIsNotAContainer() throws {
        let source = """
        fn helper() void {
            const v = structure.x;
            _ = v;
        }
        """
        let result = parser.parse(path: "helper.zig", source: source)
        #expect(result.blocks.isEmpty)
    }

    @Test func nestedContainersAreEmittedAsBlocks() throws {
        let source = """
        const Outer = struct {
            value: u32,
            const Inner = struct {
                x: u32,
            };
            pub const Kind = enum { a, b };
            const Handle = opaque {};
        };
        """
        let result = parser.parse(path: "nested.zig", source: source)
        #expect(result.blocks.map(\.typeName) == ["Outer", "Inner", "Kind", "Handle"])
        let outer = try block("Outer", in: result)
        #expect(outer.range == SourceRange(startLine: 1, endLine: 8))
        #expect(outer.properties.map(\.name) == ["value"])
        let inner = try block("Inner", in: result)
        #expect(inner.kind == .type("struct"))
        #expect(inner.range == SourceRange(startLine: 3, endLine: 5))
        #expect(inner.properties.map(\.name) == ["x"])
        #expect(inner.properties.map(\.typeRef) == ["u32"])
        #expect(try block("Kind", in: result).kind == .type("enum"))
        let handle = try block("Handle", in: result)
        #expect(handle.kind == .type("opaque"))
        #expect(handle.properties.isEmpty)
    }

    @Test func multiLineSignatureKeepsParametersAndReturnType() throws {
        let source = """
        const Allocator = @import("std").mem.Allocator;
        pub const Buffer = struct {
            x: u32,

            pub fn init(
                x: u32,
                allocator: Allocator,
            ) !Buffer {
                _ = allocator;
                return .{ .x = x };
            }
        };
        """
        let result = parser.parse(path: "buffer.zig", source: source)
        #expect(result.blocks.map(\.typeName) == ["Buffer"])
        let buffer = try block("Buffer", in: result)
        #expect(buffer.properties.map(\.name) == ["x"])
        #expect(buffer.properties.map(\.typeRef) == ["u32"])
        let initializer = try method("init", in: buffer)
        #expect(initializer.isInitializer)
        #expect(initializer.parameterTypeRefs == ["u32", "Allocator"])
        #expect(initializer.returnTypeRef == "!Buffer")
        #expect(initializer.range == SourceRange(startLine: 5, endLine: 11))
    }

    @Test func unclosedContainerKeepsPartialBlock() throws {
        let source = """
        const Outer = struct {
            x: u32,
            pub fn init(
                x: u32,
            ) Outer {
                return .{ .x = x };
            }
        """
        let result = parser.parse(path: "broken.zig", source: source)
        #expect(result.hasParseError)
        let outer = try block("Outer", in: result)
        #expect(outer.hasErrorNode)
        #expect(outer.range == SourceRange(startLine: 1, endLine: nil))
        #expect(outer.properties.map(\.name) == ["x"])
        let initializer = try method("init", in: outer)
        #expect(initializer.parameterTypeRefs == ["u32"])
        #expect(initializer.returnTypeRef == "Outer")
        #expect(initializer.range == SourceRange(startLine: 3, endLine: 7))
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "zig")
        #expect(parser.supportedExtensions.contains("zig"))
    }
}

import Testing
import Foundation
import SkeletonRustParser
import SkeletonIndexCore

@Suite struct RustSkeletonParserTests {
    let parser = RustSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesRustFile() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsTrait() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let drawable = result.blocks.first { $0.typeName == "Drawable" }
        #expect(drawable != nil)
        #expect(drawable?.kind == .type("trait"))
    }

    @Test func extractsStruct() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let circle = result.blocks.first { $0.typeName == "Circle" && $0.kind == .type("struct") }
        #expect(circle != nil)
        #expect(circle?.properties.contains { $0.name == "radius" } == true)
    }

    @Test func extractsImpl() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let impls = result.blocks.filter { $0.kind == .extension }
        #expect(!impls.isEmpty)
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" && $0.kind == .type("enum") }
        #expect(shape != nil)
    }

    @Test func implTraitForType() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let implBlocks = result.blocks.filter { $0.kind == .extension }
        let traitImpl = implBlocks.first { block in
            block.methods.contains { $0.name == "draw" }
        }
        #expect(traitImpl != nil)
        #expect(traitImpl?.typeName == "Circle")
        #expect(traitImpl?.inheritance == ["Drawable"])
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "rust")
        #expect(parser.supportedExtensions.contains("rs"))
    }

    // MARK: - Member extraction regressions

    private func signature(_ method: MethodSignature) -> String {
        let name = method.isInitializer ? "init" : method.name
        let returnPart = method.returnTypeRef.map { " -> \($0)" } ?? ""
        let start = method.range.startLine.map(String.init) ?? "?"
        let end = method.range.endLine.map(String.init) ?? "?"
        return "\(name)(\(method.parameterTypeRefs.joined(separator: ", ")))\(returnPart) [\(start)-\(end)]"
    }

    @Test func charLiteralsAndLifetimesDoNotShiftDepth() throws {
        let source = """
        impl Point {
            fn check(c: char) -> bool {
                if c == '"' || c == '{' || c == '\\'' {
                    return true;
                }
                false
            }
            fn after(&self) -> i32 { 1 }
            fn life<'a>(s: &'a str) -> &'a str { s }
            // stray {
            /* block { /* nested } */ { */
            fn text(&self) -> String {
                let raw = r#"}"#;
                String::from("{
                ")
            }
            fn later(&self) {}
        }
        """
        let result = parser.parse(path: "point.rs", source: source)
        let block = try #require(result.blocks.first { $0.kind == .extension && $0.typeName == "Point" })
        #expect(block.range == SourceRange(startLine: 1, endLine: 18))
        #expect(block.methods.map(signature) == [
            "check(char) -> bool [2-7]",
            "after(?) -> i32 [8-8]",
            "life(&'a str) -> &'a str [9-9]",
            "text(?) -> String [12-16]",
            "later(?) [17-17]",
        ])
    }

    @Test func genericImplBlockIsExtracted() throws {
        let source = """
        impl<T: Clone> Wrapper<T> {
            fn get(&self) -> &T { &self.0 }
        }
        """
        let result = parser.parse(path: "wrapper.rs", source: source)
        let block = try #require(result.blocks.first)
        #expect(block.kind == .extension)
        #expect(block.typeName == "Wrapper<T>")
        #expect(block.inheritance.isEmpty)
        #expect(block.methods.map(signature) == ["get(?) -> &T [2-2]"])
    }

    /// Contract: `impl Trait for Type` renders as `extension Type: Trait`, keeping the trait path.
    @Test func implTraitPathForTypeRendersTraitAsInheritance() throws {
        let source = """
        impl fmt::Display for Point {
            fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result { Ok(()) }
        }
        impl<T> From<Vec<T>> for Wrapper<T> where T: Clone {
            fn from(values: Vec<T>) -> Self { Wrapper(values) }
        }
        """
        let result = parser.parse(path: "display.rs", source: source)
        #expect(result.blocks.map(\.typeName) == ["Point", "Wrapper<T>"])
        #expect(result.blocks.map(\.inheritance) == [["fmt::Display"], ["From<Vec<T>>"]])
        #expect(result.blocks.allSatisfy { $0.kind == .extension })
        #expect(result.blocks.first?.methods.map(signature) == ["fmt(?, &mut fmt::Formatter) -> fmt::Result [2-2]"])
    }

    @Test func traitSupertraitsIgnorePathSeparatorsAndWhereClauses() throws {
        let source = """
        trait Render: fmt::Debug + Send where Self: Sized {
            fn render(&self) -> String;
        }
        """
        let result = parser.parse(path: "render.rs", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Render" })
        #expect(block.inheritance == ["fmt::Debug", "Send"])
        #expect(block.methods.map(signature) == ["render(?) -> String [2-2]"])
    }

    @Test func whereClauseAndMultiLineParametersAreNotProperties() throws {
        let source = """
        impl Multi {
            fn multi<T>(
                a: T,
                count: usize,
                b: T,
            ) -> usize
            where
                T: Clone,
            {
                count
            }
            fn after(&self) {}
        }
        """
        let result = parser.parse(path: "multi.rs", source: source)
        let block = try #require(result.blocks.first)
        #expect(block.properties.isEmpty)
        #expect(block.methods.map(signature) == ["multi(T, usize, T) -> usize [2-11]", "after(?) [12-12]"])
    }

    /// Contract: Rust has no initializers. `fn new` is an associated function and renders as
    /// `new(...) -> <ReturnType>`, not `init(...)`.
    @Test func newIsAnAssociatedFunctionNotAnInitializer() throws {
        let source = try fixtureSource("sample.rs")
        let result = parser.parse(path: "sample.rs", source: source)
        let circleImpl = try #require(result.blocks.first { $0.kind == .extension && $0.typeName == "Circle" })
        let new = try #require(circleImpl.methods.first { $0.name == "new" })
        #expect(!new.isInitializer)
        #expect(signature(new) == "new(f64) -> Circle [13-19]")
    }
}

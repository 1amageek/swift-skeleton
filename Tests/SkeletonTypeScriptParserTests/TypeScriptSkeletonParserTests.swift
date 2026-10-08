import Testing
import Foundation
import SkeletonTypeScriptParser
import SkeletonIndexCore

@Suite struct TypeScriptSkeletonParserTests {
    let parser = TypeScriptSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesTypeScriptFile() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsInterface() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let printable = result.blocks.first { $0.typeName == "Printable" }
        #expect(printable != nil)
        #expect(printable?.kind == .type("interface"))
    }

    @Test func extractsClassWithInheritance() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let dog = result.blocks.first { $0.typeName == "Dog" }
        #expect(dog != nil)
        #expect(dog?.kind == .type("class"))
        #expect(dog?.inheritance.contains("Animal") == true)
        #expect(dog?.inheritance.contains("Serializable") == true)
    }

    @Test func extractsEnum() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let direction = result.blocks.first { $0.typeName == "Direction" }
        #expect(direction != nil)
        #expect(direction?.kind == .type("enum"))
    }

    @Test func extractsTypeAlias() throws {
        let source = try fixtureSource("Sample.ts")
        let result = parser.parse(path: "Sample.ts", source: source)
        let point = result.blocks.first { $0.typeName == "Point" }
        #expect(point != nil)
        #expect(point?.kind == .type("type"))
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "typescript")
        #expect(parser.supportedExtensions.contains("ts"))
        #expect(parser.supportedExtensions.contains("tsx"))
    }

    // MARK: - Member extraction regressions

    private func signature(_ method: MethodSignature) -> String {
        let name = method.isInitializer ? "init" : method.name
        let returnPart = method.returnTypeRef.map { " -> \($0)" } ?? ""
        let start = method.range.startLine.map(String.init) ?? "?"
        let end = method.range.endLine.map(String.init) ?? "?"
        return "\(name)(\(method.parameterTypeRefs.joined(separator: ", ")))\(returnPart) [\(start)-\(end)]"
    }

    @Test func bracesInsideSingleQuotedStringsDoNotHideMembers() throws {
        let source = """
        class Svc {
            open = '{';
            first(): number {
                return 1;
            }
            third() {}
        }
        """
        let result = parser.parse(path: "Svc.ts", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Svc" })
        #expect(block.range == SourceRange(startLine: 1, endLine: 7))
        #expect(block.methods.map(signature) == ["first() -> number [3-5]", "third() [6-6]"])
    }

    @Test func bracesInsideTemplateLiteralsAndCommentsDoNotShiftDepth() throws {
        let source = """
        class Template {
            label: string = `x ${ "{" } y ${ `}` } {`;
            // stray {
            /* block {
               still { */
            multi: string = `
                }
            `;
            run(mode: 'a' | 'b'): void {}
            after(): number {
                return 1;
            }
        }
        """
        let result = parser.parse(path: "Template.ts", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Template" })
        #expect(block.properties.map { "\($0.name):\($0.typeRef)" } == ["label:string", "multi:string"])
        #expect(block.methods.map(signature) == ["run('a' | 'b') -> void [9-9]", "after() -> number [10-12]"])
    }

    @Test func decoratorWithObjectArgumentKeepsClass() throws {
        let source = """
        @Component({ selector: 'app', template: '<div>{{ type }}</div>' })
        class Decorated extends Base implements OnInit {
            go(): void {}
        }
        """
        let result = parser.parse(path: "Decorated.ts", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Decorated" })
        #expect(block.kind == .type("class"))
        #expect(block.inheritance == ["Base", "OnInit"])
        #expect(block.methods.map(signature) == ["go() -> void [3-3]"])
    }

    @Test func multiLineParametersWithTrailingCommaAreNotProperties() throws {
        let source = """
        class Multi {
            count: number;
            second(
                a: number,
                b: string,
            ): number {
                return a;
            }
            after(): void {}
        }
        """
        let result = parser.parse(path: "Multi.ts", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Multi" })
        #expect(block.properties.map { "\($0.name):\($0.typeRef)" } == ["count:number"])
        #expect(block.methods.map(signature) == ["second(number, string) -> number [3-8]", "after() -> void [9-9]"])
    }
}

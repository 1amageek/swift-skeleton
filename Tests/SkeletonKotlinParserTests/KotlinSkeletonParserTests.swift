import Testing
import Foundation
import SkeletonKotlinParser
import SkeletonIndexCore

@Suite struct KotlinSkeletonParserTests {
    let parser = KotlinSkeletonParser()

    private func fixtureSource(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw SkeletonError.fileReadFailed("Fixture not found: \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesKotlinFile() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        #expect(!result.hasParseError)
        #expect(!result.blocks.isEmpty)
    }

    @Test func extractsInterface() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let drawable = result.blocks.first { $0.typeName == "Drawable" }
        #expect(drawable != nil)
        #expect(drawable?.kind == .type("interface"))
        #expect(drawable?.methods.contains { $0.name == "draw" } == true)
        #expect(drawable?.methods.contains { $0.name == "resize" } == true)
    }

    @Test func extractsClassWithInheritance() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape != nil)
        #expect(shape?.kind == .type("class"))
        #expect(shape?.inheritance.contains("Drawable") == true)
    }

    @Test func extractsProperties() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape?.properties.contains { $0.name == "area" } == true)
    }

    @Test func extractsMethods() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let shape = result.blocks.first { $0.typeName == "Shape" }
        #expect(shape?.methods.contains { $0.name == "describe" } == true)
    }

    @Test func extractsObject() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let singleton = result.blocks.first { $0.typeName == "Singleton" }
        #expect(singleton != nil)
        #expect(singleton?.kind == .type("object"))
    }

    @Test func extractsEnumClass() throws {
        let source = try fixtureSource("Sample.kt")
        let result = parser.parse(path: "Sample.kt", source: source)
        let enumBlocks = result.blocks.filter { $0.typeName == "Color" }
        #expect(enumBlocks.count == 1)
        #expect(enumBlocks.first?.kind == .type("enum"))
    }

    @Test func protocolConformance() {
        #expect(parser.languageName == "kotlin")
        #expect(parser.supportedExtensions.contains("kt"))
        #expect(parser.supportedExtensions.contains("kts"))
    }

    // MARK: - Member extraction regressions

    private func signature(_ method: MethodSignature) -> String {
        let name = method.isInitializer ? "init" : method.name
        let returnPart = method.returnTypeRef.map { " -> \($0)" } ?? ""
        let start = method.range.startLine.map(String.init) ?? "?"
        let end = method.range.endLine.map(String.init) ?? "?"
        return "\(name)(\(method.parameterTypeRefs.joined(separator: ", ")))\(returnPart) [\(start)-\(end)]"
    }

    @Test func genericAndExtensionFunctionsKeepTheirNames() throws {
        let source = """
        class Utilities {
            fun <T> generic(value: T): T {
                return value
            }
            fun String.ext(times: Int): Int {
                return times
            }
            fun <K, V> Map<K, V>.firstKey(): K? = keys.firstOrNull()
        }
        """
        let result = parser.parse(path: "Utilities.kt", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Utilities" })
        #expect(block.methods.map(signature) == [
            "generic(T) -> T [2-4]",
            "ext(Int) -> Int [5-7]",
            "firstKey() -> K? [8-8]",
        ])
    }

    @Test func expressionBodyDoesNotLeakIntoReturnType() throws {
        let source = """
        class Answers {
            fun answer(): Int = 42
            fun label(): String = "a = {"
            fun inferred() = 7
        }
        """
        let result = parser.parse(path: "Answers.kt", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Answers" })
        #expect(block.methods.map(signature) == [
            "answer() -> Int [2-2]",
            "label() -> String [3-3]",
            "inferred() [4-4]",
        ])
    }

    /// Contract: a companion object is emitted as its own `object` block, the same way nested
    /// types are emitted as separate blocks. An unnamed companion uses Kotlin's implicit name
    /// `Companion`. Its members are listed on that block, not on the enclosing class.
    @Test func companionObjectMembersAreEmittedAsNestedObjectBlock() throws {
        let source = """
        class Factory {
            fun build(): Int = 1
            companion object {
                val DEFAULT: Int = 1
                fun create(): Factory = Factory()
            }
        }
        class Registry {
            companion object Store : Cache<String> {
                fun lookup(key: String): String? = null
            }
        }
        """
        let result = parser.parse(path: "Factory.kt", source: source)
        let factory = try #require(result.blocks.first { $0.typeName == "Factory" })
        #expect(factory.methods.map(signature) == ["build() -> Int [2-2]"])
        #expect(factory.properties.isEmpty)

        let companion = try #require(result.blocks.first { $0.typeName == "Companion" })
        #expect(companion.kind == .type("object"))
        #expect(companion.range == SourceRange(startLine: 3, endLine: 6))
        #expect(companion.properties.map { "\($0.name):\($0.typeRef)" } == ["DEFAULT:Int"])
        #expect(companion.methods.map(signature) == ["create() -> Factory [5-5]"])

        let store = try #require(result.blocks.first { $0.typeName == "Store" })
        #expect(store.kind == .type("object"))
        #expect(store.inheritance == ["Cache<String>"])
        #expect(store.methods.map(signature) == ["lookup(String) -> String? [10-10]"])
    }

    @Test func bracesInsideLiteralsAndCommentsDoNotShiftDepth() throws {
        let source = """
        class Lexer {
            val open: Char = '{'
            val text: String = "}"
            // stray {
            /* block {
               /* nested } */ still comment {
            */
            val raw: String = \"\"\"
                }
            \"\"\"
            fun first(): Int {
                return 1
            }
            fun second() {}
        }
        """
        let result = parser.parse(path: "Lexer.kt", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Lexer" })
        #expect(block.properties.map { "\($0.name):\($0.typeRef)" } == [
            "open:Char", "text:String", "raw:String",
        ])
        #expect(block.methods.map(signature) == ["first() -> Int [11-13]", "second() [14-14]"])
    }

    @Test func unclosedClassKeepsPartialBlockWithUnknownEnd() throws {
        let source = """
        class Broken {
            fun a() {}
            fun b(): Int = 2

        """
        let result = parser.parse(path: "Broken.kt", source: source)
        #expect(result.hasParseError)
        let block = try #require(result.blocks.first { $0.typeName == "Broken" })
        #expect(block.kind == .type("class"))
        #expect(block.hasErrorNode)
        #expect(block.range == SourceRange(startLine: 1, endLine: nil))
        #expect(block.methods.map(signature) == ["a() [2-2]", "b() -> Int [3-3]"])
    }

    @Test func formFeedAndLineSeparatorDoNotShiftLineNumbers() throws {
        let source = "class Lines {\n    // \u{0C} form feed\n    fun b(): Int {\n        return 1\n    }\n"
            + "    // \u{2028} line separator\n    fun c(): Int = 2\n}\n"
        let result = parser.parse(path: "Lines.kt", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Lines" })
        #expect(block.range == SourceRange(startLine: 1, endLine: 8))
        #expect(block.methods.map(signature) == ["b() -> Int [3-5]", "c() -> Int [7-7]"])
    }

    @Test func carriageReturnLineFeedCountsAsOneLine() throws {
        let source = "class Windows {\r\n    fun a(): Int {\r\n        return 1\r\n    }\r\n    fun b() {}\r\n}\r\n"
        let result = parser.parse(path: "Windows.kt", source: source)
        let block = try #require(result.blocks.first { $0.typeName == "Windows" })
        #expect(block.methods.map(signature) == ["a() -> Int [2-4]", "b() [5-5]"])
    }
}

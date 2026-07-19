import Testing
import SkeletonIndexCore
import SkeletonSwiftParser
import SkeletonKotlinParser
import SkeletonTypeScriptParser
import SkeletonGoParser
import SkeletonZigParser
import SkeletonRustParser
import SkeletonCppParser
import SkeletonPythonParser
import SkeletonJavaParser

private struct LanguageCase {
    let parser: any SkeletonParser
    let path: String
    let source: String
    let methodName: String
}

@Test("all supported languages produce trap fingerprints from AST method ranges")
func allLanguagesProduceTrapFingerprints() {
    let cases: [LanguageCase] = [
        LanguageCase(
            parser: SwiftSkeletonParser(),
            path: "Service.swift",
            source: """
            struct Service {
                func run(value: Int) -> Int { fatalError("pending") }
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: KotlinSkeletonParser(),
            path: "Service.kt",
            source: """
            class Service {
                fun run(value: Int): Int { TODO("pending") }
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: TypeScriptSkeletonParser(),
            path: "Service.ts",
            source: """
            class Service {
                run(value: number): number { throw new NotImplementedError("pending"); }
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: GoSkeletonParser(),
            path: "service.go",
            source: """
            package service
            type Service struct {}
            func (service *Service) Run(value int) int { panic("pending") }
            """,
            methodName: "Run"
        ),
        LanguageCase(
            parser: ZigSkeletonParser(),
            path: "service.zig",
            source: """
            const Service = struct {
                pub fn run(value: i32) i32 { @panic("pending"); }
            };
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: RustSkeletonParser(),
            path: "service.rs",
            source: """
            struct Service;
            impl Service {
                fn run(value: i32) -> i32 { panic!("pending"); }
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: CppSkeletonParser(),
            path: "service.cpp",
            source: """
            class Service {
            public:
                int run(int value) { std::abort(); }
            };
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: PythonSkeletonParser(),
            path: "service.py",
            source: """
            class Service:
                def run(self, value: int) -> int:
                    raise NotImplementedError("pending")
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: JavaSkeletonParser(),
            path: "Service.java",
            source: """
            class Service {
                int run(int value) { throw new UnsupportedOperationException("pending"); }
            }
            """,
            methodName: "run"
        ),
    ]

    for languageCase in cases {
        let parsed = languageCase.parser.parse(path: languageCase.path, source: languageCase.source)
        let analysis = DefaultImplementationAnalyzer().analyze(
            path: languageCase.path,
            blocks: parsed.blocks,
            source: languageCase.source,
            language: languageCase.parser.languageName
        )
        let method = analysis.methods.first { $0.methodName == languageCase.methodName }
        let finding = analysis.findings.first {
            $0.methodName == languageCase.methodName && $0.reason == .trap
        }

        #expect(method != nil, "Missing method for \(languageCase.parser.languageName)")
        #expect(method?.fingerprint.bodyState == .concrete)
        #expect(method?.fingerprint.terminalBehaviors.contains(.traps) == true)
        #expect(finding?.certainty == .definite)
    }
}

@Test("abstract requirements remain body-absent and unflagged")
func abstractRequirementsRemainUnflagged() {
    let cases: [LanguageCase] = [
        LanguageCase(
            parser: SwiftSkeletonParser(),
            path: "Requirement.swift",
            source: """
            protocol Requirement {
                func run(value: Int) -> Int
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: KotlinSkeletonParser(),
            path: "Requirement.kt",
            source: """
            interface Requirement {
                fun run(value: Int): Int
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: TypeScriptSkeletonParser(),
            path: "Requirement.ts",
            source: """
            interface Requirement {
                run(value: number): number;
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: GoSkeletonParser(),
            path: "requirement.go",
            source: """
            package requirement
            type Requirement interface {
                Run(value int) int
            }
            """,
            methodName: "Run"
        ),
        LanguageCase(
            parser: RustSkeletonParser(),
            path: "requirement.rs",
            source: """
            trait Requirement {
                fn run(value: i32) -> i32;
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: CppSkeletonParser(),
            path: "requirement.hpp",
            source: """
            class Requirement {
            public:
                virtual int run(int value) = 0;
            };
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: JavaSkeletonParser(),
            path: "Requirement.java",
            source: """
            interface Requirement {
                int run(int value);
            }
            """,
            methodName: "run"
        ),
        LanguageCase(
            parser: PythonSkeletonParser(),
            path: "requirement.py",
            source: """
            from abc import ABC, abstractmethod

            class Requirement(ABC):
                @abstractmethod
                def run(self, value: int) -> int:
                    pass
            """,
            methodName: "run"
        ),
    ]

    for languageCase in cases {
        let parsed = languageCase.parser.parse(path: languageCase.path, source: languageCase.source)
        let analysis = DefaultImplementationAnalyzer().analyze(
            path: languageCase.path,
            blocks: parsed.blocks,
            source: languageCase.source,
            language: languageCase.parser.languageName
        )
        let method = analysis.methods.first { $0.methodName == languageCase.methodName }

        if languageCase.parser.languageName == "cpp" && method == nil {
            #expect(!analysis.findings.contains { $0.methodName == languageCase.methodName })
            continue
        }

        #expect(method != nil, "Missing requirement for \(languageCase.parser.languageName)")
        #expect(method?.fingerprint.bodyState == .absent)
        #expect(!analysis.findings.contains { $0.methodName == languageCase.methodName })
    }
}

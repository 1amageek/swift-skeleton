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

private struct EvidenceCase {
    let parser: any SkeletonParser
    let path: String
    let source: String
    let methodName: String
}

private func analyze(_ evidenceCase: EvidenceCase) -> (
    method: MethodImplementationAnalysis?,
    findings: [ImplementationFinding],
    evidence: MethodSyntaxEvidence?
) {
    let parsed = evidenceCase.parser.parse(path: evidenceCase.path, source: evidenceCase.source)
    let analysis = DefaultImplementationAnalyzer().analyze(
        path: evidenceCase.path,
        blocks: parsed.blocks,
        source: evidenceCase.source,
        language: evidenceCase.parser.languageName,
        syntaxEvidence: parsed.methodSyntaxEvidence
    )
    return (
        analysis.methods.first { $0.methodName == evidenceCase.methodName },
        analysis.findings.filter { $0.methodName == evidenceCase.methodName },
        parsed.methodSyntaxEvidence.first { $0.methodName == evidenceCase.methodName }
    )
}

@Test("calls and traps inside local declarations are method evidence")
func localDeclarationInitializersAreEvidence() {
    let cases: [EvidenceCase] = [
        EvidenceCase(
            parser: SwiftSkeletonParser(), path: "Service.swift",
            source: """
            struct Service {
                func run(value: Int) -> Int {
                    let result: Int = fatalError("pending")
                    return result
                }
            }
            """,
            methodName: "run"),
        EvidenceCase(
            parser: KotlinSkeletonParser(), path: "Service.kt",
            source: """
            class Service {
                fun run(value: Int): Int {
                    val result: Int = TODO("pending")
                    return result
                }
            }
            """,
            methodName: "run"),
        EvidenceCase(
            parser: TypeScriptSkeletonParser(), path: "Service.ts",
            source: """
            class Service {
                run(value: number): number {
                    const result = fatalError("pending");
                    return result;
                }
            }
            """,
            methodName: "run"),
        EvidenceCase(
            parser: RustSkeletonParser(), path: "service.rs",
            source: """
            struct Service {}
            impl Service {
                fn run(&self, value: i32) -> i32 {
                    let result = unimplemented!();
                    result
                }
            }
            """,
            methodName: "run"),
        EvidenceCase(
            parser: GoSkeletonParser(), path: "service.go",
            source: """
            package service
            type Service struct{}
            func (s *Service) Run(value int) int {
                result := panic("pending")
                return result
            }
            """,
            methodName: "Run"),
        EvidenceCase(
            parser: JavaSkeletonParser(), path: "Service.java",
            source: """
            class Service {
                int run(int value) {
                    int result = todo("pending");
                    return result;
                }
            }
            """,
            methodName: "run"),
        EvidenceCase(
            parser: CppSkeletonParser(), path: "service.hpp",
            source: """
            class Service {
            public:
                int run(int value) {
                    int result = abort();
                    return result;
                }
            };
            """,
            methodName: "run"),
        EvidenceCase(
            parser: ZigSkeletonParser(), path: "service.zig",
            source: """
            const Service = struct {
                pub fn run(self: Service, value: u32) u32 {
                    const result = unreachable_value(@panic("pending"));
                    return result;
                }
            };
            """,
            methodName: "run"),
    ]

    for evidenceCase in cases {
        let language = evidenceCase.parser.languageName
        let result = analyze(evidenceCase)
        #expect(result.evidence != nil, "Missing AST evidence for \(language)")
        #expect(!(result.evidence?.trapCalls.isEmpty ?? true), "Missing trap call for \(language)")
        #expect(
            result.findings.contains { $0.reason == .trap },
            "Missing trap finding for \(language)")
    }
}

@Test("a local declaration that calls with the parameter is not a constant stub")
func localCallIsObservableWork() {
    let result = analyze(EvidenceCase(
        parser: SwiftSkeletonParser(), path: "Service.swift",
        source: """
        struct Service {
            func run(value: Int) -> Int {
                let stored = persist(value)
                return 0
            }
        }
        """,
        methodName: "run"))

    #expect(result.method?.fingerprint.callTargets == ["persist"])
    #expect(result.method?.fingerprint.parameterReads == ["value"])
    #expect(result.findings.isEmpty)
}

@Test("writes to state outside the method count as observable work")
func externalWritesAreObservable() {
    let swiftSource = """
        final class Counter {
            var count = 0
            func increment() {
                count += 1
            }
            func scratch() {
                var local = 0
                local += 1
            }
        }
        extension Counter {
            func reset() {
                count = 0
            }
        }
        """
    let increment = analyze(EvidenceCase(
        parser: SwiftSkeletonParser(), path: "Counter.swift", source: swiftSource, methodName: "increment"))
    let scratch = analyze(EvidenceCase(
        parser: SwiftSkeletonParser(), path: "Counter.swift", source: swiftSource, methodName: "scratch"))
    let reset = analyze(EvidenceCase(
        parser: SwiftSkeletonParser(), path: "Counter.swift", source: swiftSource, methodName: "reset"))

    #expect(increment.evidence?.externalWriteTargets == ["count"])
    #expect(increment.method?.fingerprint.stateWrites == ["count"])
    #expect(!increment.findings.contains { $0.reason == .noOperation })
    #expect(!reset.findings.contains { $0.reason == .noOperation })
    #expect(scratch.evidence?.externalWriteTargets == [])
    #expect(scratch.findings.contains { $0.reason == .noOperation })

    let typeScript = analyze(EvidenceCase(
        parser: TypeScriptSkeletonParser(), path: "Counter.ts",
        source: """
        class Counter {
            increment(): void {
                this.count += 1;
            }
        }
        """,
        methodName: "increment"))
    #expect(typeScript.evidence?.externalWriteTargets == ["count"])
    #expect(!typeScript.findings.contains { $0.reason == .noOperation })

    let python = analyze(EvidenceCase(
        parser: PythonSkeletonParser(), path: "counter.py",
        source: """
        class Counter:
            def increment(self):
                self.count += 1

            def scratch(self):
                items = []
                items.append(1)
                total = 0
                total += 1
        """,
        methodName: "increment"))
    #expect(python.evidence?.externalWriteTargets == ["count"])
    #expect(!python.findings.contains { $0.reason == .noOperation })
}

@Test(
    "method lookup scales linearly with the number of methods",
    .timeLimit(.minutes(1))
)
func methodLookupScalesLinearly() {
    var source = "struct Large {\n"
    for index in 0..<4_000 {
        source += "    func method\(index)(value: Int) -> Int {\n        return value + \(index)\n    }\n"
    }
    source += "}\n"

    let parsed = SwiftSkeletonParser().parse(path: "Large.swift", source: source)

    #expect(parsed.blocks.first?.methods.count == 4_000)
    #expect(parsed.methodSyntaxEvidence.count == 4_000)
}

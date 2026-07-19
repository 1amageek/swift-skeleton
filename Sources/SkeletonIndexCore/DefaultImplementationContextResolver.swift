import Foundation

public struct DefaultImplementationContextResolver: ImplementationContextResolving, Sendable {
    public init() {}

    public func resolve(
        files: [String: ParsedFile],
        sources: [String: String]
    ) -> [String: ParsedFile] {
        let productionSources = sources.filter { !isNonProduction(path: $0.key) }
        var resolvedFiles: [String: ParsedFile] = [:]

        for path in files.keys.sorted() {
            guard let file = files[path] else {
                continue
            }
            let nonProduction = isNonProduction(path: path)
            let source = sources[path] ?? ""
            var resolvedMethods: [MethodImplementationAnalysis] = []
            var findings = nonProduction ? [] : file.implementationAnalysis.findings

            for method in file.implementationAnalysis.methods {
                let binding = implementationBinding(
                    typeName: method.typeName,
                    nonProduction: nonProduction
                )
                let reachability = productionReachability(
                    method: method,
                    source: source,
                    productionSources: productionSources,
                    nonProduction: nonProduction
                )
                let fingerprint = method.fingerprint.resolving(
                    reachability: reachability,
                    binding: binding
                )
                resolvedMethods.append(method.resolving(fingerprint: fingerprint))

                if reachability == .unreferenced {
                    findings.append(ImplementationFinding(
                        scope: .method,
                        typeName: method.typeName,
                        methodName: method.methodName,
                        range: method.range,
                        certainty: .suspicious,
                        domain: .dead,
                        reason: .dead
                    ))
                }
            }

            if !nonProduction {
                findings.append(contentsOf: wiringFindings(
                    file: file,
                    path: path,
                    productionSources: productionSources
                ))
            }

            let analysis = FileImplementationAnalysis(
                language: file.implementationAnalysis.language,
                methods: resolvedMethods,
                findings: uniqueFindings(findings)
            )
            resolvedFiles[path] = file.replacing(implementationAnalysis: analysis)
        }

        return resolvedFiles
    }

    private func productionReachability(
        method: MethodImplementationAnalysis,
        source: String,
        productionSources: [String: String],
        nonProduction: Bool
    ) -> ImplementationFingerprint.ProductionReachability {
        if nonProduction {
            return .nonProduction
        }
        let methodSource = sourceSlice(source: source, range: method.range)
        guard isExplicitlyPrivate(methodSource: methodSource) else {
            return .external
        }
        let references = productionSources.values.reduce(0) {
            $0 + rawIdentifierCount(method.methodName, in: $1)
        }
        return references > 1 ? .referenced : .unreferenced
    }

    private func implementationBinding(
        typeName: String,
        nonProduction: Bool
    ) -> ImplementationFingerprint.ImplementationBinding {
        if nonProduction {
            return .testOnly
        }
        return isFakeLike(typeName: typeName) ? .fakeLike : .production
    }

    private func wiringFindings(
        file: ParsedFile,
        path: String,
        productionSources: [String: String]
    ) -> [ImplementationFinding] {
        var findings: [ImplementationFinding] = []
        for block in file.blocks where isFakeLike(typeName: block.typeName) {
            let references = productionSources.reduce(0) { partial, entry in
                let count = identifierCount(block.typeName, in: entry.value)
                if entry.key == path {
                    return partial + max(0, count - 1)
                }
                return partial + count
            }
            if references > 0 {
                findings.append(ImplementationFinding(
                    scope: .type,
                    typeName: block.typeName,
                    methodName: nil,
                    range: block.range,
                    certainty: .suspicious,
                    domain: .wire,
                    reason: .wire
                ))
            }
        }
        return findings
    }

    private func isNonProduction(path: String) -> Bool {
        let normalized = "/" + path.lowercased().replacingOccurrences(of: "\\", with: "/") + "/"
        let components = [
            "/test/", "/tests/", "/testing/", "/fixture/", "/fixtures/", "/preview/", "/previews/",
            "/example/", "/examples/", "/sample/", "/samples/", "/generated/", "/mocks/", "/stubs/",
        ]
        return components.contains { normalized.contains($0) } ||
            normalized.contains("test.") || normalized.contains("tests.")
    }

    private func isFakeLike(typeName: String) -> Bool {
        let normalized = typeName.lowercased()
        let markers = ["fake", "mock", "stub", "preview", "dummy", "inmemory"]
        return markers.contains { normalized.contains($0) }
    }

    private func isExplicitlyPrivate(methodSource: String) -> Bool {
        let signature = methodSource.split(separator: "{", maxSplits: 1).first.map(String.init) ?? methodSource
        let identifiers = Set(identifierTokens(in: signature))
        return identifiers.contains("private") || identifiers.contains("fileprivate")
    }

    private func sourceSlice(source: String, range: SourceRange) -> String {
        guard let startLine = range.startLine else {
            return ""
        }
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard startLine > 0, startLine <= lines.count else {
            return ""
        }
        let endLine = min(max(range.endLine ?? startLine, startLine), lines.count)
        return lines[(startLine - 1)..<endLine].joined(separator: "\n")
    }

    private func identifierCount(_ identifier: String, in source: String) -> Int {
        identifierTokens(in: source).filter { $0 == identifier }.count
    }

    private func rawIdentifierCount(_ identifier: String, in source: String) -> Int {
        rawIdentifierTokens(in: source).filter { $0 == identifier }.count
    }

    private func identifierTokens(in source: String) -> [String] {
        rawIdentifierTokens(in: codeOnlySource(source))
    }

    private func rawIdentifierTokens(in source: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in source {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func codeOnlySource(_ source: String) -> String {
        enum State {
            case code
            case lineComment
            case blockComment
            case string(Character)
        }

        let characters = Array(source)
        var output = Array(repeating: Character(" "), count: characters.count)
        var state = State.code
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : "\0"
            switch state {
            case .code:
                if character == "/" && next == "/" {
                    state = .lineComment
                    index += 1
                } else if character == "/" && next == "*" {
                    state = .blockComment
                    index += 1
                } else if character == "#" {
                    state = .lineComment
                } else if character == "\"" || character == "'" || character == "`" {
                    state = .string(character)
                } else {
                    output[index] = character
                }
            case .lineComment:
                if character == "\n" {
                    output[index] = character
                    state = .code
                }
            case .blockComment:
                if character == "*" && next == "/" {
                    state = .code
                    index += 1
                } else if character == "\n" {
                    output[index] = character
                }
            case .string(let quote):
                if character == "\\" {
                    index += 1
                } else if character == quote {
                    state = .code
                } else if character == "\n" {
                    output[index] = character
                }
            }
            index += 1
        }
        return String(output)
    }

    private func uniqueFindings(_ findings: [ImplementationFinding]) -> [ImplementationFinding] {
        var seen: Set<String> = []
        return findings.filter {
            let key = "\($0.scope.rawValue)|\($0.typeName)|\($0.methodName ?? "")|\($0.range.startLine ?? 0)|\($0.reason.rawValue)"
            return seen.insert(key).inserted
        }
    }
}

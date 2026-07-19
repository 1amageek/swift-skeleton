import Foundation
import Testing

@Test(.timeLimit(.minutes(1)))
func cliSkeletonQueryAndFiltersEndToEnd() async throws {
    let projectRoot = try makeTemporaryProject(files: [
        "Sources/App/Model.swift": """
        struct User {
            let id: String
            var name: String

            func displayName(prefix: String) -> String {
                prefix + name
            }
        }

        actor UserStore {
            func load(id: String) -> User {
                User(id: id, name: id)
            }
        }

        struct Placeholder {
            func load(id: String) -> User {
                fatalError("pending")
            }
        }
        """,
        "Sources/App/Other.py": """
        class PythonOnly:
            def value(self) -> str:
                return "python"
        """,
    ])
    defer { removeTemporaryProject(projectRoot) }

    let skeleton = try await runSkltn([
        "skeleton",
        projectRoot,
        "--language",
        "swift",
    ])
    #expect(skeleton.exitCode == 0)
    #expect(skeleton.stdout.contains("struct User [Sources/App/Model.swift:1-8]"))
    #expect(skeleton.stdout.contains("actor UserStore [Sources/App/Model.swift:10-14]"))
    #expect(skeleton.stdout.contains("displayName(String) -> String [5-7]"))
    #expect(!skeleton.stdout.contains("PythonOnly"))

    let actorHeaders = try await runSkltn([
        "skeleton",
        projectRoot,
        "--language",
        "swift",
        "--kind",
        "actor",
        "--headers-only",
    ])
    #expect(actorHeaders.exitCode == 0)
    #expect(actorHeaders.stdout.contains("actor UserStore [Sources/App/Model.swift:10-14]"))
    #expect(!actorHeaders.stdout.contains("struct User"))
    #expect(!actorHeaders.stdout.contains("methods:"))

    let structHeaders = try await runSkltn([
        "skeleton",
        projectRoot,
        "--language",
        "swift",
        "--kind",
        "struct",
        "--headers-only",
    ])
    #expect(structHeaders.exitCode == 0)
    #expect(structHeaders.stdout.contains("struct Placeholder [Sources/App/Model.swift:16-20] [impl:body]"))
    #expect(!structHeaders.stdout.contains("[impl!:trap]"))

    let query = try await runSkltn([
        "query",
        projectRoot,
        "--q",
        "displayName",
        "--language",
        "swift",
        "--limit",
        "5",
    ])
    #expect(query.exitCode == 0)
    #expect(query.stdout.contains("struct User [Sources/App/Model.swift:1-8]"))

    let status = try await runSkltn([
        "status",
        projectRoot,
        "--language",
        "swift",
    ])
    #expect(status.exitCode == 0)
    #expect(status.stdout.contains("files_indexed: 1"))
    #expect(status.stdout.contains("parse_error_files: 0"))
}

@Test(.timeLimit(.minutes(1)))
func cliDiagnosticsAndFilesEndToEnd() async throws {
    let projectRoot = try makeTemporaryProject(files: [
        "Good.swift": """
        enum Good {
            case ok
        }
        """,
        "Broken.swift": """
        struct Broken {
            func unfinished(
        """,
    ])
    defer { removeTemporaryProject(projectRoot) }

    let diagnostics = try await runSkltn([
        "diagnostics",
        projectRoot,
        "--language",
        "swift",
    ])
    #expect(diagnostics.exitCode == 0)
    #expect(diagnostics.stdout.contains("parse_error: Broken.swift"))

    let files = try await runSkltn([
        "files",
        projectRoot,
        "--language",
        "swift",
    ])
    #expect(files.exitCode == 0)
    #expect(files.stdout.split(separator: "\n").map(String.init) == ["Broken.swift", "Good.swift"])
}

@Test(.timeLimit(.minutes(1)))
func daemonJsonRPCEndToEnd() async throws {
    let projectRoot = try makeTemporaryProject(files: [
        "Library.swift": """
        protocol Library {
            func find(title: String) -> String?
        }
        """,
    ])
    defer { removeTemporaryProject(projectRoot) }

    let request = """
    {"jsonrpc":"2.0","id":1,"method":"index.open","params":{"project_root":"\(projectRoot)","languages":["swift"]}}
    {"jsonrpc":"2.0","id":2,"method":"index.query","params":{"project_id":"__missing__","q":"Library","limit":5}}

    """
    let response = try await runSkltn(["daemon"], stdin: request)
    #expect(response.exitCode == 0)
    #expect(response.stdout.contains(#""id":1"#))
    #expect(response.stdout.contains(#""files_indexed":1"#))
    #expect(response.stdout.contains(#""id":2"#))
    #expect(response.stdout.contains(#""error""#))
}

@Test(.timeLimit(.minutes(1)))
func cliLanguagesEndToEnd() async throws {
    let result = try await runSkltn(["languages"])
    #expect(result.exitCode == 0)

    let languages = Set(result.stdout.split(separator: "\n").map(String.init))
    #expect(languages.contains("swift"))
    #expect(languages.contains("python"))
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private enum E2EError: Error, CustomStringConvertible {
    case executableNotFound(String)
    case timedOut([String])

    var description: String {
        switch self {
        case .executableNotFound(let path):
            "skltn executable not found at \(path)"
        case .timedOut(let arguments):
            "skltn timed out: \(arguments.joined(separator: " "))"
        }
    }
}

private func runSkltn(
    _ arguments: [String],
    stdin: String? = nil,
    timeoutSeconds: Int = 5
) async throws -> CommandResult {
    let executableURL = try skltnExecutableURL()
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    if let stdin {
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        try process.run()
        if let data = stdin.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        try stdinPipe.fileHandleForWriting.close()
    } else {
        try process.run()
    }

    let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
    while process.isRunning && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }

    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        throw E2EError.timedOut(arguments)
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return CommandResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}

private func skltnExecutableURL() throws -> URL {
    let root = projectRootURL()
    let candidates = [
        root.appendingPathComponent(".build/debug/skltn"),
        root.appendingPathComponent(".build/arm64-apple-macosx/debug/skltn"),
        root.appendingPathComponent(".build/x86_64-apple-macosx/debug/skltn"),
    ]

    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
    }

    throw E2EError.executableNotFound(candidates.map(\.path).joined(separator: ", "))
}

private func projectRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeTemporaryProject(files: [String: String]) throws -> String {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-skeleton-e2e-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    for (path, content) in files {
        let fileURL = rootURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    return rootURL.path
}

private func removeTemporaryProject(_ path: String) {
    do {
        try FileManager.default.removeItem(atPath: path)
    } catch {
    }
}

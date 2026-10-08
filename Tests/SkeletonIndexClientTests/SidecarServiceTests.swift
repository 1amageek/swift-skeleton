import Foundation
import SkeletonIndexClient
import SkeletonIndexCore
import SkeletonSwiftParser
import Testing

@Test("a missing sidecar executable is a thrown error", .timeLimit(.minutes(1)))
func missingExecutableThrows() async {
  let service = SidecarService(executablePath: "skltn-missing-\(UUID().uuidString)")

  await #expect(throws: SkeletonError.self) {
    _ = try await service.status(projectID: "unused")
  }
}

@Test("a daemon that exits fails requests without terminating the host", .timeLimit(.minutes(1)))
func exitedDaemonFailsRequests() async {
  let service = SidecarService(executablePath: "/bin/sh", arguments: ["-c", "exit 3"])

  for _ in 0..<5 {
    await #expect(throws: SkeletonError.self) {
      _ = try await service.status(projectID: "unused")
    }
  }
}

@Test("an unresponsive daemon times out", .timeLimit(.minutes(1)))
func unresponsiveDaemonTimesOut() async {
  let service = SidecarService(
    executablePath: "/bin/sh",
    arguments: ["-c", "cat > /dev/null"],
    requestTimeout: .milliseconds(300)
  )

  await #expect(throws: SkeletonError.invalidResponse("sidecar request timed out: index.status")) {
    _ = try await service.status(projectID: "unused")
  }
  await service.shutdown()
}

@Test("cancelling the caller cancels a pending request", .timeLimit(.minutes(1)))
func cancellationStopsWaiting() async {
  let service = SidecarService(
    executablePath: "/bin/sh",
    arguments: ["-c", "cat > /dev/null"],
    requestTimeout: .seconds(60)
  )
  let request = Task {
    try await service.status(projectID: "unused")
  }
  do {
    try await Task.sleep(for: .milliseconds(200))
  } catch {
    Issue.record("test sleep was cancelled: \(error)")
  }
  request.cancel()

  await #expect(throws: CancellationError.self) {
    _ = try await request.value
  }
  await service.shutdown()
}

@Test("sidecar and embedded services return the same results and errors", .timeLimit(.minutes(1)))
func sidecarMatchesEmbedded() async throws {
  let projectRoot = try makeClientProject(files: [
    "Library.swift": """
    public struct Library {
        public func find(title: String) -> String? {
            fatalError("pending")
        }
        func reindex() {}
    }
    """
  ])
  defer { removeClientProject(projectRoot) }

  let sidecar = SidecarService(executablePath: try skltnExecutablePath())
  let embedded = EmbeddedService(parsers: [SwiftSkeletonParser()])

  let sidecarOpen = try await sidecar.open(projectRoot: projectRoot, languages: ["swift"])
  let embeddedOpen = try await embedded.open(projectRoot: projectRoot, languages: ["swift"])
  #expect(sidecarOpen.status.filesIndexed == embeddedOpen.status.filesIndexed)

  let options = SkeletonRenderOptions(accessBoundary: .public, kinds: ["STRUCT"], headersOnly: false)
  let sidecarText = try await sidecar.getSkeleton(
    projectID: sidecarOpen.projectID, path: nil, options: options)
  let embeddedText = try await embedded.getSkeleton(
    projectID: embeddedOpen.projectID, path: nil, options: options)
  #expect(sidecarText == embeddedText)
  #expect(sidecarText.text.contains("find(String) -> String? [2-4] [impl!:trap]"))

  let sidecarHits = try await sidecar.query(projectID: sidecarOpen.projectID, q: "find", limit: 5)
  let embeddedHits = try await embedded.query(projectID: embeddedOpen.projectID, q: "find", limit: 5)
  #expect(sidecarHits == embeddedHits)

  await #expect(throws: SkeletonError.projectNotFound("missing")) {
    _ = try await sidecar.status(projectID: "missing")
  }
  await #expect(throws: SkeletonError.projectNotFound("missing")) {
    _ = try await embedded.status(projectID: "missing")
  }

  await sidecar.shutdown()
  let reopened = try await sidecar.open(projectRoot: projectRoot, languages: ["swift"])
  #expect(reopened.status.filesIndexed == 1)
  await sidecar.shutdown()
}

// MARK: - Helpers

private func skltnExecutablePath() throws -> String {
  if let configured = ProcessInfo.processInfo.environment["SKLTN_E2E_EXECUTABLE"], !configured.isEmpty {
    return configured
  }
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let candidates = [
    ".build/debug/skltn",
    ".build/arm64-apple-macosx/debug/skltn",
    ".build/x86_64-apple-macosx/debug/skltn",
  ].map { root.appendingPathComponent($0).path }
  guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
    throw SkeletonError.invalidResponse("skltn executable not built: \(candidates.joined(separator: ", "))")
  }
  return path
}

private func makeClientProject(files: [String: String]) throws -> String {
  let rootURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("swift-skeleton-client-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  for (name, content) in files {
    try content.write(to: rootURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
  }
  return rootURL.standardizedFileURL.path
}

private func removeClientProject(_ path: String) {
  do {
    try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
  } catch {
    // Temporary directory cleanup does not affect the asserted behavior.
  }
}

import Foundation
import SkeletonIndexCore

public struct SwiftPMProjectStructureResolver: ProjectStructureResolving, Sendable {
  private let timeoutSeconds: TimeInterval

  public init(timeoutSeconds: TimeInterval = 15) {
    self.timeoutSeconds = timeoutSeconds
  }

  public func resolve(scopeRoot: String) throws -> ProjectStructure? {
    let scopeURL = URL(fileURLWithPath: scopeRoot).standardizedFileURL
    guard let packageRoot = packageRoot(startingAt: scopeURL) else {
      return nil
    }
    let data = try dumpPackage(at: packageRoot)
    let manifest: DumpPackage
    do {
      manifest = try JSONDecoder().decode(DumpPackage.self, from: data)
    } catch {
      throw SkeletonError.manifestEvaluationFailed("invalid dump-package response")
    }

    let targetIDs = Dictionary(
      uniqueKeysWithValues: manifest.targets.map { target in
        (target.name, unitID(for: target.name))
      })
    let units = manifest.targets.map { target -> ProjectUnit in
      let dependencies = target.dependencies.map { dependency in
        ProjectUnitDependency(
          name: dependency.name,
          localUnitID: dependency.canReferenceLocalTarget ? targetIDs[dependency.name] : nil
        )
      }
      return ProjectUnit(
        id: unitID(for: target.name),
        name: target.name,
        moduleName: moduleName(for: target.name),
        displayKind: "module",
        kind: projectUnitKind(for: target.type),
        sourceRoots: sourceRoots(for: target, packageRoot: packageRoot),
        dependencies: dependencies
      )
    }
    return ProjectStructure(
      projectRoot: packageRoot.path,
      packageIdentity: manifest.name,
      units: units
    )
  }

  private func packageRoot(startingAt scopeURL: URL) -> URL? {
    var isDirectory: ObjCBool = false
    let start: URL
    if FileManager.default.fileExists(atPath: scopeURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      start = scopeURL
    } else {
      start = scopeURL.deletingLastPathComponent()
    }

    var candidate = start
    while true {
      let manifest = candidate.appendingPathComponent("Package.swift")
      if FileManager.default.fileExists(atPath: manifest.path) {
        return candidate
      }
      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path {
        return nil
      }
      candidate = parent
    }
  }

  private func dumpPackage(at packageRoot: URL) throws -> Data {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
      .appendingPathComponent(
        "skltn-manifest-\(UUID().uuidString.lowercased())",
        isDirectory: true
      )
    try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer {
      do {
        try fileManager.removeItem(at: temporaryRoot)
      } catch {
        // Temporary cleanup failure does not change manifest resolution.
      }
    }

    let outputURL = temporaryRoot.appendingPathComponent("stdout.json")
    let errorURL = temporaryRoot.appendingPathComponent("stderr.txt")
    guard fileManager.createFile(atPath: outputURL.path, contents: nil),
      fileManager.createFile(atPath: errorURL.path, contents: nil)
    else {
      throw SkeletonError.manifestEvaluationFailed("failed to create manifest output files")
    }

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "swift",
      "package",
      "dump-package",
      "--package-path",
      packageRoot.path,
    ]
    process.standardOutput = outputHandle
    process.standardError = errorHandle

    do {
      try process.run()
    } catch {
      try outputHandle.close()
      try errorHandle.close()
      throw SkeletonError.manifestEvaluationFailed("failed to launch swift package")
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
      try outputHandle.close()
      try errorHandle.close()
      throw SkeletonError.manifestEvaluationFailed("swift package dump-package timed out")
    }

    try outputHandle.close()
    try errorHandle.close()
    guard process.terminationStatus == 0 else {
      let errorData = try Data(contentsOf: errorURL)
      let message = String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let message, !message.isEmpty {
        throw SkeletonError.manifestEvaluationFailed(message)
      }
      throw SkeletonError.manifestEvaluationFailed("swift package dump-package failed")
    }
    return try Data(contentsOf: outputURL)
  }

  private func sourceRoots(for target: DumpTarget, packageRoot: URL) -> [String] {
    let kind = projectUnitKind(for: target.type)
    if kind == .binary || kind == .system {
      return []
    }
    let relativePath: String
    if let path = target.path, !path.isEmpty {
      relativePath = path
    } else {
      switch kind {
      case .test:
        relativePath = "Tests/\(target.name)"
      case .plugin:
        relativePath = "Plugins/\(target.name)"
      case .regular, .executable, .macro:
        relativePath = "Sources/\(target.name)"
      case .system, .binary, .unknown:
        return []
      }
    }
    let root = packageRoot.appendingPathComponent(relativePath).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return []
    }
    return [root.path]
  }

  private func projectUnitKind(for rawValue: String) -> ProjectUnitKind {
    switch rawValue {
    case "regular":
      .regular
    case "executable":
      .executable
    case "test":
      .test
    case "macro":
      .macro
    case "plugin":
      .plugin
    case "system":
      .system
    case "binary":
      .binary
    default:
      .unknown
    }
  }

  private func unitID(for targetName: String) -> String {
    "swiftpm:\(targetName)"
  }

  private func moduleName(for targetName: String) -> String {
    String(
      targetName.unicodeScalars.map { scalar in
        CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "_"
      })
  }
}

private struct DumpPackage: Decodable {
  let name: String
  let targets: [DumpTarget]
}

private struct DumpTarget: Decodable {
  let name: String
  let path: String?
  let type: String
  let dependencies: [DumpDependency]
}

private struct DumpDependency: Decodable {
  let name: String
  let canReferenceLocalTarget: Bool

  private enum CodingKeys: String, CodingKey {
    case byName
    case target
    case product
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.byName) {
      var values = try container.nestedUnkeyedContainer(forKey: .byName)
      name = try values.decode(String.self)
      canReferenceLocalTarget = true
      return
    }
    if container.contains(.target) {
      var values = try container.nestedUnkeyedContainer(forKey: .target)
      name = try values.decode(String.self)
      canReferenceLocalTarget = true
      return
    }
    if container.contains(.product) {
      var values = try container.nestedUnkeyedContainer(forKey: .product)
      name = try values.decode(String.self)
      canReferenceLocalTarget = false
      return
    }
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: decoder.codingPath, debugDescription: "unknown dependency kind")
    )
  }
}

import Foundation
import SkeletonIndexCore

actor IndexCache {
    private let core: SkeletonIndexCore
    private var indices: [String: ProjectIndex] = [:]

    init(core: SkeletonIndexCore) {
        self.core = core
    }

    func getSkeleton(projectRoot: String, path: String?, kinds: Set<String>?) throws -> SkeletonTextResult {
        var index = try ensureIndex(projectRoot: projectRoot)
        if let kinds {
            index = filtered(index: index, kinds: kinds)
        }
        return core.getSkeleton(index: index, path: path)
    }

    func query(projectRoot: String, q: String, limit: Int) throws -> [QueryHit] {
        let index = try ensureIndex(projectRoot: projectRoot)
        return core.query(index: index, q: q, limit: limit)
    }

    private func filtered(index: ProjectIndex, kinds: Set<String>) -> ProjectIndex {
        let filteredFiles = index.files.mapValues { parsedFile in
            let blocks = parsedFile.blocks.filter { block in
                switch block.kind {
                case .type(let name): return kinds.contains(name)
                case .extension: return kinds.contains("extension")
                }
            }
            return ParsedFile(
                path: parsedFile.path,
                blocks: blocks,
                hasParseError: parsedFile.hasParseError,
                methodSyntaxEvidence: parsedFile.methodSyntaxEvidence,
                implementationAnalysis: parsedFile.implementationAnalysis
            )
        }.filter { !$0.value.blocks.isEmpty }
        return ProjectIndex(
            projectRoot: index.projectRoot,
            files: filteredFiles,
            lastUpdateTS: index.lastUpdateTS,
            isWatching: index.isWatching
        )
    }

    private func ensureIndex(projectRoot: String) throws -> ProjectIndex {
        let key = URL(fileURLWithPath: projectRoot).standardizedFileURL.path
        if let cached = indices[key] {
            return cached
        }
        let index = try core.build(projectRoot: key)
        indices[key] = index
        return index
    }
}

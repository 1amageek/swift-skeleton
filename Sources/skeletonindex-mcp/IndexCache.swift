import Foundation
import SkeletonIndexCore

actor IndexCache {
    private let core: SkeletonIndexCore
    private var indices: [String: ProjectIndex] = [:]

    init(core: SkeletonIndexCore) {
        self.core = core
    }

    func getSkeleton(projectRoot: String, path: String?) throws -> SkeletonTextResult {
        let index = try ensureIndex(projectRoot: projectRoot)
        return core.getSkeleton(index: index, path: path)
    }

    func query(projectRoot: String, q: String, limit: Int) throws -> [QueryHit] {
        let index = try ensureIndex(projectRoot: projectRoot)
        return core.query(index: index, q: q, limit: limit)
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

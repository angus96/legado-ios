import Foundation

struct BookSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let author: String
    var coverUrl: String?
    var intro: String?
    var kind: String?
    var wordCount: String? = nil
    var lastChapter: String?
    var sourceName: String
    var sourceId: UUID
    var bookUrl: String
    var sourceCount: Int = 1

    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displayAuthor: String { author.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displaySourceName: String {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (URL(string: bookUrl)?.host ?? "未命名书源") : name
    }
}

/// 每条新结果只处理一次；补齐信息时保留行 ID 和已经展示的位置。
struct SearchResultAccumulator {
    private(set) var results: [BookSearchResult] = []
    private var indices: [String: Int] = [:]
    private var sources: [String: Set<UUID>] = [:]
    private var candidates: [String: [UUID: BookSearchResult]] = [:]
    private var sourceOrder: [String: [UUID]] = [:]

    mutating func append(_ incoming: [BookSearchResult]) {
        for item in incoming {
            guard !item.displayName.isEmpty, !item.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let key = item.displayName.lowercased() + "\u{0}" + item.displayAuthor.lowercased()
            candidates[key, default: [:]][item.sourceId] = item
            if sources[key, default: []].insert(item.sourceId).inserted {
                sourceOrder[key, default: []].append(item.sourceId)
            }
            if let index = indices[key] {
                results[index].sourceCount = sources[key]?.count ?? 1
                if results[index].coverUrl?.isEmpty != false { results[index].coverUrl = item.coverUrl }
                if results[index].intro?.isEmpty != false { results[index].intro = item.intro }
                if results[index].kind?.isEmpty != false { results[index].kind = item.kind }
                if results[index].wordCount?.isEmpty != false { results[index].wordCount = item.wordCount }
                if results[index].lastChapter?.isEmpty != false { results[index].lastChapter = item.lastChapter }
            } else {
                indices[key] = results.count
                results.append(item)
            }
        }
    }

    /// 删除或停用首个返回结果的书源时，保留同一本书的其他有效来源和列表行 ID。
    mutating func retainSources(_ available: Set<UUID>) {
        var retained: [BookSearchResult] = []
        var retainedIndices: [String: Int] = [:]
        for var result in results {
            let key = result.displayName.lowercased() + "\u{0}" + result.displayAuthor.lowercased()
            let ids = sources[key, default: []].intersection(available)
            guard !ids.isEmpty else {
                sources.removeValue(forKey: key)
                candidates.removeValue(forKey: key)
                sourceOrder.removeValue(forKey: key)
                continue
            }
            if !ids.contains(result.sourceId),
               let replacementID = sourceOrder[key]?.first(where: { ids.contains($0) }),
               let replacement = candidates[key]?[replacementID] {
                result.sourceId = replacement.sourceId
                result.sourceName = replacement.sourceName
                result.bookUrl = replacement.bookUrl
                result.coverUrl = replacement.coverUrl
                result.intro = replacement.intro
                result.kind = replacement.kind
                result.wordCount = replacement.wordCount
                result.lastChapter = replacement.lastChapter
            }
            result.sourceCount = ids.count
            sources[key] = ids
            if candidates[key]?.count != ids.count {
                candidates[key] = candidates[key]?.filter { ids.contains($0.key) }
                sourceOrder[key] = sourceOrder[key]?.filter { ids.contains($0) }
            }
            retainedIndices[key] = retained.count
            retained.append(result)
        }
        results = retained
        indices = retainedIndices
    }
}

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
    let sourceName: String
    let sourceId: UUID
    let bookUrl: String
    var sourceCount: Int = 1

    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displayAuthor: String { author.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// 每条新结果只处理一次；补齐信息时保留行 ID 和已经展示的位置。
struct SearchResultAccumulator {
    private(set) var results: [BookSearchResult] = []
    private var indices: [String: Int] = [:]
    private var sources: [String: Set<UUID>] = [:]

    mutating func append(_ incoming: [BookSearchResult]) {
        for item in incoming {
            guard !item.displayName.isEmpty, !item.bookUrl.isEmpty else { continue }
            let key = item.displayName.lowercased() + "\u{0}" + item.displayAuthor.lowercased()
            if let index = indices[key] {
                sources[key, default: []].insert(item.sourceId)
                results[index].sourceCount = sources[key]?.count ?? 1
                if results[index].coverUrl?.isEmpty != false { results[index].coverUrl = item.coverUrl }
                if results[index].intro?.isEmpty != false { results[index].intro = item.intro }
                if results[index].kind?.isEmpty != false { results[index].kind = item.kind }
                if results[index].wordCount?.isEmpty != false { results[index].wordCount = item.wordCount }
                if results[index].lastChapter?.isEmpty != false { results[index].lastChapter = item.lastChapter }
            } else {
                indices[key] = results.count
                sources[key] = [item.sourceId]
                results.append(item)
            }
        }
    }
}

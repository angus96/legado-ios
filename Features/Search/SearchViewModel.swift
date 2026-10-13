import Foundation
import CoreData

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var selectedSources: [BookSource] = []
    
    private var ruleEngine: RuleEngine = RuleEngine()
    private var searchTask: Task<Void, Never>?
    private var searchID = UUID()

    init() {
        loadDefaultSources()
    }

    private func loadDefaultSources() {
        do {
            let sources = try CoreDataStack.shared.viewContext.fetch(BookSource.fetchRequest())
            selectedSources = sources.filter { $0.enabled && $0.searchUrl != nil }
        } catch {
            selectedSources = []
        }
    }
    
    func cancelSearch() {
        searchID = UUID()
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
    
    struct SearchResult: Identifiable {
        let id = UUID()
        let name: String
        let author: String
        let coverUrl: String?
        let intro: String?
        let kind: String?
        let wordCount: String? = nil
        let lastChapter: String?
        let sourceName: String
        let sourceId: UUID
        let bookUrl: String
        var sourceCount: Int = 1
        
        var displayName: String {
            name.trimmingCharacters(in: .whitespaces)
        }
        
        var displayAuthor: String {
            author.trimmingCharacters(in: .whitespaces)
        }
    }
    
    func search(keyword: String, sources: [BookSource]) async {
        guard !keyword.isEmpty else {
            cancelSearch()
            searchResults = []
            isSearching = false
            return
        }

        searchTask?.cancel()
        let requestID = UUID()
        searchID = requestID
        searchTask = Task { [keyword] in
            guard self.searchID == requestID, !Task.isCancelled else { return }
            isSearching = true
            searchResults.removeAll()
            errorMessage = nil

            defer {
                if self.searchID == requestID {
                    isSearching = false
                    searchTask = nil
                }
            }

            let enabledSources = sources.filter { $0.enabled && $0.searchUrl != nil }
            var partialBuckets: [(Int, [SearchResult])] = []
            var sourceErrors: [(Int, String)] = []

            await ConcurrentSourceSearch.run(Array(enabledSources.enumerated())) { item -> (Int, [SearchResult], String?) in
                let (index, source) = item
                do {
                    let results = try await self.searchInSource(keyword: keyword, source: source)
                    return (index, results, nil)
                } catch is CancellationError {
                    return (index, [], nil)
                } catch {
                    let message = "\(source.bookSourceName)：\(error.localizedDescription)"
                    return (index, [], message)
                }
            } onResult: { index, results, error in
                guard !Task.isCancelled, self.searchID == requestID else { return }
                partialBuckets.append((index, results))
                if !results.isEmpty {
                    let merged = partialBuckets.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
                    self.searchResults = self.aggregateResults(merged)
                }
                if let error {
                    sourceErrors.append((index, error))
                }
            }

            guard !Task.isCancelled, self.searchID == requestID else { return }

            let merged = partialBuckets
                .sorted { $0.0 < $1.0 }
                .flatMap { $0.1 }

            searchResults = aggregateResults(merged)

            if !sourceErrors.isEmpty {
                errorMessage = sourceErrors
                    .sorted { $0.0 < $1.0 }
                    .map(\.1)
                    .joined(separator: "\n")
            }
        }

        await searchTask?.value
    }
    
    private func searchInSource(keyword: String, source: BookSource) async throws -> [SearchResult] {
        let results = try await WebBook.searchBook(source: source, key: keyword)
        
        return results.map { searchBook in
            SearchResult(
name: searchBook.name,
                author: searchBook.author,
                coverUrl: searchBook.coverUrl,
                intro: searchBook.intro,
                kind: searchBook.kind,
                lastChapter: searchBook.lastChapter,
                sourceName: source.bookSourceName,
                sourceId: source.sourceId,
                bookUrl: searchBook.bookUrl
            )
        }
    }

    private func aggregateResults(_ input: [SearchResult]) -> [SearchResult] {
        var buckets: [String: SearchResult] = [:]
        var sourceBuckets: [String: Set<UUID>] = [:]
        var order: [String] = []

        for item in input {
            let normalizedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedAuthor = item.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = normalizedAuthor.isEmpty ? normalizedName : "\(normalizedName)|\(normalizedAuthor)"

            if var existing = buckets[key] {
                var sourceSet = sourceBuckets[key] ?? []
                sourceSet.insert(item.sourceId)
                sourceBuckets[key] = sourceSet
                existing.sourceCount = sourceSet.count
                if (existing.kind?.isEmpty ?? true), let kind = item.kind, !kind.isEmpty {
existing = SearchResult(
                        name: existing.name,
                        author: existing.author,
                        coverUrl: existing.coverUrl ?? item.coverUrl,
                        intro: existing.intro ?? item.intro,
                        kind: kind,
                        lastChapter: existing.lastChapter ?? item.lastChapter,
                        sourceName: existing.sourceName,
                        sourceId: existing.sourceId,
                        bookUrl: existing.bookUrl,
                        sourceCount: existing.sourceCount
                    )
                } else {
existing = SearchResult(
                        name: existing.name,
                        author: existing.author,
                        coverUrl: existing.coverUrl ?? item.coverUrl,
                        intro: existing.intro ?? item.intro,
                        kind: existing.kind,
                        lastChapter: existing.lastChapter ?? item.lastChapter,
                        sourceName: existing.sourceName,
                        sourceId: existing.sourceId,
                        bookUrl: existing.bookUrl,
                        sourceCount: existing.sourceCount
                    )
                }
                buckets[key] = existing
            } else {
                buckets[key] = item
                sourceBuckets[key] = [item.sourceId]
                order.append(key)
            }
        }

        return order.compactMap { buckets[$0] }
    }
    
func addToBookshelf(result: SearchResult) async throws -> Book {
        let context = CoreDataStack.shared.viewContext
        
        let bookData = BookImportData(
            name: result.name,
            author: result.author,
            bookUrl: result.bookUrl,
            tocUrl: "",
            origin: result.sourceId.uuidString,
            originName: result.sourceName,
            coverUrl: result.coverUrl,
            intro: result.intro,
            latestChapterTitle: result.lastChapter
        )
        
        let book = try BookDeduplicator.importBook(bookData, context: context)
        
        let sourceRequest: NSFetchRequest<BookSource> = BookSource.fetchRequest()
        sourceRequest.fetchLimit = 1
        sourceRequest.predicate = NSPredicate(format: "sourceId == %@", result.sourceId as CVarArg)
        if let source = try? context.fetch(sourceRequest).first {
            book.source = source
        }
        
        try CoreDataStack.shared.save()
        return book
    }

    private func findBook(bookUrl: String, origin: String, in context: NSManagedObjectContext) -> Book? {
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "bookUrl == %@ AND origin == %@", bookUrl, origin)
        return try? context.fetch(request).first
    }
}

enum SearchError: LocalizedError {
    case invalidSource
    case noSearchRule
    case networkFailure
    
    var errorDescription: String? {
        switch self {
        case .invalidSource: return "书源无效"
        case .noSearchRule: return "缺少搜索规则"
        case .networkFailure: return "网络请求失败"
        }
    }
}

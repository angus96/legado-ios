import Foundation
import CoreData
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    typealias SearchResult = BookSearchResult
    typealias SearchOperation = (BookSourceSnapshot, String) async throws -> [SearchBookResult]

    @Published var searchText = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var selectedSources: [BookSource] = [] {
        didSet {
            selectionDefaults?.set(selectedSources.filter { !$0.isDeleted && $0.managedObjectContext != nil }
                .map { $0.sourceId.uuidString }, forKey: Self.selectionKey)
        }
    }
    @Published private(set) var completedSourceCount = 0
    @Published private(set) var totalSourceCount = 0
    @Published private(set) var failedSourceCount = 0
    @Published private(set) var sourceErrors: [String] = []
    @Published private(set) var hasSearched = false
    @Published private(set) var wasCancelled = false

    private let operation: SearchOperation
    private let sourceTimeout: TimeInterval
    private let selectionDefaults: UserDefaults?
    private static let selectionKey = "search.selectedSourceIDs"
    private var searchTask: Task<Void, Never>?
    private var searchID = UUID()

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext,
         sourceTimeout: TimeInterval = 12,
         selectionDefaults: UserDefaults? = .standard,
         operation: @escaping SearchOperation = { source, keyword in
             try await WebBook.searchBook(source: source, key: keyword, timeout: 12)
         }) {
        self.operation = operation
        self.sourceTimeout = sourceTimeout
        self.selectionDefaults = selectionDefaults
        let request = BookSource.fetchRequest()
        request.predicate = NSPredicate(format: "enabled == YES AND searchUrl != nil AND searchUrl != ''")
        request.sortDescriptors = [NSSortDescriptor(key: "weight", ascending: false),
                                   NSSortDescriptor(key: "respondTime", ascending: true)]
        let sources = (try? context.fetch(request)) ?? []
        if let saved = selectionDefaults?.stringArray(forKey: Self.selectionKey) {
            let selectedIDs = Set(saved)
            selectedSources = sources.filter { selectedIDs.contains($0.sourceId.uuidString) }
        } else {
            selectedSources = sources
        }
    }

    func cancelSearch() {
        searchID = UUID()
        searchTask?.cancel()
        searchTask = nil
        wasCancelled = isSearching
        isSearching = false
    }

    func clearSearch() {
        cancelSearch()
        searchText = ""
        searchResults = []
        hasSearched = false
        errorMessage = nil
        completedSourceCount = 0
        totalSourceCount = 0
        failedSourceCount = 0
        sourceErrors = []
    }

    func search(keyword: String, sources: [BookSource]) async {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { clearSearch(); return }
        cancelSearch()
        let requestID = UUID()
        searchID = requestID
        searchResults = []
        errorMessage = nil
        sourceErrors = []
        completedSourceCount = 0
        failedSourceCount = 0
        hasSearched = true
        wasCancelled = false

        // 数据库内容在所属主队列一次性拷贝，并发请求只接收普通值。
        var seen = Set<UUID>()
        let definitions = sources.filter {
            !$0.isDeleted && $0.managedObjectContext != nil && $0.enabled &&
            !($0.searchUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.sorted {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.respondTime < $1.respondTime
        }.compactMap { try? BookSourceSnapshot.capture($0) }.filter { seen.insert($0.sourceId).inserted }
        totalSourceCount = definitions.count
        guard !definitions.isEmpty else {
            errorMessage = "没有可搜索的书源，请先启用书源，再选择搜索范围。"
            return
        }
        isSearching = true
        let operation = self.operation
        let timeout = sourceTimeout
        let task = Task { [weak self] in
            var accumulator = SearchResultAccumulator()
            var completed = 0
            var failures = 0
            var errors: [String] = []
            var lastPublish: TimeInterval = 0
            await ConcurrentSourceSearch.run(definitions, limit: 12) { source -> (BookSourceSnapshot, [SearchBookResult], String?) in
                do {
                    let results = try await ConcurrentSourceSearch.withTimeout(seconds: timeout) {
                        try await operation(source, keyword)
                    }
                    return (source, results, nil)
                } catch is CancellationError {
                    return (source, [], nil)
                } catch {
                    return (source, [], "\(source.bookSourceName)：\(error.localizedDescription)")
                }
            } onResult: { source, results, error in
                guard let self, self.searchID == requestID, !Task.isCancelled else { return }
                completed += 1
                if let error {
                    failures += 1
                    if errors.count < 8 { errors.append(error) }
                }
                accumulator.append(results.map {
                    SearchResult(name: $0.name, author: $0.author, coverUrl: $0.coverUrl,
                                 intro: $0.intro, kind: $0.kind, wordCount: $0.wordCount,
                                 lastChapter: $0.lastChapter, sourceName: source.bookSourceName,
                                 sourceId: source.sourceId, bookUrl: $0.bookUrl)
                })
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastPublish >= 0.12 || completed == definitions.count ||
                    (self.searchResults.isEmpty && !accumulator.results.isEmpty) {
                    self.searchResults = accumulator.results
                    self.completedSourceCount = completed
                    self.failedSourceCount = failures
                    self.sourceErrors = errors
                    lastPublish = now
                }
            }
            guard let self, self.searchID == requestID, !Task.isCancelled else { return }
            self.searchResults = accumulator.results
            self.completedSourceCount = completed
            self.failedSourceCount = failures
            self.sourceErrors = errors
            self.isSearching = false
            self.searchTask = nil
        }
        searchTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
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

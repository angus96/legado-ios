import Foundation
import CoreData
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    typealias SearchResult = BookSearchResult
    typealias SearchOperation = (BookSourceSnapshot, String) async throws -> [SearchBookResult]

    enum SearchMode: String {
        case all
        case title
        case author
    }

    @Published var searchText = ""
    @Published var searchMode: SearchMode = .all {
        didSet {
            selectionDefaults?.set(searchMode.rawValue, forKey: Self.modeKey)
            applySearchMode()
        }
    }
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
    private static let modeKey = "search.mode"
    private var searchTask: Task<Void, Never>?
    private var searchID = UUID()
    private var unfilteredResults: [SearchResult] = []
    private var resultKeyword = ""

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext,
         sourceTimeout: TimeInterval = 12,
         selectionDefaults: UserDefaults? = .standard,
         operation: @escaping SearchOperation = { source, keyword in
             try await WebBook.searchBook(source: source, key: keyword, timeout: 12)
         }) {
        self.operation = operation
        self.sourceTimeout = sourceTimeout
        self.selectionDefaults = selectionDefaults
        searchMode = SearchMode(rawValue: selectionDefaults?.string(forKey: Self.modeKey) ?? "") ?? .all
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
        resultKeyword = ""
        publishResults([])
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
        resultKeyword = keyword
        publishResults([])
        errorMessage = nil
        sourceErrors = []
        completedSourceCount = 0
        failedSourceCount = 0
        hasSearched = true
        wasCancelled = false

        // 数据库内容在所属主队列一次性拷贝，并发请求只接收普通值。
        var seen = Set<UUID>()
        let usableSources = sources.filter {
            !$0.isDeleted && $0.managedObjectContext != nil && $0.enabled &&
            !$0.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !($0.searchUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let sourceObjects = Dictionary(usableSources.map { ($0.sourceId, $0) }, uniquingKeysWith: { first, _ in first })
        let definitions = usableSources.sorted {
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
                    return (source, [], "\(source.bookSourceName)：\(NetworkError.message(for: error))")
                }
            } onResult: { source, results, error in
                guard let self, self.searchID == requestID, !Task.isCancelled else { return }
                completed += 1
                if let error {
                    failures += 1
                    if errors.count < 8 { errors.append(error) }
                }
                if let currentSource = sourceObjects[source.sourceId],
                   !currentSource.isDeleted, currentSource.managedObjectContext != nil, currentSource.enabled {
                    let name = source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    accumulator.append(results.map {
                        SearchResult(name: $0.name, author: $0.author, coverUrl: $0.coverUrl,
                                     intro: $0.intro, kind: $0.kind, wordCount: $0.wordCount,
                                     lastChapter: $0.lastChapter, sourceName: name.isEmpty ? source.bookSourceUrl : name,
                                     sourceId: source.sourceId, bookUrl: $0.bookUrl)
                    })
                }
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastPublish >= 0.12 || completed == definitions.count ||
                    (self.unfilteredResults.isEmpty && !accumulator.results.isEmpty) {
                    accumulator.retainSources(Set(sourceObjects.compactMap { id, object in
                        !object.isDeleted && object.managedObjectContext != nil && object.enabled ? id : nil
                    }))
                    self.publishResults(accumulator.results)
                    self.completedSourceCount = completed
                    self.failedSourceCount = failures
                    self.sourceErrors = errors
                    lastPublish = now
                }
            }
            guard let self, self.searchID == requestID, !Task.isCancelled else { return }
            accumulator.retainSources(Set(sourceObjects.compactMap { id, object in
                !object.isDeleted && object.managedObjectContext != nil && object.enabled ? id : nil
            }))
            self.publishResults(accumulator.results)
            self.completedSourceCount = completed
            self.failedSourceCount = failures
            self.sourceErrors = errors
            self.isSearching = false
            self.searchTask = nil
        }
        searchTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }

    private func publishResults(_ results: [SearchResult]) {
        unfilteredResults = results
        applySearchMode()
    }

    private func applySearchMode() {
        switch searchMode {
        case .all:
            searchResults = unfilteredResults
        case .title:
            searchResults = unfilteredResults.filter {
                $0.displayName.localizedCaseInsensitiveContains(resultKeyword)
            }
        case .author:
            searchResults = unfilteredResults.filter {
                !$0.displayAuthor.isEmpty && $0.displayAuthor.localizedCaseInsensitiveContains(resultKeyword)
            }
        }
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

import Foundation
import Combine
import CoreData

struct CacheChapterItem: Identifiable {
    let id: NSManagedObjectID
    let number: Int
    let title: String
    var isCached: Bool
}

@MainActor
final class ChapterCacheViewModel: ObservableObject {
    @Published private(set) var chapters: [CacheChapterItem] = []
    @Published var selectedIDs: Set<NSManagedObjectID> = []
    @Published var startNumber = "1"
    @Published var endNumber = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isCaching = false
    @Published private(set) var isStopping = false
    @Published private(set) var completedCount = 0
    @Published private(set) var targetCount = 0
    @Published private(set) var savedCount = 0
    @Published private(set) var skippedCount = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var failures: [String] = []
    @Published private(set) var status = ""
    @Published var errorMessage: String?

    let book: Book
    private var cacheTask: Task<Void, Never>?
    private let cacheOperation: @MainActor (BookChapter, Book) async throws -> Void

    init(book: Book, cacheOperation: @escaping @MainActor (BookChapter, Book) async throws -> Void = {
        try await ChapterContentLoader.cache(chapter: $0, book: $1)
    }) {
        self.book = book
        self.cacheOperation = cacheOperation
    }

    var cachedSelectionCount: Int {
        chapters.filter { selectedIDs.contains($0.id) && $0.isCached }.count
    }

    func loadChapters() async {
        guard !isLoading, !isCaching else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard !book.isDeleted, let context = book.managedObjectContext else {
                throw CacheError.bookUnavailable
            }
            guard !book.isLocal else { throw CacheError.localBook }
            try await ChapterDirectoryUpdater.repairStoredDirectory(for: book)
            var stored = try context.fetch(BookChapter.fetchRequest(byBookId: book.bookId))
            if stored.isEmpty {
                guard let source = try BookSourceResolver.resolve(for: book) else { throw CacheError.noSource }
                let original = try BookRequestSnapshot.capture(book)
                let definition = try BookSourceSnapshot.capture(source)
                let metadata = try await WebBook.getBookInfo(source: definition, book: original)
                let directory = try await WebBook.getChapterList(source: definition, book: metadata)
                try Task.checkCancellation()
                try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                                          metadata: metadata, definition: definition, chapters: directory)
                stored = try context.fetch(BookChapter.fetchRequest(byBookId: book.bookId))
            }
            try Task.checkCancellation()
            chapters = stored.enumerated().map { position, chapter in
                CacheChapterItem(id: chapter.objectID, number: position + 1, title: chapter.title,
                                 isCached: hasCache(chapter, verifyContents: false))
            }
            selectedIDs = Set(chapters.map(\.id))
            startNumber = "1"
            endNumber = String(chapters.count)
            if chapters.isEmpty { errorMessage = "没有可缓存的章节，请先更新目录。" }
        } catch is CancellationError {
        } catch {
            errorMessage = NetworkError.message(for: error)
        }
    }

    func selectRange() {
        guard !isCaching else { return }
        guard let start = Int(startNumber), let end = Int(endNumber),
              start >= 1, end <= chapters.count, start <= end else {
            errorMessage = "请输入 1 至 \(chapters.count) 之间的章节序号，起始章节不能大于结束章节。"
            return
        }
        errorMessage = nil
        selectedIDs = Set(chapters[(start - 1)..<end].map(\.id))
    }

    func toggle(_ item: CacheChapterItem) {
        guard !isCaching else { return }
        if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
    }

    func startCaching() {
        guard !isCaching, !isLoading else { return }
        let items = chapters.filter { selectedIDs.contains($0.id) }
        guard !items.isEmpty else { return }
        do {
            let original = try BookRequestSnapshot.capture(book)
            errorMessage = nil
            status = "正在缓存"
            completedCount = 0; savedCount = 0; skippedCount = 0; failedCount = 0
            failures = []
            targetCount = items.count
            isStopping = false
            isCaching = true
            cacheTask = Task {
                await ConcurrentSourceSearch.run(items, limit: 3, operation: { item in
                    await self.cache(item, original: original)
                }, onResult: { outcome in
                    await self.record(outcome)
                })
                self.refreshCacheFlags()
                self.status = Task.isCancelled ? "缓存已停止" : (self.failedCount == 0 ? "缓存完成" : "部分章节缓存失败")
                self.isCaching = false
                self.isStopping = false
                self.cacheTask = nil
            }
        } catch { errorMessage = NetworkError.message(for: error) }
    }

    func stopCaching() {
        guard isCaching else { return }
        isStopping = true
        status = "正在停止"
        cacheTask?.cancel()
    }

    func waitForCompletion() async { await cacheTask?.value }

    private enum Outcome {
        case saved(NSManagedObjectID), skipped(NSManagedObjectID)
        case failed(String), invalidated, cancelled
    }

    private func cache(_ item: CacheChapterItem, original: BookRequestSnapshot) async -> Outcome {
        do {
            try Task.checkCancellation()
            guard !book.isDeleted, let context = book.managedObjectContext,
                  book.origin == original.origin, book.bookUrl == original.bookUrl,
                  let chapter = try context.existingObject(with: item.id) as? BookChapter,
                  !chapter.isDeleted, chapter.book === book else { return .invalidated }
            if hasCache(chapter) { return .skipped(item.id) }
            try await cacheOperation(chapter, book)
            try Task.checkCancellation()
            guard hasCache(chapter) else { throw CacheError.notSaved }
            return .saved(item.id)
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled { return .cancelled }
            return .failed("第 \(item.number) 章：\(NetworkError.message(for: error))")
        }
    }

    private func record(_ outcome: Outcome) {
        switch outcome {
        case .saved(let id):
            savedCount += 1
            markCached(id)
        case .skipped(let id):
            skippedCount += 1
            markCached(id)
        case .failed(let message):
            failedCount += 1
            if failures.count < 8 { failures.append(message) }
        case .invalidated:
            errorMessage = "书籍或目录已变化，缓存已停止。请重新打开缓存页面。"
            stopCaching()
            return
        case .cancelled:
            return
        }
        completedCount += 1
    }

    private func markCached(_ id: NSManagedObjectID) {
        if let index = chapters.firstIndex(where: { $0.id == id }) { chapters[index].isCached = true }
    }

    private func hasCache(_ chapter: BookChapter, verifyContents: Bool = true) -> Bool {
        guard !chapter.isDeleted, chapter.managedObjectContext != nil, chapter.isCached,
              let path = chapter.cachePath, !path.isEmpty else { return false }
        let file = ChapterContentLoader.cacheURL(path)
        if verifyContents {
            return (try? String(contentsOf: file, encoding: .utf8).isEmpty) == false
        }
        let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return (size ?? 0) > 0
    }

    private func refreshCacheFlags() {
        guard let context = book.managedObjectContext, !book.isDeleted else { return }
        var updated = chapters
        for index in updated.indices {
            guard let chapter = try? context.existingObject(with: updated[index].id) as? BookChapter else { continue }
            updated[index].isCached = hasCache(chapter, verifyContents: false)
        }
        chapters = updated
    }

    private enum CacheError: LocalizedError {
        case bookUnavailable, localBook, notSaved, noSource
        var errorDescription: String? {
            switch self {
            case .bookUnavailable: return "书籍已不存在。"
            case .noSource: return "找不到此书的书源，请先换源。"
            case .localBook: return "这本书已保存在本机，无需下载章节。"
            case .notSaved: return "章节未能保存到本机，请检查剩余存储空间后重试。"
            }
        }
    }
}

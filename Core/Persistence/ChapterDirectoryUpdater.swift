import CoreData

enum ChapterDirectoryUpdater {
    /// 修复已经保存的重复目录。用章节链接对应阅读位置、缓存和书签，避免因序号变化跳章。
    static func repairStoredDirectory(for book: Book) async throws {
        let original = try BookRequestSnapshot.capture(book)
        let (bookID, coordinator, isLocal) = try ManagedObjectAccess.read(book) {
            ($0.objectID, $0.managedObjectContext?.persistentStoreCoordinator, $0.isLocal)
        }
        guard !isLocal, !bookID.isTemporaryID, let coordinator else { return }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let repaired = try await context.perform { () -> Bool in
            do {
                try Task.checkCancellation()
                guard let target = try context.existingObject(with: bookID) as? Book,
                      !target.isDeleted, target.origin == original.origin, target.bookUrl == original.bookUrl else {
                    throw CancellationError()
                }
                let stored = try context.fetch(BookChapter.fetchRequest(byBookId: target.bookId))
                let input = stored.map { chapter -> WebChapter in
                    var item = WebChapter()
                    item.title = chapter.title; item.url = chapter.chapterUrl; item.index = Int(chapter.index)
                    return item
                }
                let positions = TocParser.directoryPositions(input)
                guard !positions.isEmpty,
                      positions.count != stored.count || stored.enumerated().contains(where: { Int($0.element.index) != $0.offset }) else {
                    return false
                }
                let ordered = positions.map { stored[$0] }
                let newIndices = Dictionary(ordered.enumerated().filter { !$0.element.chapterUrl.isEmpty }
                    .map { ($0.element.chapterUrl, $0.offset) }, uniquingKeysWith: { first, _ in first })
                let oldURLs = Dictionary(stored.map { ($0.index, $0.chapterUrl) }, uniquingKeysWith: { first, _ in first })
                var cached: [String: BookChapter] = [:]
                for chapter in stored where chapter.isCached && chapter.cachePath?.isEmpty == false {
                    cached[chapter.chapterUrl] = chapter
                }
                let currentIndex = oldURLs[target.durChapterIndex].flatMap { newIndices[$0] }
                    ?? ReadingProgressMapper.chapterIndex(previousIndex: Int(target.durChapterIndex),
                        previousCount: stored.count, title: target.durChapterTitle, newTitles: ordered.map(\.title))
                for (index, chapter) in ordered.enumerated() {
                    if (!chapter.isCached || chapter.cachePath?.isEmpty != false), let previous = cached[chapter.chapterUrl] {
                        chapter.isCached = previous.isCached
                        chapter.cachePath = previous.cachePath
                        chapter.contentHash = previous.contentHash
                    }
                    chapter.index = Int32(clamping: index)
                }
                let bookmarks = Bookmark.fetchRequest()
                bookmarks.predicate = NSPredicate(format: "bookId == %@", target.bookId as CVarArg)
                for bookmark in try context.fetch(bookmarks) {
                    if let url = oldURLs[bookmark.chapterIndex], let index = newIndices[url] {
                        bookmark.chapterIndex = Int32(clamping: index)
                    }
                }
                let retained = Set(ordered.map(\.objectID))
                for chapter in stored where !retained.contains(chapter.objectID) { context.delete(chapter) }
                target.totalChapterNum = Int32(clamping: ordered.count)
                target.durChapterIndex = Int32(clamping: currentIndex)
                target.durChapterTitle = ordered[currentIndex].title
                try Task.checkCancellation()
                try context.save()
                return true
            } catch {
                context.rollback()
                throw error
            }
        }
        if repaired {
            try await ManagedObjectAccess.update(book) { $0.managedObjectContext?.refresh($0, mergeChanges: true) }
        }
    }

    static func replace(
        book: Book, source: BookSource, original: BookRequestSnapshot,
        metadata: BookRequestSnapshot, definition: BookSourceSnapshot, chapters: [WebChapter]
    ) async throws {
        guard !chapters.isEmpty else { throw WebBookError.noRule("新书源未返回目录，已保留原书源") }
        let bookID = try ManagedObjectAccess.read(book) { $0.objectID }
        let sourceID = try ManagedObjectAccess.read(source) { $0.objectID }
        let coordinator = try ManagedObjectAccess.read(book) { $0.managedObjectContext?.persistentStoreCoordinator }
        guard !bookID.isTemporaryID, !sourceID.isTemporaryID, let coordinator else {
            throw ManagedObjectAccessError.unavailable
        }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let cancellation = DirectoryCancellation()
        try Task.checkCancellation()
        try await withTaskCancellationHandler(operation: {
          try await context.perform {
            do {
                try cancellation.check()
                guard let target = try context.existingObject(with: bookID) as? Book,
                      let newSource = try context.existingObject(with: sourceID) as? BookSource,
                      !target.isDeleted, !newSource.isDeleted,
                      target.origin == original.origin, target.bookUrl == original.bookUrl else {
                    throw CancellationError()
                }
                let index = ReadingProgressMapper.chapterIndex(
                    previousIndex: Int(target.durChapterIndex), previousCount: Int(target.totalChapterNum),
                    title: target.durChapterTitle, newTitles: chapters.map(\.title)
                )
                let sameBook = original.bookUrl == metadata.bookUrl &&
                    (target.source?.objectID == sourceID || original.origin == definition.bookSourceUrl ||
                     original.origin == definition.sourceId.uuidString)
                let oldPosition = target.durChapterPos
                let oldChapter = (target.chapters as? Set<BookChapter>)?.first { $0.index == target.durChapterIndex }
                let preservePosition = sameBook && oldChapter?.chapterUrl == chapters[index].url
                var previousCache: [String: (Bool, String?, String?)] = [:]
                if let oldChapters = target.chapters as? Set<BookChapter> {
                    if sameBook {
                        for chapter in oldChapters { previousCache[chapter.chapterUrl] = (chapter.isCached, chapter.cachePath, chapter.contentHash) }
                    }
                    for chapter in oldChapters { context.delete(chapter) }
                }
                target.origin = definition.bookSourceUrl
                target.originName = definition.bookSourceName
                target.bookUrl = metadata.bookUrl
                target.tocUrl = metadata.tocUrl
                target.tocHtml = metadata.tocHtml
                target.coverUrl = metadata.coverUrl
                target.intro = metadata.intro
                target.kind = metadata.kind
                target.latestChapterTitle = metadata.latestChapterTitle
                target.source = newSource
                target.updatedAt = Date()
                for web in chapters {
                    let chapter = BookChapter.create(in: context, bookId: target.bookId, url: web.url,
                                                     index: Int32(clamping: web.index), title: web.title)
                    chapter.book = target
                    chapter.sourceId = definition.sourceId.uuidString
                    chapter.isVIP = web.isVip
                    if let cache = previousCache[web.url] {
                        chapter.isCached = cache.0
                        chapter.cachePath = cache.1
                        chapter.contentHash = cache.2
                    }
                }
                target.totalChapterNum = Int32(clamping: chapters.count)
                target.durChapterIndex = Int32(clamping: index)
                target.durChapterTitle = chapters[index].title
                target.durChapterPos = preservePosition ? oldPosition : 0
                target.downloadUrls = metadata.downloadUrls
                target.wordCount = metadata.wordCount
                try cancellation.check()
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
          }
        }, onCancel: { cancellation.cancel() })
        try await ManagedObjectAccess.update(book) { book in
            book.managedObjectContext?.refresh(book, mergeChanges: true)
        }
    }
}

private final class DirectoryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }

    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
}
